#!/usr/bin/env node
// parser_diff —— S3 解析层差分对拍（#273 差分族重构批；原 scripts/parser_diff/main.go）。
//
// 与 lexer/typeck 的真差异：
//   ① **三种合成语料模式**：`--pathological` / `--legal-deep` / `--threshold`
//      不吃 corpus 位置参数——自己造样本写临时目录，再走同一套 golden 比对
//      （digest 里对应独立节，节名不带 corpus- 前缀）
//   ② 语料集只吃 `.c`
//   ③ 判红退出码 2
//
// **不迁（原 Go 的 oracle 分支）**：pathological/legal_deep/threshold 三个模式在
// 非 golden 形态下会与 Rust oracle 逐字节对拍，其中 `--threshold` 的 C 族还做
// 「类型骨架形状断言」（mtype / skeleton / dumpDoc / 4 个 pick 函数，约 200 行）。
// 工序④删区后这些分支在 golden 模式下都提前 `return goldenRun(...)`，oracle 分支
// 永不可达——与 gen_diag/gen_diagnostics 同批裁定，整块不迁。
import fs from "node:fs";
import path from "node:path";
import { canonicalize } from "../../internal/canonicalize.mts";
import {
  makeModesStore,
  type ModesDigest,
} from "../../internal/modesdigest.mts";
import {
  moonDump,
  sha16,
  type DiffTarget,
  type Fail,
  type GateContext,
  type GoldenStore,
  type SyntheticMode,
} from "../../internal/diffgate.mts";
import { makeFail } from "../../internal/genio.mts";

/** 判红出口：parser 历史口径是 exit 2。 */
export function fatal(msg: string): never {
  return makeFail("parser_diff: ", 2)(msg);
}

const GOLDEN_REL = "scripts/parser_diff/golden_digest.json";
const NOTE = "freeze 时已全量对拍；golden = mb 归一 hash ≡ 清单；fork 例 golden 跳过";

/** 合成语料模式的节名（不带 corpus- 前缀）。 */
const SYNTH_SECTIONS = new Set(["pathological", "legal_deep", "threshold"]);

const rep = (s: string, n: number): string => s.repeat(n);

/** E3 病态 12 样本（原 Go pathologicalSamples 逐条照搬）。 */
const PATHOLOGICAL: { name: string; src: string }[] = [
  { name: "paren_63", src: "int main() { return " + rep("(", 63) + "1" + rep(")", 63) + "; }" },
  { name: "brace_300", src: "int main() {" + rep("{", 300) + rep("}", 300) + "return 0; }" },
  {
    name: "init_list_3000",
    src: "int a[3000] = " + rep("{", 3000) + "1" + rep("}", 3000) + "; int main() { return 0; }",
  },
  { name: "assign_chain_3000", src: "int main() { int a = 0; a" + rep(" = a", 3000) + "; return a; }" },
  { name: "unary_chain_5000", src: "int main() { return " + rep("!", 5000) + "1; }" },
  { name: "pointer_chain_100", src: "int " + rep("*", 100) + " p; int main() { return 0; }" },
  { name: "postfix_chain_5000", src: "int main() { int a[1]; return a" + rep("[0]", 5000) + "; }" },
  { name: "decl_suffix_1300", src: "int a" + rep("[1]", 1300) + ";" },
  { name: "typedef_suffix_1500", src: "typedef int T" + rep("[1]", 1500) + ";" },
  { name: "sizeof_abstract_1400", src: "int main() { return sizeof(int" + rep("[1]", 1400) + "); }" },
  { name: "param_suffix_1500", src: "int f(int a" + rep("[1]", 1500) + ") { return 0; }" },
  { name: "field_suffix_1500", src: "struct S { int a" + rep("[1]", 1500) + "; };" },
];

/** E4 合法深嵌套反向锚（2 例）。 */
const LEGAL_DEEP: { name: string; src: string }[] = [
  {
    name: "paren_30_add_100",
    src: "int main() { return " + rep("(", 30) + "1" + rep(" + 1", 100) + rep(")", 30) + "; }",
  },
  { name: "decl_suffix_1200", src: "int a" + rep("[1]", 1200) + "; int main() { return 0; }" },
];

