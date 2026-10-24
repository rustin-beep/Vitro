#!/usr/bin/env node
// libc_boot_diff —— libc 自举对拍闸（Go→.mts 重写，refs #273；原 main.go 729 行，S5 尾项）。
//
// 命题：**MoonBit 引擎能否编译自己的标准库 C 源，且产物与冻结基线一致**。
// 这是"自举"的机器判据——不是"能跑通"，是"逐字节一致"。
//
// 用法（**仓库根**）：
//
//	node scripts/moonbit/libc_boot_diff/main.mts            # 对拍 scripts/moonbit/libc_src/src
//	node scripts/moonbit/libc_boot_diff/main.mts --selftest # J9：注入差异必红
//
// 为什么两侧形态不同、却仍能逐字节比（历史口径；Rust oracle 已随工序④删区，
// 现役判定 = golden 冻结基线比）：
//   - Rust 侧 `vitro_cli export --builtin-libc` 的口径是「注入 stub main →
//     编译 → 过滤」三段式：① 追加 stub unit `int main(){return 0;}`；② code[0]
//     若为 Jump（入口 wrapper）→ 记 operand 为 wrapper_ip 并截断 code；③ code[0]
//     置 Nop；④ func_table / func_index 删 "main"；⑤ 删预注册 libc 索引项。
//   - MoonBit 侧以 `dump_compile --library` 编译同样的 <源 + stub>：library mode
//     不预注册固定索引段、全局偏移自 0 起 —— 这正是 ⑤ 的同一语义。本驱动再对
//     MoonBit 产物做 ②③④ 同等过滤，然后投影到**交集字段**比对。
//
// 已知唯一的注入口径坑：stub 必须**直接接在主源末尾换行之后**（不前插空行）
// ——Rust 的多 unit 拼接等价于 `src1 + src2`，前插空行会让 stub 区指令的
// loc.line 差 1（实测踩过，非引擎差异）。
//
// 判定：交集字段（rules.json 的 compare_fields）经键排序 + 归一器归一后
// 逐字节相等 → SAME；任一字段不同 → DIFF（真红）；任一侧编译失败 → FAIL。
// 空集不得绿：源目录无 .c、或某侧零产物 → 直接红。
//
// 迁移口径（#292 批）：
//   - **RawMessage 语义是硬前提**（实测实锤）：Go `json.Unmarshal → map[string]
//     RawMessage → json.Marshal` 只对**被解码成 map 的那一层**排序键，值以原始
//     字节内嵌（嵌套对象保持原键序）。全层重排会改写 `{"loc":{"line":…,
//     "column":…}}` 内层顺序，`proj_sha` 立刻对不上（首版即此红）。故本版用
//     `internal/canonicalize` 的 `parseRawJson`/`embedText`/`emitSortedObject`
//     （JsonRaw 携带原始切片 + Go compact/escapeHTML 口径）；
//   - 默认模式（golden 基线比）与 `--selftest` 进 parity 闸；写盘模式
//     （--freeze/--freeze-mb）不进对拍（两侧会各写一遍基线文件）；
//   - 前置只依赖 `moon`（`moon run --target native cmd/dump_compile`），不依赖
//     预建产物——CI 的 static-gates 已装 MoonBit 工具链；
//   - oracle 在位时走双跑面（`native/target/release/vitro_cli`）；本仓已删区，
//     实际恒走 golden。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { JsonNumber, JsonRaw, canonicalize, emitSortedObject, embedText, parseRawJson } from "../../internal/canonicalize.mts";
import type { JsonValue } from "../../internal/canonicalize.mts";
import { byteCompare } from "../../internal/text.mts";

const RULES_PATH = "scripts/moonbit/libc_boot_diff/rules.json";
const BOOT_DIGEST_FILE = "scripts/moonbit/libc_boot_diff/golden_digest.json";

/** 顶层键 → 内嵌 JSON 文本（Go `map[string]json.RawMessage` 的等价形态）。 */
export type FieldText = Map<string, string>;

