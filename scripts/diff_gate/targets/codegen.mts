#!/usr/bin/env node
// codegen_diff —— S5 字节码生成层差分对拍（#273 差分族重构批；原 scripts/codegen_diff/main.go）。
//
// **整体接管型 target**（走 DiffTarget.override）：三件事让骨架默认路径装不下它——
//   ① cases 存的是**判定记录**（`{result_sha}` 或 `{fail, fail_stage}`）而非哈希串，
//      靠 flatten（ok → sha / fail → "FAIL:<stage>"）套进 GoldenSection；
//   ② `dump` 段必须保留**原始字节**——含 u64 位模式（globals_init_64 第二元 > 2^53），
//      JSON.parse 往返会丢末位（Go 端用 json.RawMessage 正是为此）；
//   ③ 两类非 case 级校验：verify（#200 P0 bytecode 结构验证）+ slot_strategy 版本对账。
//
// **不迁（oracle 侧）**：rustDumpBatch / runCorpus 的 oracle 双臂比对 / `--baseline`
// 的 DIFF-ONE-SIDED 豁免 / writeCgManifest+verifyCgManifest（freeze 时写盘）。
// 工序④删区后 oracle 永不存在；`--freeze` 必然 fail。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { canonicalize } from "../../internal/canonicalize.mts";
import { makeFail } from "../../internal/genio.mts";
import { sha16 } from "../../internal/diffgate.mts";
import type { DiffTarget, Fail, GateContext, GoldenSection, GoldenStore } from "../../internal/diffgate.mts";

export function fatal(msg: string): never {
  return makeFail("codegen_diff: ", 1)(msg);
}

const GOLDEN_REL = "scripts/codegen_diff/golden_digest.json";
const SLOT_REL = "scripts/codegen_diff/slot_strategy.json";
const DUMP_SUB = "cmd/dump_compile";

const KNOWN_FORKS: Record<string, string> = {
  "function_pointer_return_ptr.c": "局部函数指针双层→C 单层（F3-v2）——codegen 消费面放大（symbols.ty）",
  "kr_5_11.c": "局部函数原型双层→C 单层（F3-v2）——codegen 消费面放大",
};

// ---- digest 形状（codegen 私有：version/note/corpora，cases 是判定记录） ----

interface CgEntry {
  result_sha?: string;
  fail?: boolean;
  fail_stage?: string;
}
interface CgSec {
  sources: Record<string, string>;
  cases: Record<string, CgEntry>;
}
interface CgDoc {
  version: number;
  note: string;
  corpora: Record<string, CgSec>;
}

const CG_NOTE = "freeze 时已全量对拍（SAME/AGREE-ERROR/FORK）；golden = mb 指纹 ≡ 清单";

function loadCg(root: string, fail: Fail): CgDoc {
  const p = path.join(root, GOLDEN_REL);
  const empty: CgDoc = { version: 1, note: CG_NOTE, corpora: {} };
  if (!fs.existsSync(p)) return empty;
  let d: CgDoc;
  try {
    d = JSON.parse(fs.readFileSync(p, "utf8")) as CgDoc;
  } catch {
    return fail(`digest 清单坏或版本不识 ${GOLDEN_REL}`);
  }
  if (d.version !== 1) fail(`digest 清单坏或版本不识 ${GOLDEN_REL}`);
  return { version: 1, note: d.note ?? CG_NOTE, corpora: d.corpora ?? {} };
}

