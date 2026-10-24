#!/usr/bin/env node
// teaching_annotation_diff —— S8 teaching 族级增量对拍器（Go→.mts 重写，refs #273；原 2026-10-01 批四）。
//
// 用途：MoonBit cmd/serve 与 golden（工序③固化：scripts/teaching_annotation_diff/
// golden/algorithm_annotations_v3.json）的**算法标注首现序列**族级对拍——只比
// 已迁移族条目（rules.json migrated_algorithms），未迁移族条目两侧跳过。
//
// 口径逐字照搬 native/tests/algorithm_annotation_golden_test.rs（提取段）：
//   compile（含算法检测）→ run → step.begin → step.next × step_budget
//   首现去重键 = (phase, desc)；条目 = algorithm/display_name/phase/desc/
//   code_line/src；src = 源码第 code_line 行 trim；code_line 越界 = ""。
//
// 双向断言：① 过滤后首现序列逐条相等（六字段）② 非空模板集与 golden
// 过滤后键集严格相等。
//
// 豁免：rules.json exemptions（template+kind+algorithm+phase+desc 锚定，
// kind ∈ missing/extra/diff）。fail loud：规则文件缺失/坏 JSON/字段缺失一律 exit 2。
//
// 用法（仓库根）：
//   node scripts/teaching_annotation_diff/main.mts [--only tpl1,tpl2] [--backend-wasm]
//        [--freeze] [--catalog-check] [--catalog-selftest]
//
// 前置：`cd moonbit && MOON_CC=clang moon build --target native cmd/serve`
// ——exe 新鲜度由 internal/freshness 门禁（mtime 触发 + 构建复核）兜底。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";
import { ensureFresh } from "../internal/freshness.mts";
import { loadRules, runCatalogCheck } from "./catalog.mts";
import type { Rules } from "./catalog.mts";

export interface FirstOccurrence {
  algorithm: string;
  display_name: string;
  phase: string;
  desc: string;
  code_line: number;
  src: string;
}

export interface DiffRecord {
  template: string;
  kind: "missing" | "extra" | "diff";
  golden?: FirstOccurrence;
  actual?: FirstOccurrence;
}

export interface Exemption {
  template: string;
  kind: string;
  algorithm: string;
  phase: string;
  desc: string;
  reason: string;
}

interface ServingOptions {
  /** #49 批三：被测物换统一入口壳 serve（node 消费 gateway wasm.wasm） */
  backendWasm: boolean;
}

/** Go `%q` 对 ASCII/普通文本的等价形态（诊断文案用）。 */
function quote(s: string): string {
  return JSON.stringify(s);
}

/** Go `%+v` 结构体打印的近似形态（红路径诊断用）。 */
function plusV(e: FirstOccurrence): string {
  return `{Algorithm:${e.algorithm} DisplayName:${e.display_name} Phase:${e.phase} Desc:${e.desc} CodeLine:${e.code_line} Src:${e.src}}`;
}

export function recordString(d: DiffRecord): string {
  if (d.kind === "missing") {
    const e = d.golden!;
    return `[${d.template}] missing: ${e.algorithm}/${e.phase}/${quote(e.desc)} (line ${e.code_line})`;
  }
  if (d.kind === "extra") {
    const e = d.actual!;
    return `[${d.template}] extra:   ${e.algorithm}/${e.phase}/${quote(e.desc)} (line ${e.code_line})`;
  }
  return `[${d.template}] diff:    golden ${plusV(d.golden!)} vs actual ${plusV(d.actual!)}`;
}

function serveExe(root: string): string {
  const override = process.env["VITRO_SERVE_MB"];
  if (override !== undefined && override !== "") return override;
  const name = process.platform === "win32" ? "serve.exe" : "serve";
  return path.join(root, "moonbit", "_build", "native", "debug", "build", "cmd", "serve", name);
}