/** offsetof 嵌套深链（F1 病灶形状）。 */
function offsetofChain(k: number): string {
  let s = "offsetof(struct{int a[0];},a)";
  for (let i = 0; i < k; i++) s = "offsetof(struct{int a[" + s + "];},a)";
  return s;
}
const enumChain = (n: number): string => "enum E { A = " + rep("1+", n - 1) + "1 };\nint main() { return 0; }\n";
const sassertChain = (n: number): string =>
  "_Static_assert(" + rep("1+", n - 1) + "1, \"x\");\nint main() { return 0; }\n";

/** E3+ 阈值 A/B 族（7 例；C 族 16 例只比 hash，见下）。 */
const THRESHOLD_AGREE: { name: string; src: string }[] = [
  { name: "offsetof_16", src: "int main() { return " + offsetofChain(16) + "; }\n" },
  { name: "offsetof_64", src: "int main() { return " + offsetofChain(64) + "; }\n" },
  { name: "offsetof_128", src: "int main() { return " + offsetofChain(128) + "; }\n" },
  { name: "offsetof_140", src: "int main() { return " + offsetofChain(140) + "; }\n" },
  { name: "enum_add_600", src: enumChain(600) },
  { name: "enum_add_1200", src: enumChain(1200) },
  { name: "sassert_add_1200", src: sassertChain(1200) },
];

/**
 * E3+ 阈值 C 族（16 例）：指针括号 + 多维数组的 C 语义折叠样本。
 * golden 模式只比 hash，故此处只需源码；原 Go 的 `want` 骨架期望与
 * `pick` 提取函数属 oracle 分支的形状断言，未迁。
 */
const THRESHOLD_SHAPE: { name: string; src: string }[] = [
  { name: "shape_ptrarr_guard", src: "int *p0[2];\nint main() { return 0; }\n" },
  { name: "shape_arrptr_dim1_guard", src: "int (*p3)[5];\nint main() { return 0; }\n" },
  { name: "shape_arrptr_dim2", src: "int (*p1)[2][3];\nint main() { return 0; }\n" },
  { name: "shape_arrptr_dim3", src: "int (*p2)[2][3][4];\nint main() { return 0; }\n" },
  { name: "shape_arrptr_field", src: "struct S1 { int (*f)[2][3]; };\nint main() { return 0; }\n" },
  { name: "shape_arrptr_param", src: "int g1(int (*p)[2][3]) { return 0; }\nint main() { return 0; }\n" },
  { name: "shape_arrptr_abstract", src: "int m1 = sizeof(int (*)[2][3]);\nint main() { return m1; }\n" },
  { name: "shape_arrptr_typedef", src: "typedef int (*Q1)[2][3];\nQ1 x;\nint main() { return 0; }\n" },
  { name: "shape_arrptr_inner_dim", src: "int (*q1[2])[3][4];\nint main() { return 0; }\n" },
  { name: "shape_arrptr_inner_dim23", src: "int (*q2[2][3])[4][5];\nint main() { return 0; }\n" },
  { name: "shape_dblptr_arrptr", src: "int (*(*q3)[2][3])[4][5];\nint main() { return 0; }\n" },
  { name: "shape_ptrarr_dim23", src: "int *q4[2][3];\nint main() { return 0; }\n" },
  { name: "shape_fnret_arrptr", src: "int (*h1(void))[2][3];\nint main() { return 0; }\n" },
  { name: "shape_fnptr_ret_arrptr", src: "int (*(*h2)(void))[2][3];\nint main() { return 0; }\n" },
  { name: "shape_fnptr_guard", src: "int (*fp9)(void);\nint main() { return 0; }\n" },
  { name: "shape_fnptr_arr_guard", src: "int (*fp8[2])(void);\nint main() { return 0; }\n" },
];