/** Go MarshalIndent：顶层 struct 序（version→note→corpora）+ map 键字节序。 */
function serializeCg(d: CgDoc): string {
  const q = (s: string): string => JSON.stringify(s);
  const entry = (e: CgEntry): string => {
    const parts: string[] = [];
    if (e.result_sha !== undefined) parts.push(`"result_sha": ${q(e.result_sha)}`);
    if (e.fail === true) parts.push(`"fail": true`);
    if (e.fail_stage !== undefined) parts.push(`"fail_stage": ${q(e.fail_stage)}`);
    // 缩进层级：corpora(4) → 节(6) → cases(8) → case 键(8) → 条目字段(10)，闭合条目回 8
    return parts.length === 0 ? "{}" : "{\n" + parts.map((p) => `          ${p}`).join(",\n") + "\n        }";
  };
  const mapBody = (m: Record<string, string>, indent: string): string => {
    const keys = Object.keys(m).sort();
    if (keys.length === 0) return "{}";
    return "{\n" + keys.map((k) => `${indent}  ${q(k)}: ${q(m[k] ?? "")}`).join(",\n") + "\n" + indent + "}";
  };
  const sec = (s: CgSec): string =>
    `{\n      "sources": ${mapBody(s.sources, "      ")},\n      "cases": ${mapCases(s.cases)}\n    }`;
  const mapCases = (m: Record<string, CgEntry>): string => {
    const keys = Object.keys(m).sort();
    if (keys.length === 0) return "{}";
    return "{\n" + keys.map((k) => `        ${q(k)}: ${entry(m[k] ?? {})}`).join(",\n") + "\n      }";
  };
  const corporaKeys = Object.keys(d.corpora).sort();
  const corporaBody =
    corporaKeys.length === 0
      ? "{}"
      : "{\n" +
        corporaKeys.map((c) => `    ${q(c)}: ${sec(d.corpora[c] ?? { sources: {}, cases: {} })}`).join(",\n") +
        "\n  }";
  return `{\n  "version": ${d.version},\n  "note": ${q(d.note)},\n  "corpora": ${corporaBody}\n}\n`;
}

function saveCg(root: string, d: CgDoc, fail: Fail): void {
  const p = path.join(root, GOLDEN_REL);
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, serializeCg(d), { mode: 0o644 });
  } catch (e) {
    fail(`写 digest 清单失败 ${GOLDEN_REL}: ${(e as Error).message}`);
  }
}

// ---- GoldenStore：判定记录 ↔ GoldenSection 的 flatten ----

const FAIL_PREFIX = "FAIL:";

function makeCgStore(root: string): GoldenStore {
  return {
    missingHint: "先 --freeze",
    load(corpusName: string): GoldenSection | null {
      const sec = loadCg(root, fatal).corpora[corpusName];
      if (sec === undefined) return null;
      const cases: Record<string, string> = {};
      for (const [name, e] of Object.entries(sec.cases)) {
        cases[name] = e.fail === true ? `${FAIL_PREFIX}${e.fail_stage ?? ""}` : (e.result_sha ?? "");
      }
      return { sources: sec.sources ?? {}, cases };
    },
    save(corpusName: string, s: GoldenSection): void {
      const d = loadCg(root, fatal);
      const cases: Record<string, CgEntry> = {};
      for (const [name, flat] of Object.entries(s.cases)) {
        if (flat.startsWith(FAIL_PREFIX)) {
          cases[name] = { fail: true, fail_stage: flat.slice(FAIL_PREFIX.length) };
        } else {
          cases[name] = { result_sha: flat };
        }
      }
      d.corpora[corpusName] = { sources: s.sources, cases };
      saveCg(root, d, fatal);
    },
  };
}

// ---- 产物解析：dump 段保留原始字节 ----

/**
 * 从 JSON 文本里提取某键的**原始值子串**（不解析、不重编）。
 * 必需：`dump` 段含 u64 位模式（globals_init_64 第二元 > 2^53），
 * JSON.parse 往返会丢末位——Go 端用 json.RawMessage 正是为此。
 */