/** 批量 serve 驱动（serve_smoke 同款）：stdin 喂 NDJSON，收集 stdout。 */
export function runServeBatch(
  exe: string,
  payload: string,
  timeoutMs: number,
  opts: ServingOptions,
): { stdout: string; code: number; timedOut: boolean } {
  const r = opts.backendWasm
    ? spawnSync("node", [exe, "serve"], {
        input: payload,
        encoding: "utf8",
        timeout: timeoutMs,
        maxBuffer: 64 * 1024 * 1024,
      })
    : spawnSync(exe, [], {
        input: payload,
        encoding: "utf8",
        timeout: timeoutMs,
        maxBuffer: 64 * 1024 * 1024,
      });
  const timedOut = r.error !== undefined && (r.error as NodeJS.ErrnoException).code === "ETIMEDOUT";
  const code = r.status ?? (timedOut ? 0 : -1);
  return { stdout: r.stdout ?? "", code, timedOut };
}

interface RespLine {
  id?: number;
  result?: unknown;
  error?: unknown;
}

interface StepPayload {
  code_line: number;
  algorithm_step: {
    algorithm_name: string;
    display_name: string;
    phase: string;
    description: string;
  } | null;
}

/** 单模板首现提取（Rust extract_first_occurrences 同口径）。 */
export function extractViaServe(
  exe: string,
  source: string,
  budget: number,
  opts: ServingOptions,
): FirstOccurrence[] {
  const lines: string[] = [];
  let id = 0;
  id++;
  lines.push(JSON.stringify({ id, method: "compile", params: { source } }));
  id++;
  lines.push(JSON.stringify({ id, method: "run" }));
  id++;
  lines.push(JSON.stringify({ id, method: "step.begin" }));
  const nextIDs = new Set<number>();
  for (let i = 0; i < budget; i++) {
    id++;
    nextIDs.add(id);
    lines.push(JSON.stringify({ id, method: "step.next" }));
  }
  const { stdout, timedOut } = runServeBatch(exe, lines.join("\n") + "\n", 120_000, opts);
  if (timedOut) throw new Error("serve 超时（120s）");
  const seen = new Set<string>();
  const first: FirstOccurrence[] = [];
  const srcLines = source.split("\n");
  for (const line of stdout.split("\n")) {
    if (line.trim() === "") continue;
    let r: RespLine;
    try {
      r = JSON.parse(line) as RespLine;
    } catch {
      throw new Error(`响应行非 JSON: ${line.slice(0, 200)}`);
    }
    if (r.error !== undefined && r.error !== null) {
      throw new Error(`serve 错误帧 (id=${r.id ?? -1}): ${JSON.stringify(r.error).slice(0, 300)}`);
    }
    if (r.id === undefined || !nextIDs.has(r.id) || r.result === undefined) continue;
    const res = r.result as { payloads?: StepPayload[] };
    if (!Array.isArray(res.payloads)) throw new Error("step.next result 解析失败: 缺 payloads");
    for (const pl of res.payloads) {
      const a = pl.algorithm_step;
      if (a === null || a === undefined) continue;
      const key = a.phase + "\u0000" + a.description;
      if (a.phase === "" || seen.has(key)) continue;
      seen.add(key);
      let src = "";
      if (pl.code_line >= 1 && pl.code_line <= srcLines.length) {
        src = (srcLines[pl.code_line - 1] ?? "").trim();
      }
      first.push({
        algorithm: a.algorithm_name,
        display_name: a.display_name,
        phase: a.phase,
        desc: a.description,
        code_line: pl.code_line,
        src,
      });
    }
  }
  return first;
}

export function filterMigrated(entries: FirstOccurrence[], migrated: Set<string>): FirstOccurrence[] {
  return entries.filter((e) => migrated.has(e.algorithm));
}

function sameKey(a: FirstOccurrence, b: FirstOccurrence): boolean {
  return a.phase === b.phase && a.desc === b.desc;
}

function sameEntry(a: FirstOccurrence, b: FirstOccurrence): boolean {
  return (
    a.algorithm === b.algorithm &&
    a.display_name === b.display_name &&
    a.phase === b.phase &&
    a.desc === b.desc &&
    a.code_line === b.code_line &&
    a.src === b.src
  );
}

