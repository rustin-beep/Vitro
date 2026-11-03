// W4 第四臂对拍——纯函数库（抽样 / 帧构造 / include 收集 / 逐位对比）。
// CLI 壳见 main.mts；两侧跑器见 rs/（wasmtime）与 host_node.mts（V8）。
// 纪律 8 字节确定性口径：JSON 键序显式构造；偏移/长度一律 Buffer.byteLength
// 字节口径；对比在 Buffer 层逐字节（不经 string 解码，避免编码层掩盖分叉）。

import { createHash } from "node:crypto";

// ── 抽样 ──────────────────────────────────────────────────────────────

/** 确定性 PRNG（mulberry32）——seed 固定则抽样可复现。 */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Fisher–Yates 前 k 项（seed 确定性）；k ≥ n 时返回全量（保持字典序稳定）。 */
export function sampleK<T>(items: readonly T[], k: number, rnd: () => number): T[] {
  const arr = items.slice();
  if (k >= arr.length) return arr;
  for (let i = 0; i < k; i++) {
    const j = i + Math.floor(rnd() * (arr.length - i));
    const tmp = arr[i] as T;
    arr[i] = arr[j] as T;
    arr[j] = tmp;
  }
  return arr.slice(0, k);
}

export interface SuiteFiles {
  suite: string;
  files: string[]; // 相对 corpus/ 的 posix 路径，已字典序
}

export interface SampleSpec {
  quotas: Record<string, number>; // suite → 份数
  /** 必含清单（相对 corpus/ 路径）——特征覆盖（include / 已知异常路径等），不占配额。 */
  mustInclude: string[];
}

/** 工程模式目录（一级子目录 = 一个工程 case；与 clang_direct projectCorpusDirs 同约定）。 */
export const PROJECT_SUITES: ReadonlySet<string> = new Set(["llm_multifile"]);

/** 配额键必须是 corpus 根目录（审阅 P3：未知 suite 静默忽略 = 抽样面无声塌缩，fail loud）。 */
export function validateQuotaKeys(quota: Record<string, number>, roots: readonly string[]): void {
  const known = new Set(roots);
  for (const k of Object.keys(quota)) {
    if (!known.has(k)) {
      throw new Error(`--quota 未知 suite '${k}'（corpus 根目录全集：${roots.slice().sort(byteOrder).join(" / ")}）`);
    }
  }
}

/** 分层抽样：每 suite 独立 seed 派生（suite 名哈希），加 mustInclude 去重并稳定排序。 */
export function stratifiedSample(suites: SuiteFiles[], spec: SampleSpec, seed: number): string[] {
  const chosen = new Set<string>(spec.mustInclude);
  for (const s of suites) {
    const quota = spec.quotas[s.suite] ?? 0;
    if (quota <= 0) continue;
    const rnd = mulberry32(seed ^ fnv1a32(s.suite));
    for (const f of sampleK(s.files, quota, rnd)) chosen.add(f);
  }
  return Array.from(chosen).sort(byteOrder);
}