export function rawField(text: string, key: string): string | undefined {
  const needle = `"${key}"`;
  let i = text.indexOf(needle);
  while (i >= 0) {
    // 确认是对象键而非字符串内容：键后紧跟冒号（允许空白）
    let j = i + needle.length;
    while (j < text.length && (text[j] === " " || text[j] === "\t" || text[j] === "\n" || text[j] === "\r")) j++;
    if (text[j] === ":") {
      j++;
      while (j < text.length && /\s/.test(text[j] ?? "")) j++;
      const start = j;
      const end = scanValue(text, j);
      if (end > start) return text.slice(start, end);
    }
    i = text.indexOf(needle, i + 1);
  }
  return undefined;
}

/** 从 pos 起扫描一个 JSON 值的结束位置（配平 / 字符串转义）。 */
function scanValue(s: string, pos: number): number {
  const c = s[pos];
  if (c === undefined) return pos;
  if (c === '"') {
    let i = pos + 1;
    while (i < s.length) {
      if (s[i] === "\\") {
        i += 2;
        continue;
      }
      if (s[i] === '"') return i + 1;
      i++;
    }
    return i;
  }
  if (c === "{" || c === "[") {
    let depth = 0;
    let i = pos;
    let inStr = false;
    while (i < s.length) {
      const ch = s[i];
      if (inStr) {
        if (ch === "\\") {
          i += 2;
          continue;
        }
        if (ch === '"') inStr = false;
        i++;
        continue;
      }
      if (ch === '"') {
        inStr = true;
        i++;
        continue;
      }
      if (ch === "{" || ch === "[") depth++;
      else if (ch === "}" || ch === "]") {
        depth--;
        if (depth === 0) return i + 1;
      }
      i++;
    }
    return i;
  }
  // 数字 / true / false / null：吃到定界符
  let i = pos;
  while (i < s.length && !",}] \t\n\r".includes(s[i] ?? "")) i++;
  return i;
}

interface MoonDoc {
  ok: boolean;
  stage: string;
  slot: number;
  dump: string;
  verifyOK: boolean | null;
}

export function parseMoonDoc(raw: Buffer): MoonDoc {
  const text = raw.toString("latin1");
  // 外层小值字段走 JSON.parse（值域小，无 u64 精度问题）
  const outer = JSON.parse(raw.toString("utf8")) as {
    ok?: boolean;
    stage?: string;
    slot_strategy?: number;
    verify?: { ok?: boolean; violations?: unknown };
  };
  const dump = rawField(text, "dump") ?? "";
  return {
    ok: outer.ok === true,
    stage: outer.stage ?? "",
    slot: typeof outer.slot_strategy === "number" ? outer.slot_strategy : -1,
    dump,
    verifyOK: outer.verify === undefined ? null : outer.verify.ok === true,
  };
}

/** dump 产物定位：`<stem>.c.compile.json` 优先，退 `<stem>.compile.json`。 */
function compileRawOf(moonDir: string, file: string, fail: Fail): Buffer {
  const base = path.basename(file);
  const stem = base.slice(0, base.length - path.extname(base).length);
  for (const name of [`${stem}.c.compile.json`, `${stem}.compile.json`]) {
    const p = path.join(moonDir, name);
    if (fs.existsSync(p)) return fs.readFileSync(p);
  }
  return fail(`MoonBit 侧输出缺失: ${stem}`);
}

// ---- 差异面：runCases + 两类额外校验 ----

/** slot 对账期望（rules 外置；本值由人工维护）。 */
function slotExpect(root: string, fail: Fail): number {
  try {
    const r = JSON.parse(fs.readFileSync(path.join(root, SLOT_REL), "utf8")) as { schema?: number; expected?: number };
    if (r.schema !== 1) fail(`槽位策略期望 schema 不支持: ${String(r.schema)}（期望 1）`);
    return r.expected ?? -1;
  } catch (e) {
    return fail(`读槽位策略期望失败: ${(e as Error).message}`);
  }
}