export function compareTemplate(tpl: string, golden: FirstOccurrence[], actual: FirstOccurrence[]): DiffRecord[] {
  const recs: DiffRecord[] = [];
  let i = 0;
  let j = 0;
  while (i < golden.length || j < actual.length) {
    if (j >= actual.length || (i < golden.length && j < actual.length && !sameKey(golden[i]!, actual[j]!))) {
      recs.push({ template: tpl, kind: "missing", golden: golden[i]! });
      i++;
    } else if (i >= golden.length) {
      recs.push({ template: tpl, kind: "extra", actual: actual[j]! });
      j++;
    } else {
      if (!sameEntry(golden[i]!, actual[j]!)) {
        recs.push({ template: tpl, kind: "diff", golden: golden[i]!, actual: actual[j]! });
      }
      i++;
      j++;
    }
  }
  return recs;
}

function exempted(rec: DiffRecord, exs: Exemption[]): number {
  for (let i = 0; i < exs.length; i++) {
    const e = exs[i]!;
    if (e.template !== rec.template || e.kind !== rec.kind) continue;
    const entry = rec.kind === "extra" ? rec.actual : rec.golden;
    if (entry !== undefined && e.algorithm === entry.algorithm && e.phase === entry.phase && e.desc === entry.desc) {
      return i;
    }
  }
  return -1;
}