export function fnv1a32(s: string): number {
  let h = 0x811c9dc5;
  for (const b of Buffer.from(s, "utf8")) {
    h ^= b;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** 字节字典序（与 Go sort.Strings / canonicalize 口径一致）。 */
export function byteOrder(a: string, b: string): number {
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

// ── include 收集（cmd/vitro_wasm collect_walk 语义复刻）──────────────

export function dirOf(p: string): string {
  let last = -1;
  for (let i = 0; i < p.length; i++) {
    const c = p.charCodeAt(i);
    if (c === 47 || c === 92) last = i;
  }
  if (last === 0) return "/";
  if (last < 0) return ".";
  return p.slice(0, last);
}

export function baseName(p: string): string {
  let idx = -1;
  for (let i = 0; i < p.length; i++) {
    const c = p.charCodeAt(i);
    if (c === 47 || c === 92) idx = i;
  }
  return idx < 0 ? p : p.slice(idx + 1);
}

export function normalizeRel(p: string): string {
  const parts: string[] = [];
  for (const seg of p.split("/")) {
    if (seg === "..") parts.pop();
    else if (seg !== "." && seg !== "") parts.push(seg);
  }
  return parts.join("/");
}

export function vfsKeyFor(parentName: string, inc: string): string {
  return normalizeRel(dirOf(parentName) + "/" + inc);
}

export function joinDir(dir: string, name: string): string {
  return dir === "." ? name : `${dir}/${name}`;
}

const INCLUDE_RE = /^[ \t]*#[ \t]*include[ \t]*"([^"]+)"/;

export function scanQuoteIncludes(src: string): string[] {
  const out: string[] = [];
  for (const line of src.split("\n")) {
    const m = INCLUDE_RE.exec(line);
    if (m && m[1] !== undefined) out.push(m[1]);
  }
  return out;
}

export interface FileEntry {
  filename: string;
  source: string;
}

/** 递归收集主文件及其 quote-include 闭包；read 读失败回 null 则跳过。 */
export function collectFiles(
  mainPath: string,
  mainSrc: string,
  read: (p: string) => string | null,
): FileEntry[] {
  const entries: FileEntry[] = [];
  const seen = new Set<string>();
  const walk = (p: string, name: string, src: string): void => {
    if (seen.has(name)) return;
    seen.add(name);
    entries.push({ filename: name, source: src });
    for (const inc of scanQuoteIncludes(src)) {
      const incPath = joinDir(dirOf(p), inc);
      const incSrc = read(incPath);
      if (incSrc !== null && incSrc !== "") walk(incPath, vfsKeyFor(name, inc), incSrc);
    }
  };
  walk(mainPath, baseName(mainPath), mainSrc);
  return entries;
}

// ── 每例实例复位标记（审阅 P2-3 处置）────────────────────────────────
//
// 单侧 trap 重建实例后两侧会话态历史不对称，期间的字节差判 CASCADE 本意是
// 归因级联；但 epoch 长期不等（实测 synth 轮 5/1 → 10/6）会把真分叉（如
// #420 note 泄漏）整段吸收。治本：每 case 首帧前双方强制重建实例——两侧在
// case 边界永远同一起点，CASCADE 面收敛到「case 内单侧 trap 之后」（语义正确
// 的窗口）。跑器识别 RESET_LINE 请求行即重建实例并回 RESET_ACK（两侧字面
// 相同，对比器据此把 epoch 归零）。`--shared` 退回共享实例形态（serve 真实
// 形态，观察用）。

export const RESET_LINE = '{"__w4_reset__":true}';
export const RESET_ACK = '{"__w4_reset__":"ok"}';
export const RESET_METHOD = "__reset__";

const RESET_ACK_BUF = Buffer.from(RESET_ACK, "utf8");

export function isResetAck(b: Buffer): boolean {
  return b.length === RESET_ACK_BUF.length && b.equals(RESET_ACK_BUF);
}

// ── 帧构造 ─────────────────────────────────────────────────────────────

export interface CaseInput {
  name: string; // 相对 corpus/ 的 posix 路径（语料身份）
  files: FileEntry[];
  stdin: string | null;
}

export type Profile = "run" | "deep-nomem" | "deep";
export const PROFILES: readonly Profile[] = ["run", "deep-nomem", "deep"];

/** 语料身份保留字：请求流开头的静态元数据族（进程级、与会话无关）。 */
export const STATIC_CASE = "__static__";

/**
 * 静态族前导帧（一次性）：ping / 五张静态表 / icons 全量 / texts 读-装-读闭环 /
 * config 档位切换往返 / destroy。`_` 常量供给面（wasmtime 侧手工 3864 条）主要
 * 经此族与 dump 族暴露。
 */
export function staticFrames(): string[] {
  const f = (id: number, method: string, params: unknown = {}): string => JSON.stringify({ id, method, params });
  return [
    f(1, "ping"),
    f(2, "capabilities"),
    f(3, "error_catalog"),
    f(4, "semantic_labels"),
    f(5, "contracts"),
    f(6, "algorithms.catalog"),
    f(7, "icons.get"),
    f(8, "texts.get"),
    f(9, "config.get"),
    f(10, "texts.install", { payload: '{"suggestions":{},"builtin_notes":{},"trap_messages":{},"error_catalog":{}}' }),
    f(11, "texts.get"),
    f(12, "config.set", { preset: "algo" }),
    f(13, "config.get"),
    f(14, "config.set", { preset: "default", max_steps: 10000000 }),
    f(15, "config.get"),
    f(16, "output.delta", { cursor: 0, stream: "bogus" }), // fail-loud 错误帧也是对拍面
    f(17, "no.such.method"),
    f(18, "session.destroy"),
  ];
}

export const STATIC_METHODS: readonly string[] = [
  "ping", "capabilities", "error_catalog", "semantic_labels", "contracts", "algorithms.catalog", "icons.get",
  "texts.get", "config.get", "texts.install", "texts.get#2", "config.set:algo", "config.get#2", "config.set:default",
  "config.get#3", "output.delta:bogus", "no.such.method", "session.destroy",
];

/** 每语料帧序列（按 profile）；键序显式构造。reset=true 时首帧为实例复位标记。 */
export function buildFrames(c: CaseInput, profile: Profile = "run", reset = true): string[] {
  const f = (id: number, method: string, params: unknown = {}): string => JSON.stringify({ id, method, params });
  const main = c.files[0];
  const mainSrc = main?.source ?? "";
  const mainName = main?.filename ?? "main.c";
  const frames: string[] = [];
  if (reset) frames.push(RESET_LINE);
  let id = 1;
  frames.push(f(id++, "session.create"));
  frames.push(f(id++, "compile", { files: c.files.map((x) => ({ filename: x.filename, source: x.source })) }));
  if (profile !== "run") {
    for (const m of ["ast.dump", "typeck.dump", "symbols.dump", "codegen.dump"]) {
      frames.push(f(id++, m, { source: mainSrc, filename: mainName }));
    }
  }
  const runParams: Record<string, unknown> = {};
  if (c.stdin !== null) runParams["input"] = c.stdin;
  frames.push(f(id++, "run", runParams));
  for (const stream of ["stdout", "stderr", "note"]) {
    frames.push(f(id++, "output.delta", { cursor: 0, stream }));
  }
  if (profile !== "run") {
    frames.push(f(id++, "memory.regions"));
    if (profile === "deep") frames.push(f(id++, "memory.dump"));
    frames.push(f(id++, "vfs.list"));
    frames.push(f(id++, "step.begin"));
    frames.push(f(id++, "step.next", { frames: 50 }));
    frames.push(f(id++, "payload.get"));
    frames.push(f(id++, "seek", { step: 10 }));
    frames.push(f(id++, "breakpoints.set", { lines: [5, 10] }));
    frames.push(f(id++, "step.next", { every: 7 }));
    frames.push(f(id++, "step.next", { frames: 30 }));
    frames.push(f(id++, "payload.get", { start: 0, end: 40 }));
    frames.push(f(id++, "session.destroy"));
  }
  return frames;
}

/** 与 buildFrames 同序的帧标签（对比报告用）。 */
export function frameMethods(profile: Profile, reset = true): string[] {
  const out: string[] = reset ? [RESET_METHOD] : [];
  out.push("session.create", "compile");
  if (profile !== "run") out.push("ast.dump", "typeck.dump", "symbols.dump", "codegen.dump");
  out.push("run", "output.delta:stdout", "output.delta:stderr", "output.delta:note");
  if (profile !== "run") {
    out.push("memory.regions");
    if (profile === "deep") out.push("memory.dump");
    out.push(
      "vfs.list", "step.begin", "step.next:frames50", "payload.get", "seek:10", "breakpoints.set",
      "step.next:every7", "step.next:frames30", "payload.get:0-40", "session.destroy",
    );
  }
  return out;
}

export interface ManifestCase {
  name: string;
  suite: string;
  has_stdin: boolean;
  file_count: number;
  frame_start: number; // 响应文件中的起始行号（0 基）
  frame_count: number;
  methods: string[]; // 与帧一一对应的标签
}

export interface Manifest {
  schema: "w4-manifest-v1";
  seed: number;
  profile: Profile;
  wasm_sha256: string;
  cases: ManifestCase[];
}

// ── 对抗性合成语料（--synth）────────────────────────────────────────
//
// 目标不是 C 语义而是 **runtime 差异面**：wasm 栈（深嵌套走引擎守卫还是
// 真递归）、js-string 供给层编码边界（lone surrogate / 代理对 / 高字节）、
// 大 buffer 路径（超长源码/stdin/输出）、步数超限 trap、algo 档长跑 GC 压力。
// 病态 12 样本与 legal_deep 照搬 scripts/diff_gate/targets/parser.mts。

const rep = (s: string, n: number): string => s.repeat(n);
/** 嵌套 struct 定义链（wasm 栈溢出触发面——W4 唯一 TRAP_ONE 形态）。 */
const structNest = (n: number): string =>
  rep("struct S {", n) + " int a; " + "} s;" + rep("} t;", n - 1) + "\nint main() { return 0; }";

export interface SynthCase {
  name: string;
  src: string;
  stdin?: string;
}

export function synthCases(): SynthCase[] {
  const out: SynthCase[] = [
    // 病态 12（E3 守卫面——两侧须同点拒绝）
    { name: "paren_63", src: "int main() { return " + rep("(", 63) + "1" + rep(")", 63) + "; }" },
    { name: "brace_300", src: "int main() {" + rep("{", 300) + rep("}", 300) + "return 0; }" },
    { name: "init_list_3000", src: "int a[3000] = " + rep("{", 3000) + "1" + rep("}", 3000) + "; int main() { return 0; }" },
    { name: "assign_chain_3000", src: "int main() { int a = 0; a" + rep(" = a", 3000) + "; return a; }" },
    { name: "unary_chain_5000", src: "int main() { return " + rep("!", 5000) + "1; }" },
    { name: "pointer_chain_100", src: "int " + rep("*", 100) + " p; int main() { return 0; }" },
    { name: "postfix_chain_5000", src: "int main() { int a[1]; return a" + rep("[0]", 5000) + "; }" },
    { name: "decl_suffix_1300", src: "int a" + rep("[1]", 1300) + ";" },
    { name: "typedef_suffix_1500", src: "typedef int T" + rep("[1]", 1500) + ";" },
    { name: "sizeof_abstract_1400", src: "int main() { return sizeof(int" + rep("[1]", 1400) + "); }" },
    { name: "param_suffix_1500", src: "int f(int a" + rep("[1]", 1500) + ") { return 0; }" },
    { name: "field_suffix_1500", src: "struct S { int a" + rep("[1]", 1500) + "; };" },
    // legal_deep 2
    { name: "paren_30_add_100", src: "int main() { return " + rep("(", 30) + "1" + rep(" + 1", 100) + rep(")", 30) + "; }" },
    { name: "decl_suffix_1200", src: "int a" + rep("[1]", 1200) + "; int main() { return 0; }" },
    // 更深变体（守卫之外若仍有递归路径，wasm 栈限差异在此暴露）
    { name: "paren_2000", src: "int main() { return " + rep("(", 2000) + "1" + rep(")", 2000) + "; }" },
    { name: "paren_20000", src: "int main() { return " + rep("(", 20000) + "1" + rep(")", 20000) + "; }" },
    { name: "brace_20000", src: "int main() {" + rep("{", 20000) + rep("}", 20000) + "return 0; }" },
    { name: "unary_chain_100000", src: "int main() { return " + rep("-", 100000) + "1; }" },
    { name: "add_chain_50000", src: "int main() { return 1" + rep(" + 1", 50000) + "; }" },
    { name: "ternary_chain_5000", src: "int main() { int x = 1; return " + rep("x ? ", 5000) + "1" + rep(" : 0", 5000) + "; }" },
    { name: "call_nest_5000", src: "int f(int x) { return x; }\nint main() { return " + rep("f(", 5000) + "1" + rep(")", 5000) + "; }" },
    { name: "if_nest_5000", src: "int main() { int x = 1;\n" + rep("if (x) {\n", 5000) + "x = 2;\n" + rep("}\n", 5000) + "return x; }" },
    { name: "struct_nest_2000", src: structNest(2000) },
    // 栈预算临界梯度（跑器默认 2MiB vs V8 默认 ~1MB——两侧临界不重合：V8 ∈
    // (4000,5000]、wasmtime 2MiB ∈(5000,6000]，均为 2026-11-03 实测）。梯度锚
    // 4000（双侧通过=AGREE）/ 6000（双侧溢出=TRAP_BOTH stack 类）——两档都在
    // 两侧各自临界的稳定侧，断言语义=「预算窗对齐不被回退」。**勿加 5000 档**：
    // 恰落在两临界之间，两侧必然 TRAP_ONE（wasmtime 过、V8 溢出）——预算型
    // 差异变 CI 常红，非语义分叉信号（#421 面）。
    ...[250, 500, 1000, 1500, 3000, 4000, 6000, 8000, 12000].map((n) => ({ name: `struct_nest_${n}`, src: structNest(n) })),
    { name: "comment_nest_deep", src: "int main() { return 0; }" + rep("/* ", 10000) + rep(" */", 10000) },
    { name: "macro_recursion", src: "#define A B\n#define B A\nint main() { return A; }" },
    { name: "macro_expand_deep", src: rep("#define M", 1) + "0 1\n" + Array.from({ length: 300 }, (_, i) => `#define M${i + 1} M${i}+M${i}`).join("\n") + "\nint main() { return M20; }" },
    { name: "include_self", src: '#include "include_self.c"\nint main() { return 0; }' },
    // 运行期深递归（VM 调用栈在引擎堆，不在 wasm 栈——call_depth_limit 守卫面）
    { name: "c_recursion_9000", src: "int f(int n) { return n == 0 ? 0 : 1 + f(n - 1); }\nint main() { printf(\"%d\\n\", f(9000)); return 0; }" },
    { name: "c_recursion_20000_trap", src: "int f(int n) { return n == 0 ? 0 : 1 + f(n - 1); }\nint main() { printf(\"%d\\n\", f(20000)); return 0; }" },
    { name: "c_recursion_infinite", src: "int f(int n) { return f(n + 1) + 1; }\nint main() { return f(0); }" },
    // 步数超限 / 长跑（GC 压力面）
    { name: "loop_infinite_trap", src: "int main() { volatile int x = 0; while (1) { x++; } return x; }" },
    { name: "loop_5M_steps", src: "int main() { long s = 0; for (int i = 0; i < 600000; i++) { s += i % 7; } printf(\"%ld\\n\", s); return 0; }" },
    { name: "malloc_churn", src: "#include <stdlib.h>\nint main() { long s = 0; for (int i = 0; i < 20000; i++) { int *p = malloc(64); p[0] = i; s += p[0]; free(p); } printf(\"%ld\\n\", s); return 0; }" },
    { name: "string_churn", src: "#include <string.h>\n#include <stdio.h>\nchar buf[4096];\nint main() { for (int i = 0; i < 3000; i++) { snprintf(buf, sizeof buf, \"%d-%s\", i, \"abcdefghijklmnopqrstuvwxyz\"); } printf(\"%s\\n\", buf); return 0; }" },
    // 输出字节域（Latin-1 折回 / 高字节 / NUL / 控制字符）
    { name: "putchar_high_bytes", src: "int main() { for (int c = 0; c < 256; c++) putchar(c); return 0; }" },
    { name: "printf_utf8_literal", src: "int main() { printf(\"héllo wörld — 你好 🎉\\n\"); return 0; }" },
    { name: "stdout_1MB", src: "int main() { for (int i = 0; i < 1048576; i++) putchar('A' + (i % 26)); return 0; }" },
    { name: "stdout_17MB_truncate", src: "int main() { for (int i = 0; i < 17825792; i++) putchar('x'); return 0; }" },
    { name: "stderr_mixed", src: "#include <stdio.h>\nint main() { for (int i = 0; i < 100; i++) { printf(\"o%d \", i); fprintf(stderr, \"e%d \", i); } return 3; }" },
    // 源码编码边界（供给层 UTF-16 语义：代理对 / lone surrogate / BOM / NUL）
    { name: "src_emoji_ident", src: "int main() { /* 🎉🎉🎉 */ int x = 1; return x; }" },
    { name: "src_lone_surrogate_comment", src: "int main() { /* \ud800 lone */ return 0; }" },
    { name: "src_lone_surrogate_string", src: "int main() { printf(\"\udc00\"); return 0; }" },
    { name: "src_surrogate_pair_string", src: "int main() { printf(\"\ud83c\udf89\\n\"); return 0; }" },
    { name: "src_bom_prefix", src: "\ufeffint main() { return 0; }" },
    { name: "src_nul_in_comment", src: "int main() { /* \u0000 */ return 0; }" },
    { name: "src_crlf", src: "int main() {\r\n  return 0;\r\n}\r\n" },
    { name: "src_all_bmp_sample", src: "int main() { /* " + Array.from({ length: 2000 }, (_, i) => String.fromCharCode(0x100 + i * 31)).join("") + " */ return 0; }" },
    // 超长源码（大 buffer 路径——fromCharCodeArray / concat）
    { name: "src_2MB_comment", src: "int main() { return 0; }\n/* " + rep("x", 2 * 1024 * 1024) + " */" },
    { name: "src_1MB_many_lines", src: Array.from({ length: 40000 }, (_, i) => `int v${i} = ${i};`).join("\n") + "\nint main() { return v39999 & 1; }" },
    // 规模缩放探针（O(n²) 判据：2× 规模 → 4× 时间）——src_1MB_many_lines 的 1/4、1/2
    { name: "src_250k_many_lines", src: Array.from({ length: 10000 }, (_, i) => `int v${i} = ${i};`).join("\n") + "\nint main() { return v9999 & 1; }" },
    { name: "src_500k_many_lines", src: Array.from({ length: 20000 }, (_, i) => `int v${i} = ${i};`).join("\n") + "\nint main() { return v19999 & 1; }" },
    { name: "src_long_string_literal", src: 'int main() { const char *s = "' + rep("ab", 200000) + '"; return s[0]; }' },
    // stdin 域
    { name: "stdin_1MB", src: "#include <stdio.h>\nint main() { long s = 0; int c; while ((c = getchar()) != EOF) s += c; printf(\"%ld\\n\", s); return 0; }", stdin: rep("0123456789\n", 100000) },
    { name: "stdin_utf8", src: "#include <stdio.h>\nint main() { int c, n = 0; while ((c = getchar()) != EOF) n++; printf(\"%d\\n\", n); return 0; }", stdin: "你好 🎉 é\n" },
    { name: "stdin_scanf_wait", src: "#include <stdio.h>\nint main() { int a, b; if (scanf(\"%d %d\", &a, &b) == 2) printf(\"%d\\n\", a + b); return 0; }", stdin: "7" },
    // 诊断密集（error_catalog 空表 lean 产物下的文案路径）
    { name: "diag_many_errors", src: Array.from({ length: 500 }, (_, i) => `int f${i}() { return undefined_${i}; }`).join("\n") + "\nint main() { return 0; }" },
    { name: "diag_type_mismatch_many", src: Array.from({ length: 300 }, (_, i) => `int *p${i} = ${i}.5;`).join("\n") + "\nint main() { return 0; }" },
    // 浮点文本化（Double::to_string 分歧面——双侧同引擎但经 runtime 浮点 op）
    { name: "float_edge_print", src: "#include <stdio.h>\n#include <math.h>\nint main() { double v[] = {0.1, 1e16, 1e-7, 1.0/3.0, -0.0, 1e300*1e300, 0.0/0.0, 123456789.123456789, 5e-324, 1.7976931348623157e308}; for (int i = 0; i < 10; i++) printf(\"%g %f %e %.17g\\n\", v[i], v[i], v[i], v[i]); printf(\"%f %f %f\\n\", sin(1.0), exp(10.0), pow(2.0, 0.5)); return 0; }" },
    { name: "int_edge_ops", src: "#include <stdio.h>\n#include <limits.h>\nint main() { int a = INT_MIN; long long b = LLONG_MIN; unsigned u = 0u - 1u; printf(\"%d %lld %u %d %lld\\n\", a / -1 == a, b % -1, u >> 31, a >> 31, (long long)a * a); printf(\"%d %d\\n\", 7 / -2, 7 % -2); return 0; }" },
  ];
  return out;
}

/** 请求行级对抗帧（静态族之后追加）：深嵌套 JSON / 超长参数 / 编码边界。 */
export function adversarialFrames(startId: number): { frames: string[]; methods: string[] } {
  const frames: string[] = [];
  const methods: string[] = [];
  let id = startId;
  const push = (label: string, line: string): void => {
    frames.push(line);
    methods.push(label);
    id += 1;
  };
  // 深嵌套 JSON（json_parse 递归面）——合法 JSON，params 为深数组
  for (const d of [100, 1000, 10000, 100000]) {
    push(`json_depth_${d}`, `{"id":${id},"method":"ping","params":${rep("[", d)}1${rep("]", d)}}`);
  }
  // 超长 params 字符串（1MB）
  push("params_1MB_string", `{"id":${id},"method":"compile","params":{"source":"${rep("x", 1024 * 1024)}"}}`);
  // 编码边界：lone surrogate / 代理对 / NUL / BOM 经 JSON 转义进字符串域
  push("params_lone_surrogate", `{"id":${id},"method":"compile","params":{"source":"int main() { /* \\ud800\\udfff\\udc00 */ return 0; }"}}`);
  push("params_nul_escape", `{"id":${id},"method":"compile","params":{"source":"int main() { /* \\u0000\\u0001\\u001f */ return 0; }"}}`);
  push("line_bom_prefix", `\ufeff{"id":${id},"method":"ping","params":{}}`);
  push("line_trailing_cr", `{"id":${id},"method":"ping","params":{}}\r`);
  push("line_invalid_json", `{"id":${id},"method":"ping",`);
  push("line_empty", ``);
  push("line_non_object", `[1,2,3]`);
  push("id_string", `{"id":"abc","method":"ping","params":{}}`);
  push("id_float_big", `{"id":1e308,"method":"ping","params":{}}`);
  push("id_null", `{"id":null,"method":"ping","params":{}}`);
  push("params_missing", `{"id":${id},"method":"ping"}`);
  push("method_missing", `{"id":${id},"params":{}}`);
  push("config_max_steps_overflow", `{"id":${id},"method":"config.set","params":{"max_steps":3000000000}}`);
  push("config_max_steps_float", `{"id":${id},"method":"config.set","params":{"max_steps":1.5e9}}`);
  push("config_unknown_key", `{"id":${id},"method":"config.set","params":{"bogus":1}}`);
  push("step_next_both", `{"id":${id},"method":"step.next","params":{"frames":1,"every":1}}`);
  push("icons_unknown_id", `{"id":${id},"method":"icons.get","params":{"ids":["__nope__"]}}`);
  push("texts_install_bad_json", `{"id":${id},"method":"texts.install","params":{"payload":"{not json"}}`);
  push("texts_install_clear", `{"id":${id},"method":"texts.install","params":{"payload":"{\\"suggestions\\":{\\"__clear__\\":true}}"}}`);
  push("texts_get_after_clear", `{"id":${id},"method":"texts.get","params":{}}`);
  push("session_destroy_tail", `{"id":${id},"method":"session.destroy","params":{}}`);
  return { frames, methods };
}

// ── 对比 ──────────────────────────────────────────────────────────────

export type FrameVerdict = "AGREE" | "TRAP_BOTH" | "CASCADE" | "DIFF" | "TRAP_ONE";
/**
 * 秩序：AGREE < TRAP_BOTH（双侧 trap，文案不比）< CASCADE（双侧实例历史不对称
 * 期间的字节差——单侧 trap 重建后、另一侧未重建，会话态残留差异的级联，非
 * runtime 分叉）< DIFF（同历史下字节不等）< TRAP_ONE（单侧 trap，级联根）。
 */
export const VERDICT_RANK: Record<FrameVerdict, number> = { AGREE: 0, TRAP_BOTH: 1, CASCADE: 2, DIFF: 3, TRAP_ONE: 4 };

const TRAP_PREFIX = Buffer.from('{"__host_trap__":', "utf8");

export function isTrapLine(b: Buffer): boolean {
  return b.length >= TRAP_PREFIX.length && b.subarray(0, TRAP_PREFIX.length).equals(TRAP_PREFIX);
}

/**
 * trap 归因类别（审阅 P2-4 处置）：TRAP_BOTH 不再只判「同帧都 trap」，两侧归一化
 * 类别须相同，否则判 DIFF（如一侧栈溢出另一侧 unreachable = 真分叉）。类别由
 * 两侧 runtime 的 kind/文案归一：
 *   stack       wasmtime StackOverflow / V8 RangeError "Maximum call stack"
 *   unreachable wasmtime UnreachableCodeReached / V8 RuntimeError "unreachable"
 *   oob         wasmtime ArrayOutOfBounds·MemoryOutOfBounds / V8 "out of bounds"
 *   host        供给层 bail（js-string 规范 trap 的宿主实现，仅 W4_STRINGS=host）
 *   other       其余（文案见 left_trap/right_trap）
 */
export type TrapCategory = "stack" | "unreachable" | "oob" | "host" | "other";

export function trapCategory(b: Buffer): TrapCategory {
  const s = b.toString("utf8");
  if (/StackOverflow|Maximum call stack|stack overflow/i.test(s)) return "stack";
  if (/UnreachableCodeReached|RuntimeError: unreachable|"unreachable"|unreachable instruction/i.test(s)) return "unreachable";
  if (/OutOfBounds|out of bounds|out-of-bounds/i.test(s)) return "oob";
  if (/"kind":"host-err"|js-string /.test(s)) return "host";
  return "other";
}

export interface FirstDiff {
  byte_offset: number;
  left: string; // 首差附近 ±ctx 的 UTF-8 解码片段（展示用；判定在 Buffer 层）
  right: string;
}

export function firstDiff(a: Buffer, b: Buffer, ctx = 48): FirstDiff | null {
  const n = Math.min(a.length, b.length);
  let i = 0;
  while (i < n && a[i] === b[i]) i++;
  if (i === n && a.length === b.length) return null;
  const lo = Math.max(0, i - ctx);
  return {
    byte_offset: i,
    left: a.subarray(lo, Math.min(a.length, i + ctx)).toString("utf8"),
    right: b.subarray(lo, Math.min(b.length, i + ctx)).toString("utf8"),
  };
}

export interface FrameReport {
  idx: number;
  method: string;
  verdict: FrameVerdict;
  left_len: number;
  right_len: number;
  /** 此前两侧各自的 trap（=实例重建）次数——不等即实例历史不对称；复位标记归零。 */
  epoch: { left: number; right: number };
  first_diff?: FirstDiff;
  left_trap?: string;
  right_trap?: string;
  /** 双侧 trap 时的归一化类别（不同即 DIFF）。 */
  trap_kind?: { left: TrapCategory; right: TrapCategory };
}

export interface CaseReport {
  name: string;
  suite: string;
  verdict: FrameVerdict;
  frames: FrameReport[];
}

export interface DiffReport {
  schema: "w4-diff-v1";
  left_label: string;
  right_label: string;
  left_sha256: string;
  right_sha256: string;
  identical: boolean;
  line_count: { left: number; right: number };
  summary: Record<FrameVerdict, number> & { cases: number; frames: number };
  cases: CaseReport[];
}

export function classifyFrame(l: Buffer, r: Buffer): FrameVerdict {
  const lt = isTrapLine(l);
  const rt = isTrapLine(r);
  // 双侧 trap：归因类别须相同（P2-4）——栈溢出 vs unreachable 是真分叉
  if (lt && rt) return trapCategory(l) === trapCategory(r) ? "TRAP_BOTH" : "DIFF";
  if (lt !== rt) return "TRAP_ONE";
  return l.equals(r) ? "AGREE" : "DIFF";
}

export function splitLines(buf: Buffer): Buffer[] {
  const out: Buffer[] = [];
  let start = 0;
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] === 10) {
      out.push(buf.subarray(start, i));
      start = i + 1;
    }
  }
  if (start < buf.length) out.push(buf.subarray(start));
  return out;
}