export function runCodegenCases(ctx: GateContext, fail: Fail = fatal): Map<string, string> {
  const files = fs
    .readdirSync(ctx.corpus)
    .filter((n) => n.endsWith(".c"))
    .sort();
  if (files.length === 0) fail(`语料目录无 .c 文件: ${ctx.corpus}`);
  // 注：dump_compile 的产物是**文件**（每样本一个 .compile.json），stdout 不参与
  // 判定，故走 moon run 无流混排问题（与 vm 的 exe 直跑不同）。
  spawnMoon(ctx, fail);

  const out = new Map<string, string>();
  const slotSeen = new Map<number, number>();
  const verifyErrors: string[] = [];
  lastSlotSeen = slotSeen;
  lastVerifyErrors = verifyErrors;

  for (const f of files) {
    const raw = compileRawOf(ctx.workDir, f, fail);
    const gd = parseMoonDoc(raw);
    if (gd.ok) {
      // verify（#200 P0）：ok 例必携带；缺字段 = 协议缺位，ok=false = 结构违约
      if (gd.verifyOK === null) {
        verifyErrors.push(`${f}: ok 例缺 verify 字段——dump_compile 出口协议缺位（#200 P0）`);
      } else if (!gd.verifyOK) {
        verifyErrors.push(`${f}: bytecode 结构验证违约（#200 P0 verify）`);
      }
      slotSeen.set(gd.slot, (slotSeen.get(gd.slot) ?? 0) + 1);
      out.set(f, sha16(canonicalize(Buffer.from(gd.dump, "latin1"))));
    } else {
      out.set(f, `${FAIL_PREFIX}${gd.stage}`);
    }
  }
  return out;
}

let lastSlotSeen = new Map<number, number>();
let lastVerifyErrors: string[] = [];

function spawnMoon(ctx: GateContext, fail: Fail): void {
  const r = spawnSync(
    "moon",
    ["-C", "moonbit", "run", "--target", "native", DUMP_SUB, "--", ctx.corpus, ctx.workDir],
    { cwd: ctx.root, encoding: "utf8", timeout: 600_000, maxBuffer: 64 * 1024 * 1024 },
  );
  if (r.status !== 0) fail(`moon run ${DUMP_SUB} 执行失败: exit ${String(r.status)}\n${(r.stdout ?? "") + (r.stderr ?? "")}`);
}

const codegenExtraChecks = (ctx: GateContext): string[] => {
  const errs: string[] = [...lastVerifyErrors];
  // slot_strategy 版本对账（Rust 侧产物无该字段，故为单向期望对账；空集亦红）
  const expect = slotExpect(ctx.root, fatal);
  let total = 0;
  for (const c of lastSlotSeen.values()) total += c;
  if (total === 0) {
    errs.push("slot_strategy=FAIL——无任何成功样本携带外层字段可供对账");
    return errs;
  }
  const parts: string[] = [];
  for (const [v, c] of [...lastSlotSeen.entries()].sort((a, b) => a[0] - b[0])) {
    let tag = `${v}×${c}`;
    if (v !== expect) tag += "(≠期望)";
    parts.push(tag);
  }
  process.stdout.write(
    `codegen_diff: slot_strategy=${parts.join(", ")}（期望 ${expect}；Rust 侧无该字段，见 slot_strategy.json）\n`,
  );
  if ([...lastSlotSeen.keys()].some((v) => v !== expect)) {
    errs.push(
      `槽位策略已变更——须同步 codegen 包 SLOT_STRATEGY_VERSION、slot_strategy.json，并重跑全量 A 级对拍（v2 前提见 JSON 的 _v2_plan）`,
    );
  }
  return errs;
};

export const codegenTarget: DiffTarget = {
  name: "codegen_diff",
  fail: fatal,
  golden: (root: string) => makeCgStore(root),
  corpusExts: [".c"],
  sourcesPolicy: "presence",
  knownForks: KNOWN_FORKS,
  extraChecks: codegenExtraChecks,
  runCases: (ctx: GateContext) => runCodegenCases(ctx),
};

export { loadCg, serializeCg };