/** 字节序排序（Go sort.Strings 口径）。 */
function byteSort(xs: string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

export interface ParsedArgs {
  only: string;
  backendWasm: boolean;
  catalogCheck: boolean;
  catalogSelftest: boolean;
  freeze: boolean;
}

export function parseArgs(argv: string[]): { args: ParsedArgs } | { usage: string } {
  const args: ParsedArgs = { only: "", backendWasm: false, catalogCheck: false, catalogSelftest: false, freeze: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    const eq = a.indexOf("=");
    const flag = eq >= 0 ? a.slice(0, eq) : a;
    switch (flag) {
      case "-only":
      case "--only": {
        const v = eq >= 0 ? a.slice(eq + 1) : argv[++i];
        if (v === undefined) return { usage: "--only 缺值" };
        args.only = v;
        break;
      }
      case "-backend-wasm":
      case "--backend-wasm":
        args.backendWasm = true;
        break;
      case "-catalog-check":
      case "--catalog-check":
        args.catalogCheck = true;
        break;
      case "-catalog-selftest":
      case "--catalog-selftest":
        args.catalogSelftest = true;
        break;
      case "-freeze":
      case "--freeze":
        args.freeze = true;
        break;
      default:
        return { usage: `未知参数 ${JSON.stringify(a)}` };
    }
  }
  return { args };
}

export function main(argv: string[]): number {
  const parsed = parseArgs(argv);
  if ("usage" in parsed) {
    // 用法错 = exit 2（Go flag 包同口径），与判定红的 1 分流
    process.stderr.write(`teaching_annotation_diff: ${parsed.usage}（用法: main.mts [--only a,b] [--backend-wasm] [--freeze] [--catalog-check] [--catalog-selftest]）\n`);
    return 2;
  }
  const { args } = parsed;
  const root = projectRoot();
  const opts: ServingOptions = { backendWasm: args.backendWasm };

  if (args.catalogCheck || args.catalogSelftest) {
    const r = runCatalogCheck(root, args.catalogSelftest);
    if (r.error !== undefined) {
      process.stdout.write("错误: " + r.error + "\n");
      return 2;
    }
    return r.code;
  }

  const rulesPath = path.join(root, "scripts", "teaching_annotation_diff", "rules.json");
  const goldenPath = path.join(root, "scripts", "teaching_annotation_diff", "golden", "algorithm_annotations_v3.json");
  // 过渡对账臂（#39 libc 同模式）：旧份存在期间 sha256 必须一致；旧份消失自动豁免
  const legacyGolden = path.join(root, "native", "tests", "golden", "algorithm_annotations_v3.json");

  let gb: string;
  try {
    gb = fs.readFileSync(goldenPath, "latin1");
  } catch (e) {
    process.stdout.write("错误: 读 golden 真源失败: " + (e instanceof Error ? e.message : String(e)) + "\n");
    return 2;
  }
  if (fs.existsSync(legacyGolden)) {
    const lb = fs.readFileSync(legacyGolden, "latin1");
    const norm = (s: string): Buffer => Buffer.from(s.replace(/\r\n/g, "\n"), "latin1");
    if (!norm(gb).equals(norm(lb))) {
      process.stdout.write("错误: golden 过渡对账红——新旧份内容不一致（scripts/teaching_annotation_diff/golden/ ↔ native/tests/golden/）\n");
      return 1;
    }
  }

  let rules: Rules;
  let golden: Record<string, FirstOccurrence[]>;
  try {
    rules = loadRules(rulesPath);
    golden = JSON.parse(fs.readFileSync(goldenPath, "utf8")) as Record<string, FirstOccurrence[]>;
  } catch (e) {
    process.stdout.write("错误: " + (e instanceof Error ? e.message : String(e)) + "\n");
    return 2;
  }
  const migrated = new Set(rules.migrated_algorithms);
  const exemptions = rules.exemptions as Exemption[];

  let exe = serveExe(root);
  if (args.backendWasm) {
    const shell = path.join(root, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_wasm", "vitro_wasm.js");
    const wasmMod = path.join(root, "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm");
    if (!fs.existsSync(shell)) {
      process.stdout.write(`错误: wasm 臂产物缺失 ${shell}（统一入口壳）\n`);
      return 2;
    }
    // wasm 产物新鲜度门禁（批五 P2-5：存在性 + mtime 触发 + 构建复核）
    ensureFresh("teaching_annotation_diff", wasmMod, ["build", "--release", "--target", "wasm-gc", "gateway/wasm"]);
    ensureFresh("teaching_annotation_diff_glue", shell, ["build", "--release", "--target", "js", "cmd/vitro_wasm"]);
    exe = shell;
  } else {
    ensureFresh("teaching_annotation_diff", exe, ["build", "--target", "native", "cmd/serve"]);
  }

  let tplNames: string[];
  try {
    tplNames = [];
    const onlySet = new Set(args.only === "" ? [] : args.only.split(",").map((s) => s.trim()));
    for (const name of fs.readdirSync(path.join(root, "templates")).sort()) {
      const dir = path.join(root, "templates", name);
      if (!fs.statSync(dir).isDirectory()) continue;
      if (!fs.existsSync(path.join(dir, "source.c"))) continue;
      if (onlySet.size > 0 && !onlySet.has(name)) continue;
      tplNames.push(name);
    }
  } catch (e) {
    process.stdout.write("错误: templates 目录不可读: " + (e instanceof Error ? e.message : String(e)) + "\n");
    return 2;
  }
  if (tplNames.length === 0) {
    process.stdout.write("错误: 模板集为空\n");
    return 2;
  }
  process.stdout.write(
    `teaching_annotation_diff: ${tplNames.length} 模板 × 已迁移族 ${migrated.size} 算法（budget ${rules.step_budget}；豁免 ${exemptions.length}）\n`,
  );

  // golden 过滤（族级）：每模板的已迁移族条目
  const goldenFiltered = new Map<string, FirstOccurrence[]>();
  const goldenNonEmpty = new Set<string>();
  for (const [tpl, entries] of Object.entries(golden)) {
    const f = filterMigrated(entries, migrated);
    goldenFiltered.set(tpl, f);
    if (f.length > 0) goldenNonEmpty.add(tpl);
  }

  const fails: string[] = [];
  const actualNonEmpty = new Set<string>();
  const exemptUsed = new Set<number>();
  tplNames.forEach((tpl, idx) => {
    let src: string;
    try {
      src = fs.readFileSync(path.join(root, "templates", tpl, "source.c"), "utf8");
    } catch (e) {
      process.stdout.write("错误: 读模板失败: " + tpl + " " + (e instanceof Error ? e.message : String(e)) + "\n");
      process.exit(2);
    }
    let actual: FirstOccurrence[];
    try {
      actual = extractViaServe(exe, src, rules.step_budget, opts);
    } catch (e) {
      fails.push(`[${tpl}] 提取失败: ${e instanceof Error ? e.message : String(e)}`);
      return;
    }
    const actualF = filterMigrated(actual, migrated);
    if (actualF.length > 0) actualNonEmpty.add(tpl);
    const gF = goldenFiltered.get(tpl) ?? [];
    for (const rec of compareTemplate(tpl, gF, actualF)) {
      const ei = exempted(rec, exemptions);
      if (ei >= 0) {
        exemptUsed.add(ei);
        continue;
      }
      fails.push(recordString(rec));
    }
    if ((idx + 1) % 10 === 0 || idx === tplNames.length - 1) process.stdout.write(`  … ${idx + 1}/${tplNames.length}\n`);
  });

  // -freeze：首现序列以当前被测物为准写回 golden（过滤后形态）。人工令专用；
  // 禁止与 --only 同用（子集会漏写其余模板）。
  if (args.freeze) {
    if (args.only !== "") {
      process.stdout.write("错误: --freeze 须全量模式（--only 子集会漏写其余模板）\n");
      return 2;
    }
    const frozen: Record<string, FirstOccurrence[]> = {};
    for (let idx = 0; idx < tplNames.length; idx++) {
      const tpl = tplNames[idx]!;
      let src: string;
      try {
        src = fs.readFileSync(path.join(root, "templates", tpl, "source.c"), "utf8");
      } catch (e) {
        process.stdout.write("错误: 读模板失败: " + tpl + " " + (e instanceof Error ? e.message : String(e)) + "\n");
        return 2;
      }
      let actual: FirstOccurrence[];
      try {
        actual = extractViaServe(exe, src, rules.step_budget, opts);
      } catch (e) {
        process.stdout.write("错误: 冻结提取失败: " + tpl + " " + (e instanceof Error ? e.message : String(e)) + "\n");
        return 2;
      }
      const f = filterMigrated(actual, migrated);
      if (f.length > 0) frozen[tpl] = f;
      if ((idx + 1) % 10 === 0 || idx === tplNames.length - 1) process.stdout.write(`  … 冻结 ${idx + 1}/${tplNames.length}\n`);
    }
    // Go MarshalIndent：map 键排序 + struct 字段序（六字段）
    const ordered: Record<string, unknown[]> = {};
    for (const k of byteSort(Object.keys(frozen))) {
      ordered[k] = (frozen[k] ?? []).map((e) => ({
        algorithm: e.algorithm,
        display_name: e.display_name,
        phase: e.phase,
        desc: e.desc,
        code_line: e.code_line,
        src: e.src,
      }));
    }
    try {
      fs.writeFileSync(goldenPath, JSON.stringify(ordered, null, 2) + "\n", "utf8");
    } catch (e) {
      process.stdout.write("错误: golden 写回失败: " + (e instanceof Error ? e.message : String(e)) + "\n");
      return 2;
    }
    process.stdout.write(`golden 已重冻 → ${goldenPath}（${Object.keys(frozen).length} 模板）\n`);
    return 0;
  }

  // 双向模板集（--only 子集模式跳过该断言）
  if (args.only === "") {
    for (const tpl of byteSort([...goldenNonEmpty])) {
      if (!actualNonEmpty.has(tpl)) fails.push(`[模板集] golden 有已迁移族条目但 MoonBit 零标注: ${tpl}`);
    }
    for (const tpl of byteSort([...actualNonEmpty])) {
      if (!goldenNonEmpty.has(tpl)) fails.push(`[模板集] MoonBit 报已迁移族标注但 golden 无该模板条目: ${tpl}`);
    }
    // 豁免僵尸检测：未触达的豁免条目 = 僵尸，红
    exemptions.forEach((e, i) => {
      if (!exemptUsed.has(i)) fails.push(`[豁免僵尸] 未触达: ${JSON.stringify(e)}`);
    });
  }

  if (fails.length > 0) {
    process.stdout.write(`\nFAIL: ${fails.length} 处不一致\n`);
    fails.forEach((f, i) => {
      if (i >= 40) {
        process.stdout.write(`  … 其余 ${fails.length - 40} 处略\n`);
        return;
      }
      process.stdout.write("  " + f + "\n");
    });
    return 1;
  }
  process.stdout.write("OK: 已迁移族首现序列与 golden 逐条一致（双向模板集相等）\n");
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