export function sha256Hex(b: Buffer): string {
  return createHash("sha256").update(b).digest("hex");
}

function trapMsg(b: Buffer): string {
  try {
    const j = JSON.parse(b.toString("utf8")) as { __host_trap__?: unknown; kind?: unknown };
    return `${String(j.kind ?? "?")}: ${String(j.__host_trap__ ?? "")}`;
  } catch {
    return b.toString("utf8").slice(0, 200);
  }
}

export function compareResponses(
  manifest: Manifest,
  left: Buffer,
  right: Buffer,
  labels: { left: string; right: string },
): DiffReport {
  const ll = splitLines(left);
  const rl = splitLines(right);
  const summary: DiffReport["summary"] = { AGREE: 0, TRAP_BOTH: 0, CASCADE: 0, DIFF: 0, TRAP_ONE: 0, cases: 0, frames: 0 };
  const cases: CaseReport[] = [];
  // 实例历史：每个 trap 行 = 该侧重建一次实例；两侧计数不等期间的 DIFF 降级为
  // CASCADE；复位标记帧（两侧同回 RESET_ACK）把两侧计数归零（P2-3：CASCADE 窗口
  // 收敛到 case 内单侧 trap 之后，不再跨 case 吸收真分叉）
  let trapL = 0;
  let trapR = 0;
  for (const c of manifest.cases) {
    const frames: FrameReport[] = [];
    let worst: FrameVerdict = "AGREE";
    for (let k = 0; k < c.frame_count; k++) {
      const idx = c.frame_start + k;
      const l = ll[idx] ?? Buffer.alloc(0);
      const r = rl[idx] ?? Buffer.alloc(0);
      if (isResetAck(l) && isResetAck(r)) {
        trapL = 0;
        trapR = 0;
      }
      let verdict: FrameVerdict = ll[idx] === undefined || rl[idx] === undefined ? "DIFF" : classifyFrame(l, r);
      if (verdict === "DIFF" && trapL !== trapR) verdict = "CASCADE";
      const fr: FrameReport = {
        idx,
        method: c.methods[k] ?? `frame${k}`,
        verdict,
        left_len: l.length,
        right_len: r.length,
        epoch: { left: trapL, right: trapR },
      };
      if (verdict === "DIFF" || verdict === "CASCADE") {
        const fd = firstDiff(l, r);
        if (fd) fr.first_diff = fd;
      }
      if (isTrapLine(l) && isTrapLine(r)) fr.trap_kind = { left: trapCategory(l), right: trapCategory(r) };
      if (isTrapLine(l)) {
        fr.left_trap = trapMsg(l);
        trapL += 1;
      }
      if (isTrapLine(r)) {
        fr.right_trap = trapMsg(r);
        trapR += 1;
      }
      frames.push(fr);
      summary.frames += 1;
      if (VERDICT_RANK[verdict] > VERDICT_RANK[worst]) worst = verdict;
    }
    summary[worst] += 1;
    summary.cases += 1;
    cases.push({ name: c.name, suite: c.suite, verdict: worst, frames });
  }
  const ls = sha256Hex(left);
  const rs = sha256Hex(right);
  return {
    schema: "w4-diff-v1",
    left_label: labels.left,
    right_label: labels.right,
    left_sha256: ls,
    right_sha256: rs,
    identical: ls === rs,
    line_count: { left: ll.length, right: rl.length },
    summary,
    cases,
  };
}