export interface RulesDoc {
  schema: number;
  src_dir: string;
  stub_source: string;
  compare_fields: string[];
}

interface BootEntry {
  src_sha: string;
  proj_sha: string;
}

interface BootDigestDoc {
  version: number;
  note: string;
  cases: Map<string, BootEntry>;
}

/** 单源的两侧产物（MoonBit 侧已按 export 口径过滤，文本 = 内嵌形态）。 */
export interface Pair {
  name: string;
  moonOK: boolean;
  moonFields: FieldText | null;
  rustFields: FieldText | null;
  rustOK: boolean;
  wrapperIP: number;
  codeLen: number;
}

const fromSlash = (p: string): string => p.split("/").join(path.sep);

/** JsonRaw 解包（取结构值）。 */
const unwrap = (v: JsonValue | undefined): JsonValue | undefined => (v instanceof JsonRaw ? v.value : v);

class ExitErr extends Error {
  readonly code: number;
  constructor(code: number) {
    super("exit");
    this.name = "ExitErr";
    this.code = code;
  }
}

/** Go `fatal`：stderr 前缀 `libc_boot_diff: `，退出码 2。 */
export function fatal(format: string): never {
  process.stderr.write("libc_boot_diff: " + format + "\n");
  throw new ExitErr(2);
}

const errText = (e: unknown): string => (e instanceof Error ? e.message : String(e));

function fileExists(p: string): boolean {
  try {
    fs.statSync(p);
    return true;
  } catch {
    return false;
  }
}

/** Go `os.ReadDir`（按文件名字节序）+ `.c` 过滤。 */
export function listC(dir: string): string[] {
  const names = fs
    .readdirSync(fromSlash(dir), { withFileTypes: true })
    .filter((e) => !e.isDirectory() && e.name.endsWith(".c"))
    .map((e) => e.name)
    .sort(byteCompare);
  return names.map((n) => path.join(fromSlash(dir), n));
}