/** 有意分叉例（局部函数指针/原型双层 → C 语义单层，F3-v2）。 */
const KNOWN_FORKS: Record<string, string> = {
  "function_pointer_return_ptr.c": "局部函数指针双层→C 单层（F3-v2）",
  "kr_5_11.c": "局部函数原型双层→C 单层（F3-v2）",
};

/**
 * threshold 模式的 C 族（shape_*）= 裁定 b 的**有意分叉**：清单里登记的 oracle
 * hash 仅供溯源，形状正确性由 wbtest 锚守。Go 版在 goldenRun 里以
 * `mode == "threshold" && thresholdShapeSampleOf(name)` 整体跳过——此处按
 * （节, case）判定同一语义。
 */
const SHAPE_FORK_REASON = "有意分叉例（裁定 b 撕裂折叠），形状校验走现模式/wbtest 锚";

function parserFork(corpusName: string, caseName: string): string | undefined {
  if (corpusName === "threshold" && caseName.startsWith("shape_")) return SHAPE_FORK_REASON;
  return KNOWN_FORKS[caseName];
}

function writeSamples(tmpDir: string, samples: { name: string; src: string }[], what: string): void {
  try {
    for (const s of samples) fs.writeFileSync(path.join(tmpDir, s.name + ".c"), s.src);
  } catch (e) {
    fatal(`${what} 写入失败: ${(e as Error).message}`);
  }
}

const SYNTH: Record<string, SyntheticMode> = {
  "--pathological": {
    section: "pathological",
    prepare: (tmp) => writeSamples(tmp, PATHOLOGICAL, "病态样本"),
  },
  "--legal-deep": {
    section: "legal_deep",
    prepare: (tmp) => writeSamples(tmp, LEGAL_DEEP, "E4 样本"),
  },
  "--threshold": {
    section: "threshold",
    prepare: (tmp) => {
      writeSamples(tmp, THRESHOLD_AGREE, "阈值样本");
      writeSamples(tmp, THRESHOLD_SHAPE, "阈值样本");
    },
  },
};

function makeParserGolden(root: string): GoldenStore {
  return makeModesStore(
    root,
    GOLDEN_REL,
    NOTE,
    "先 --freeze",
    (n) => (SYNTH_SECTIONS.has(n) ? n : "corpus-" + n),
    fatal,
  );
}

export { makeParserGolden };

/** 单样本产物定位：`<stem>.c.ast.json` 优先，退 `<stem>.ast.json`。 */
function astRawOf(moonDir: string, file: string, fail: Fail): Buffer {
  const base = path.basename(file);
  const stem = base.slice(0, base.length - path.extname(base).length);
  for (const name of [`${stem}.c.ast.json`, `${stem}.ast.json`]) {
    const p = path.join(moonDir, name);
    if (fs.existsSync(p)) return fs.readFileSync(p);
  }
  return fail(`MoonBit 侧输出缺失: ${stem}`);
}

export function runParserCases(ctx: GateContext, fail: Fail = fatal): Map<string, string> {
  const files = fs
    .readdirSync(ctx.corpus)
    .filter((n) => n.endsWith(".c"))
    .sort();
  if (files.length === 0) fail(`语料目录无 .c 文件: ${ctx.corpus}`);
  moonDump(ctx.root, "cmd/dump_ast", [ctx.corpus, ctx.workDir], fail);
  const out = new Map<string, string>();
  for (const f of files) {
    out.set(f, sha16(canonicalize(astRawOf(ctx.workDir, f, fail))));
  }
  return out;
}

export const parserTarget: DiffTarget = {
  name: "parser_diff",
  fail: fatal,
  golden: (root: string) => makeParserGolden(root),
  corpusExts: [".c"],
  knownForks: parserFork,
  sourcesPolicy: "presence",
  syntheticModes: SYNTH,
  runCases: (ctx: GateContext) => runParserCases(ctx),
};

/** 供测试引用：阈值 A/B + C 族合计条数（与入库 golden 的 threshold 节对账）。 */
export const THRESHOLD_SAMPLE_COUNT = THRESHOLD_AGREE.length + THRESHOLD_SHAPE.length;

export type { ModesDigest };