// ── 行为基线（synth 对抗面）────────────────────────────────────────────
//
// 对抗集天然含 TRAP_ONE（栈预算）/ TRAP_BOTH / CASCADE，不能要求 identical；
// 按 corpus_fuzz 分桶基线纪律锁定每例 verdict：DIFF 恒红（永不可登记）、
// 恶化（秩序上升）红、未登记（新例无基线）红、僵尸（基线有本轮无）红、
// 改善（秩序下降）亦红并指引 --freeze-baseline（基线漂移即红——与 golden
// digest 同口径，改善不静默吞）。

export interface SynthBaseline {
  schema: "w4-synth-baseline-v1";
  profile: Profile;
  note: string;
  cases: Record<string, FrameVerdict>;
}

export interface BaselineProblem {
  kind: "diff" | "worsened" | "improved" | "unregistered" | "zombie";
  name: string;
  from?: FrameVerdict;
  to?: FrameVerdict;
}

export function checkBaseline(report: DiffReport, base: SynthBaseline): BaselineProblem[] {
  const problems: BaselineProblem[] = [];
  const seen = new Set<string>();
  for (const c of report.cases) {
    seen.add(c.name);
    if (c.verdict === "DIFF") {
      problems.push({ kind: "diff", name: c.name, to: c.verdict });
      continue;
    }
    const b = base.cases[c.name];
    if (b === undefined) {
      problems.push({ kind: "unregistered", name: c.name, to: c.verdict });
      continue;
    }
    if (VERDICT_RANK[c.verdict] > VERDICT_RANK[b]) problems.push({ kind: "worsened", name: c.name, from: b, to: c.verdict });
    else if (VERDICT_RANK[c.verdict] < VERDICT_RANK[b]) problems.push({ kind: "improved", name: c.name, from: b, to: c.verdict });
  }
  for (const name of Object.keys(base.cases)) {
    if (!seen.has(name)) problems.push({ kind: "zombie", name, from: base.cases[name] });
  }
  return problems.sort((a, b) => byteOrder(a.name, b.name));
}

/** 由本轮报告冻结基线（键按字节序；DIFF 例拒绝冻结——fail loud）。 */
export function freezeBaseline(report: DiffReport, profile: Profile, note: string): SynthBaseline {
  const cases: Record<string, FrameVerdict> = {};
  for (const c of report.cases.slice().sort((a, b) => byteOrder(a.name, b.name))) {
    if (c.verdict === "DIFF") throw new Error(`拒绝冻结：${c.name} 为 DIFF（语义分叉不可登记为基线）`);
    cases[c.name] = c.verdict;
  }
  return { schema: "w4-synth-baseline-v1", profile, note, cases };
}