export function loadRules(): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(RULES_PATH, "utf8");
  } catch (e) {
    fatal(`读规则失败（须在仓库根运行）: ${errText(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`规则解析失败: ${errText(e)}`);
  }
  if (rd.schema !== 1) fatal(`规则 schema 不支持: ${rd.schema}（期望 1）`);
  if (!Array.isArray(rd.compare_fields) || rd.compare_fields.length === 0) fatal("规则缺 compare_fields");
  return rd;
}

function loadBootDigest(): BootDigestDoc {
  const d: BootDigestDoc = { version: 1, note: "freeze 时已全量对拍；golden = mb 投影 hash ≡ 清单", cases: new Map() };
  if (fileExists(BOOT_DIGEST_FILE)) {
    let parsed: { version?: number; note?: string; cases?: Record<string, BootEntry> };
    try {
      parsed = JSON.parse(fs.readFileSync(BOOT_DIGEST_FILE, "utf8")) as typeof parsed;
    } catch {
      fatal(`digest 清单坏或版本不识 ${BOOT_DIGEST_FILE}`);
    }
    if (parsed.version !== 1) fatal(`digest 清单坏或版本不识 ${BOOT_DIGEST_FILE}`);
    if (parsed.note !== undefined) d.note = parsed.note;
    for (const [k, v] of Object.entries(parsed.cases ?? {})) d.cases.set(k, v);
  }
  return d;
}

function saveBootDigest(d: BootDigestDoc): void {
  const keys = [...d.cases.keys()].sort(byteCompare);
  const cases: Record<string, BootEntry> = {};
  for (const k of keys) cases[k] = d.cases.get(k) as BootEntry;
  const text = JSON.stringify({ version: d.version, note: d.note, cases }, null, 2) + "\n";
  try {
    fs.writeFileSync(BOOT_DIGEST_FILE, text, "utf8");
  } catch (e) {
    fatal(`写 digest 清单失败: ${errText(e)}`);
  }
}

const hash16 = (b: Uint8Array): string => crypto.createHash("sha256").update(b).digest("hex").slice(0, 16);

/** 逐字节 CRLF→LF 后取 sha256 前 8 位（Go `bytes.ReplaceAll(b, crlf, lf)` 口径）。 */
export function fileSHA8(p: string): string {
  const b = fs.readFileSync(p);
  const out = Buffer.alloc(b.length);
  let n = 0;
  for (let i = 0; i < b.length; i++) {
    if (b[i] === 13 && b[i + 1] === 10) continue;
    out[n++] = b[i] as number;
  }
  return crypto.createHash("sha256").update(out.subarray(0, n)).digest("hex").slice(0, 8);
}

/** Go `%s` of []byte：按字节截断到 160 + 省略号。 */
function preview(b: Uint8Array | string): string {
  const buf = typeof b === "string" ? Buffer.from(b, "utf8") : Buffer.from(b);
  if (buf.length > 160) return buf.subarray(0, 160).toString("utf8") + "…";
  return buf.toString("utf8");
}

/** 解析原始 JSON 文本 → 顶层对象 Map（值均带原始切片）。 */
function parseObj(text: string | Uint8Array): Map<string, JsonValue> {
  const root = parseRawJson(text);
  const inner = root instanceof JsonRaw ? root.value : root;
  if (!(inner instanceof Map)) throw new Error("顶层不是对象");
  return inner as Map<string, JsonValue>;
}

/** 对象 Map（值带原始切片）→ FieldText（值取内嵌形态文本）。 */
function toFieldText(m: Map<string, JsonValue>): FieldText {
  const out: FieldText = new Map();
  for (const [k, v] of m) out.set(k, embedText(v));
  return out;
}

// ── 产物过滤 / 投影（Go json.RawMessage 面的等价实现）─────────────────

/**
 * 按 Rust export 口径过滤 MoonBit dump：
 *   ① code[0] 为 Jump → 记 wrapper_ip，截断 code 到 wrapper_ip
 *   ② code[0] 置 Nop
 *   ③ func_table / func_index 删 main
 * 值以原始字节内嵌（只有被解码成 map 的层排序键）——RawMessage 语义。
 */
export function filterExport(dump: JsonValue): { fields: FieldText; wrapperIP: number; codeLen: number } {
  const inner = dump instanceof JsonRaw ? dump.value : dump;
  if (!(inner instanceof Map)) throw new Error("产物顶层不是对象");
  const m = inner as Map<string, JsonValue>;

  const codeRaw = m.get("code");
  if (codeRaw === undefined) throw new Error("产物无 code 字段");
  const codeInner = codeRaw instanceof JsonRaw ? codeRaw.value : codeRaw;
  if (!Array.isArray(codeInner)) throw new Error("code 解析失败: 顶层 code 不是数组");
  const code = codeInner as JsonValue[];

  let wrapperIP = -1;
  if (code.length > 0) {
    const first = code[0];
    const firstInner = unwrap(first);
    if (firstInner instanceof Map) {
      const op = unwrap(firstInner.get("op"));
      if (typeof op === "string" && op.includes("Jump")) {
        const operand = unwrap(firstInner.get("operand"));
        // Go：json.Unmarshal(ins["operand"], &float64) —— 非数值即不记 wrapper_ip
        if (operand instanceof JsonNumber) {
          const n = Number(operand.raw);
          if (Number.isFinite(n)) wrapperIP = Math.trunc(n);
        }
      }
    }
  }

  let items = code.map((v) => embedText(v));
  if (wrapperIP >= 0 && wrapperIP <= items.length) items = items.slice(0, wrapperIP);
  if (items.length > 0) {
    const first = code[0];
    const firstInner = first instanceof JsonRaw ? (first.value as JsonValue) : first;
    if (!(firstInner instanceof Map)) throw new Error("code[0] 解析失败: 不是对象");
    const entries = new Map<string, string>();
    for (const [k, v] of firstInner as Map<string, JsonValue>) entries.set(k, embedText(v));
    entries.set("op", '"Nop"');
    entries.set("operand", "0");
    items[0] = emitSortedObject(entries);
  }

  const fields: FieldText = new Map();
  for (const [k, v] of m) if (k !== "code") fields.set(k, embedText(v));

  for (const k of ["func_table", "func_index"]) {
    const raw = m.get(k);
    if (raw === undefined) continue;
    const obj = raw instanceof JsonRaw ? raw.value : raw;
    if (!(obj instanceof Map)) continue; // Go：Unmarshal 失败即 continue（原样保留）
    const entries = new Map<string, string>();
    for (const [kk, vv] of obj as Map<string, JsonValue>) if (kk !== "main") entries.set(kk, embedText(vv));
    fields.set(k, emitSortedObject(entries));
  }
  fields.set("code", "[" + items.join(",") + "]");
  return { fields, wrapperIP, codeLen: items.length };
}

/** 只保留 fields 里的键（两侧产物形态不同，交集才是可比面）。空投影 = 错。 */
export function project(fields: FieldText, keep: readonly string[]): FieldText {
  const out: FieldText = new Map();
  for (const f of keep) {
    const v = fields.get(f);
    if (v !== undefined) out.set(f, v);
  }
  if (out.size === 0) throw new Error("投影后无字段（compare_fields 与产物键全不匹配）");
  return out;
}

/** Go `json.Marshal(map[string]RawMessage)` 口径的字节（proj_sha 的输入单源）。 */
export function projectRaw(fields: FieldText, keep: readonly string[]): Buffer {
  return Buffer.from(emitSortedObject(project(fields, keep)), "utf8");
}

/** injectOperand：code[1].operand +1（selftest 用；code[0] 已是 Nop）。 */
export function injectOperand(fields: FieldText): { fields: FieldText; ok: boolean } {
  const codeText = fields.get("code");
  if (codeText === undefined) return { fields, ok: false };
  const root = parseRawJson(codeText);
  const arr = root instanceof JsonRaw ? root.value : root;
  if (!Array.isArray(arr) || arr.length < 2) return { fields, ok: false };
  const second = arr[1] as JsonValue;
  const secondInner = second instanceof JsonRaw ? (second.value as JsonValue) : second;
  if (!(secondInner instanceof Map)) return { fields, ok: false };
  const entries = new Map<string, string>();
  for (const [k, v] of secondInner as Map<string, JsonValue>) entries.set(k, embedText(v));
  const operand = entries.get("operand");
  if (operand === undefined || !/^-?\d+(\.\d+)?$/.test(operand)) return { fields, ok: false };
  entries.set("operand", String(Math.trunc(Number(operand)) + 1));
  const items = arr.map((v) => embedText(v));
  items[1] = emitSortedObject(entries);
  const out: FieldText = new Map(fields);
  out.set("code", "[" + items.join(",") + "]");
  return { fields: out, ok: true };
}

/** 投影 → 键排序 → 归一器归一 → 逐字节比较。 */
export function comparePair(p: Pair, keep: readonly string[]): { same: boolean; detail: string } {
  const moonRaw = projectRaw(p.moonFields as FieldText, keep);
  const rustRaw = projectRaw(p.rustFields as FieldText, keep);
  const a = canonicalize(rustRaw);
  const b = canonicalize(moonRaw);
  if (a.equals(b)) return { same: true, detail: "" };
  // 逐字段定位差异（报告可读性）——同样走「编码 → 归一」
  let detail = "";
  const rustFields = project(p.rustFields as FieldText, keep);
  const moonFields = project(p.moonFields as FieldText, keep);
  for (const k of [...rustFields.keys()].sort(byteCompare)) {
    const x = canonicalize(Buffer.from(emitSortedObject(new Map([[k, rustFields.get(k) as string]])), "utf8"));
    const y = canonicalize(Buffer.from(emitSortedObject(new Map([[k, moonFields.get(k) as string]])), "utf8"));
    if (!x.equals(y)) {
      detail += `    [${k}] 两侧不同（rust ${x.length} 字节 / moon ${y.length} 字节）\n`;
      detail += `        rust: ${preview(x)}\n`;
      detail += `        moon: ${preview(y)}\n`;
    }
  }
  return { same: false, detail };
}

/** comparePair 的错误面统一转 fatal（Go：比对失败即 exit 2，不静默跳过）。 */
function cmpOrFatal(p: Pair, keep: readonly string[], prefix: string): { same: boolean; detail: string } {
  try {
    return comparePair(p, keep);
  } catch (e) {
    fatal(`${prefix}: ${errText(e)}`);
  }
}

// ── 外部调用 ─────────────────────────────────────────────────────────

export function runMoon(stubDir: string, outDir: string): void {
  const r = spawnSync("moon", ["run", "--target", "native", "cmd/dump_compile", "--", stubDir, outDir, "--library"], {
    cwd: "moonbit",
    maxBuffer: 64 * 1024 * 1024,
  });
  const out = (r.stdout?.toString("utf8") ?? "") + (r.stderr?.toString("utf8") ?? "");
  if (r.error !== undefined) fatal(`moon dump_compile --library 失败: ${r.error.message}\n${out}`);
  if ((r.status ?? -1) !== 0) fatal(`moon dump_compile --library 失败: exit status ${r.status}\n${out}`);
}

let rustCLIOnce = "";

function rustCLI(): string {
  if (rustCLIOnce !== "") return rustCLIOnce;
  for (const p of [path.join("native", "target", "release", "vitro_cli.exe"), path.join("native", "target", "release", "vitro_cli")]) {
    if (fileExists(p)) {
      rustCLIOnce = p;
      return p;
    }
  }
  fatal("未找到 vitro_cli release 二进制（先 cargo build --release --bin vitro_cli）");
}

function runRustExport(src: string, out: string): void {
  const exe = rustCLI();
  const r = spawnSync(exe, ["export", src, "-o", out, "--builtin-libc"], { maxBuffer: 64 * 1024 * 1024 });
  const text = (r.stdout?.toString("utf8") ?? "") + (r.stderr?.toString("utf8") ?? "");
  if (r.error !== undefined) fatal(`vitro_cli export 失败 ${src}: ${r.error.message}\n${text}`);
  if ((r.status ?? -1) !== 0) fatal(`vitro_cli export 失败 ${src}: exit status ${r.status}\n${text}`);
}

// ── J9：selftest ────────────────────────────────────────────────────

export function selftestRun(pairs: Pair[], keep: readonly string[], baselineGreen: boolean): number {
  if (!baselineGreen) {
    process.stdout.write("libc_boot_diff: selftest ABORT——基线不绿，注入后的红无法归因\n");
    return 2;
  }
  if (pairs.length === 0) {
    process.stdout.write("libc_boot_diff: selftest ABORT——无样本\n");
    return 2;
  }
  const p = pairs[0] as Pair;
  const inj = injectOperand(p.moonFields as FieldText);
  if (!inj.ok) {
    process.stdout.write("libc_boot_diff: selftest ABORT——注入失败（样本 code 段不足 2 条或 operand 非数值）\n");
    return 2;
  }
  const cmp = cmpOrFatal({ ...p, moonFields: inj.fields }, keep, "selftest 比对失败");
  process.stdout.write(`libc_boot_diff: selftest 已注入——${p.name} 的 code[1].operand +1\n`);
  if (cmp.same) {
    process.stdout.write("libc_boot_diff: selftest FAIL——注入后仍判绿，闸门失效\n");
    return 1;
  }
  process.stdout.write("libc_boot_diff: selftest PASS——注入差异被捕获（红），J9 证红成立\n");
  return 0;
}

// ── 主流程 ──────────────────────────────────────────────────────────

interface Flags {
  selftest: boolean;
  freeze: boolean;
  golden: boolean;
  freezeMB: boolean;
}

export function runMain(argv: readonly string[]): number {
  try {
    const fl = parseFlags(argv);
    return mainFlow(fl);
  } catch (e) {
    if (e instanceof ExitErr) return e.code;
    throw e;
  }
}

/** 参数面：`--selftest/--freeze/--freeze-mb/--golden`，互斥校验与未知参数 fail loud。 */
function parseFlags(argv: readonly string[]): Flags {
  const fl: Flags = { selftest: false, freeze: false, golden: false, freezeMB: false };
  for (const a of argv) {
    switch (a) {
      case "--selftest":
        fl.selftest = true;
        break;
      case "--freeze":
        fl.freeze = true;
        break;
      case "--freeze-mb":
        fl.freezeMB = true;
        break;
      case "--golden":
        fl.golden = true;
        break;
      default:
        fatal(`未知参数: ${a}（可用：--selftest/--freeze/--freeze-mb/--golden）`);
    }
  }
  if ((fl.freeze && fl.golden) || (fl.freezeMB && (fl.freeze || fl.golden))) {
    fatal("--freeze/--freeze-mb/--golden 互斥（freeze-mb 属删区后入账通道）");
  }
  return fl;
}

function mainFlow(fl: Flags): number {
  let golden = fl.golden;
  const { selftest, freeze, freezeMB } = fl;

  // --freeze-mb（第十一轮审阅 P2-2）：删区后合法刷新路径——只跑 mb 侧 +
  // 投影 hash 入账（正确性背书 = CI golden 步语义 + 下游消费）。
  if (freezeMB) {
    const rd = loadRules();
    if (!fileExists(fromSlash(rd.src_dir))) fatal(`源目录不存在（须在仓库根运行）: ${rd.src_dir}`);
    const files = listC(rd.src_dir);
    const work = fs.mkdtempSync(path.join(os.tmpdir(), "libc_boot_fmb_"));
    try {
      const stubDir = path.join(work, "src");
      fs.mkdirSync(stubDir, { recursive: true });
      for (const f of files) {
        const body = fs.readFileSync(f);
        fs.writeFileSync(path.join(stubDir, path.basename(f)), Buffer.concat([body, Buffer.from(rd.stub_source, "utf8")]));
      }
      const moonDir = path.join(work, "moon");
      runMoon(stubDir, moonDir);
      const doc = loadBootDigest();
      let added = 0;
      let refreshed = 0;
      let unchanged = 0;
      for (const f of files) {
        const base = path.basename(f);
        let m: Map<string, JsonValue>;
        try {
          m = parseObj(fs.readFileSync(path.join(moonDir, base + ".compile.json")));
        } catch (e) {
          fatal(`--freeze-mb 读产物失败 ${base}: ${errText(e)}`);
        }
        const dump = m.get("dump");
        if (dump === undefined) fatal(`--freeze-mb 解析失败 ${base}`);
        const { fields } = filterExport(dump);
        const entry: BootEntry = { src_sha: fileSHA8(f), proj_sha: hash16(projectRaw(fields, rd.compare_fields)) };
        const old = doc.cases.get(base);
        if (old !== undefined) {
          if (old.src_sha === entry.src_sha && old.proj_sha === entry.proj_sha) {
            unchanged++;
          } else {
            doc.cases.set(base, entry);
            process.stdout.write(`REFRESH ${base}（proj ${old.proj_sha} → ${entry.proj_sha}）\n`);
            refreshed++;
          }
          continue;
        }
        doc.cases.set(base, entry);
        process.stdout.write(`ADD ${base}\n`);
        added++;
      }
      if (added === 0 && refreshed === 0) {
        process.stdout.write(`libc_boot_diff --freeze-mb: 零新增零漂移（${unchanged} 例均与现状一致）\n`);
        return 0;
      }
      saveBootDigest(doc);
      process.stdout.write(`libc_boot_diff --freeze-mb: 新增 ${added} / 重算 ${refreshed} / 一致 ${unchanged} → ${BOOT_DIGEST_FILE}\n`);
      return 0;
    } finally {
      fs.rmSync(work, { recursive: true, force: true });
    }
  }

  // 工序④固化（2026-10-05 面六）：oracle 缺失自动切 golden（删区后零改动存活）
  const rustAlive =
    fileExists(path.join("native", "target", "release", "vitro_cli.exe")) ||
    fileExists(path.join("native", "target", "release", "vitro_cli"));
  if (!rustAlive && !freeze && !golden) {
    process.stderr.write(
      "libc_boot_diff: [裁判切换] oracle exe 不存在——本判定走 --golden 冻结基线（结构裁判自 oracle 切为 digest 清单；正确性主锚仍为 Clang/shadow）\n",
    );
    golden = true;
  }
  if (freeze && !rustAlive) fatal("--freeze 需要 oracle exe");
  const rd = loadRules();

  if (!fileExists(fromSlash(rd.src_dir))) fatal(`源目录不存在（须在仓库根运行）: ${rd.src_dir}`);
  const files = listC(rd.src_dir);
  if (files.length === 0) fatal(`源目录无 .c 文件: ${rd.src_dir}`);
  process.stdout.write(`libc_boot_diff: 对拍 ${rd.src_dir}（${files.length} 个 C 源）\n`);

  const work = fs.mkdtempSync(path.join(os.tmpdir(), "libc_boot_"));
  try {
    const stubDir = path.join(work, "src");
    fs.mkdirSync(stubDir, { recursive: true });
    for (const f of files) {
      const body = fs.readFileSync(f);
      // 关键：直接拼接（不插入额外分隔），与 Rust 多 unit 拼接口径一致
      fs.writeFileSync(path.join(stubDir, path.basename(f)), Buffer.concat([body, Buffer.from(rd.stub_source, "utf8")]));
    }

    const moonDir = path.join(work, "moon");
    runMoon(stubDir, moonDir);

    // 装载两侧产物（先全部读入，selftest 需要基线判定后再注入）
    const pairs: Pair[] = [];
    let ok = true;
    for (const f of files) {
      const base = path.basename(f);
      const p: Pair = {
        name: base,
        moonOK: false,
        moonFields: null,
        rustFields: null,
        rustOK: false,
        wrapperIP: -1,
        codeLen: -1,
      };
      const prod = path.join(moonDir, base + ".compile.json");
      let m: Map<string, JsonValue>;
      try {
        m = parseObj(fs.readFileSync(prod));
      } catch (e) {
        process.stdout.write(`  FAIL ${base}: MoonBit 侧无产物（${errText(e)}）\n`);
        ok = false;
        pairs.push(p);
        continue;
      }
      if (unwrap(m.get("ok")) !== true) {
        process.stdout.write(`  FAIL ${base}: MoonBit 编译失败 ${preview(embedText(m.get("errors") ?? null))}\n`);
        ok = false;
        pairs.push(p);
        continue;
      }
      let filtered: { fields: FieldText; wrapperIP: number; codeLen: number };
      try {
        filtered = filterExport(m.get("dump") as JsonValue);
      } catch (e) {
        process.stdout.write(`  FAIL ${base}: MoonBit 产物过滤失败（${errText(e)}）\n`);
        ok = false;
        pairs.push(p);
        continue;
      }
      p.moonOK = true;
      p.moonFields = filtered.fields;
      p.wrapperIP = filtered.wrapperIP;
      p.codeLen = filtered.codeLen;

      if (golden) {
        pairs.push(p);
        continue;
      }
      // oracle 在位：Rust export 侧产物已完成同等过滤，直接用
      const rustPath = path.join(work, base.replace(/\.c$/, "") + ".rust.json");
      runRustExport(f, rustPath);
      if (!fileExists(rustPath) || fs.statSync(rustPath).size === 0) {
        process.stdout.write(`  FAIL ${base}: Rust export 无产物\n`);
        ok = false;
        pairs.push(p);
        continue;
      }
      p.rustOK = true;
      p.rustFields = toFieldText(parseObj(fs.readFileSync(rustPath)));
      pairs.push(p);
    }

    if (!ok) {
      process.stdout.write("libc_boot_diff: FAIL——任一侧缺产物（见上）\n");
      return 1;
    }

    // ---- 工序④固化：golden / freeze 基线模式 ----
    if (golden || freeze) {
      const doc = loadBootDigest();
      if (freeze) {
        // freeze：现模式已双侧跑齐，逐例投影 hash 入清单——先跑 comparePair
        // 全绿才写（审阅 P2-1 纪律）
        let bad = 0;
        for (const pp of pairs) {
          const cmp = cmpOrFatal(pp, rd.compare_fields, `比对 ${pp.name} 失败`);
          if (!cmp.same) {
            process.stdout.write(`  DIFF ${pp.name}（freeze 拒写清单——先归因）\n`);
            bad++;
          } else {
            doc.cases.set(pp.name, {
              src_sha: fileSHA8(path.join(fromSlash(rd.src_dir), pp.name)),
              proj_sha: hash16(projectRaw(pp.moonFields as FieldText, rd.compare_fields)),
            });
          }
        }
        if (bad > 0) return 1;
        saveBootDigest(doc);
        process.stdout.write(`libc_boot_diff freeze: ${pairs.length} 例投影 hash 入清单 → ${BOOT_DIGEST_FILE}\n`);
        return 0;
      }
      // golden：mb 投影 hash ≡ 清单
      let nSame = 0;
      let nDiff = 0;
      for (const pp of pairs) {
        const e = doc.cases.get(pp.name);
        if (e === undefined) {
          process.stdout.write(`  DIFF ${pp.name}：清单缺例（先 --freeze）\n`);
          nDiff++;
          continue;
        }
        const sha = fileSHA8(path.join(fromSlash(rd.src_dir), pp.name));
        if (sha !== e.src_sha) {
          process.stdout.write(`  DIFF ${pp.name}：libc 源已变更而清单未重刷（${sha} ≠ ${e.src_sha}）\n`);
          nDiff++;
          continue;
        }
        const got = hash16(projectRaw(pp.moonFields as FieldText, rd.compare_fields));
        if (got !== e.proj_sha) {
          process.stdout.write(
            `  DIFF ${pp.name}：投影 hash ${got} ≠ 清单 ${e.proj_sha}（全文对照见 frozen-oracle-snapshot 分支）\n`,
          );
          nDiff++;
        } else {
          nSame++;
        }
      }
      process.stdout.write(`libc_boot_diff[golden]: SAME=${nSame} DIFF=${nDiff}（${pairs.length} 源）\n`);
      if (nDiff > 0) return 1;
      process.stdout.write("libc_boot_diff[golden]: PASS——MoonBit library mode 自举产物与冻结基线一致\n");
      return 0;
    }

    // 基线判定（oracle 在位的双跑面）
    let nSame = 0;
    let nDiff = 0;
    for (const p of pairs) {
      const cmp = cmpOrFatal(p, rd.compare_fields, `比对 ${p.name} 失败`);
      if (cmp.same) {
        nSame++;
        process.stdout.write(`  SAME ${p.name}（code=${p.codeLen} 条；wrapper_ip=${p.wrapperIP}）\n`);
      } else {
        nDiff++;
        process.stdout.write(`  DIFF ${p.name}\n${cmp.detail}\n`);
      }
    }
    process.stdout.write(`libc_boot_diff: SAME=${nSame} DIFF=${nDiff}（${pairs.length} 源）\n`);

    if (selftest) return selftestRun(pairs, rd.compare_fields, nDiff === 0);
    if (nDiff > 0) {
      process.stdout.write("libc_boot_diff: FAIL——自举产物与 oracle 不一致（真红）\n");
      return 1;
    }
    process.stdout.write("libc_boot_diff: PASS——MoonBit library mode 产物与 Rust export 交集字段逐字节一致\n");
    return 0;
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(runMain(process.argv.slice(2)));
}
