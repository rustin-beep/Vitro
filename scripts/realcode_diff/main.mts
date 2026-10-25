#!/usr/bin/env node
// vitro_clang_diff —— Vitro vs Clang 逐文件对比勘探（Go→.mts 重写，refs #273）。
//
// 四种模式（与 Go 版 CLI 同形）：
//   勘探（-repo）：外部 C 仓库全量对比（Clang 真值 → serve 连发 → 剥壳重试 → 运行对比）
//   勘探（-corpus）：仓内语料批（Clang + gcc 分桶 + Vitro 三方；子目录 = 多文件工程）
//   聚合（-aggregate）：result.json → gold_<corpus>.json（只取测量签名）
//   合规（-check）：仓内金样本静态合规闸 + corpora.json 三向对账
//
// 协议红线：勘探产物（report.md / result.json）不进仓——诊断 message 可引用源码
// token；仓内只收测量签名。真值口径 = Clang；Vitro 输出不作 C 语义依据。
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { fatal } from "../internal/capi.mts";
import { byteCompare, byteSort, goJSONMarshalIndent } from "../internal/text.mts";
import { runAggregate } from "./aggregate.mts";
import { runCheck } from "./check_gold.mts";
import { compareWithGold } from "./compare_gold.mts";
import {
  clangCheck,
  clangCheckProject,
  findGcc,
  gccCheck,
  gccCheckProject,
  runCompare,
  serveBatchFiles,
  serveBatchKeys,
} from "./probes.mts";
import { layerOf, stripStdbool, stripStmtExprs } from "./stmt_expr.mts";
import type { CompileFile, Diag, FileResult, Project } from "./types.mts";

// ---------- CLI（Go flag 包语义：-x v / -x=v / --x；布尔支持 =value；遇位置参数即止） ----------
export interface CliOptions {
  repo: string;
  out: string;
  filter: string;
  limit: number;
  batch: number;
  vitro: string;
  aggregate: string;
  check: boolean;
  corpus: string;
  goldOut: string;
  aggRepo: string;
  aggSourceFork: string;
  aggSourceCommit: string;
  gcc: string;
  /** Go 版定义但未消费——保留旗标兼容（不静默改 CLI 面）。 */
  gccOnly: boolean;
  probe: boolean;
}

function usage(): string {
  return [
    "用法: node scripts/realcode_diff/main.mts [flags]",
    "  -repo <dir>           外部 C 仓库根（勘探模式必填）",
    "  -corpus <name>        仓内语料批名（corpus/<name>/）",
    "  -out <dir>            输出目录（默认 _diff_out）",
    "  -aggregate <file>     聚合模式：输入 result.json",
    "  -check                合规模式：校验仓内金样本",
    "  -limit <n>  -filter <s>  -batch <n>  -probe",
    "  -gold-out <name>  -agg-repo <name>  -agg-source-fork <s>  -agg-source-commit <s>",
    "  -vitro <dir>  -gcc <path>  -gcc-only",
  ].join("\n");
}

function parseBool(name: string, v: string): boolean {
  switch (v) {
    case "1":
    case "t":
    case "T":
    case "TRUE":
    case "true":
    case "True":
      return true;
    case "0":
    case "f":
    case "F":
    case "FALSE":
    case "false":
    case "False":
      return false;
    default:
      fatal(`invalid value ${JSON.stringify(v)} for flag -${name}: parse error`);
  }
}

export function parseArgs(argv: readonly string[], vivoDefault: string): CliOptions {
  const o: CliOptions = {
    repo: "",
    out: "_diff_out",
    filter: "",
    limit: 0,
    batch: 25,
    vitro: vivoDefault,
    aggregate: "",
    check: false,
    corpus: "",
    goldOut: "gold_signatures.json",
    aggRepo: "TheAlgorithms/C",
    aggSourceFork: "https://github.com/rustin-beep/C",
    aggSourceCommit: "e5dad3f",
    gcc: "",
    gccOnly: false,
    probe: false,
  };
  const bools = new Set(["check", "gcc-only", "probe"]);
  const strings = new Set([
    "repo", "out", "filter", "vitro", "aggregate", "corpus", "gold-out",
    "agg-repo", "agg-source-fork", "agg-source-commit", "gcc",
  ]);
  const ints = new Set(["limit", "batch"]);

  for (let i = 0; i < argv.length; i++) {
    let tok = argv[i] as string;
    if (tok === "--") break;
    if (tok === "-" || !tok.startsWith("-")) break;
    tok = tok.startsWith("--") ? tok.slice(2) : tok.slice(1);
    if (tok === "h" || tok === "help") {
      process.stderr.write(usage() + "\n");
      process.exit(0);
    }
    const eq = tok.indexOf("=");
    const name = eq >= 0 ? tok.slice(0, eq) : tok;
    const inline = eq >= 0 ? tok.slice(eq + 1) : null;

    if (bools.has(name)) {
      const val = inline === null ? true : parseBool(name, inline);
      if (name === "check") o.check = val;
      else if (name === "gcc-only") o.gccOnly = val;
      else o.probe = val;
      continue;
    }
    if (!strings.has(name) && !ints.has(name)) {
      fatal(`flag provided but not defined: -${name}`);
    }
    let val = inline;
    if (val === null) {
      i++;
      if (i >= argv.length) fatal(`flag needs an argument: -${name}`);
      val = argv[i] as string;
    }
    if (ints.has(name)) {
      const n = Number(val);
      if (!/^[+-]?\d+$/.test(val) || !Number.isFinite(n)) {
        fatal(`invalid value ${JSON.stringify(val)} for flag -${name}: parse error`);
      }
      if (name === "limit") o.limit = n;
      else o.batch = n;
      continue;
    }
    switch (name) {
      case "repo":
        o.repo = val;
        break;
      case "out":
        o.out = val;
        break;
      case "filter":
        o.filter = val;
        break;
      case "vitro":
        o.vitro = val;
        break;
      case "aggregate":
        o.aggregate = val;
        break;
      case "corpus":
        o.corpus = val;
        break;
      case "gold-out":
        o.goldOut = val;
        break;
      case "agg-repo":
        o.aggRepo = val;
        break;
      case "agg-source-fork":
        o.aggSourceFork = val;
        break;
      case "agg-source-commit":
        o.aggSourceCommit = val;
        break;
      case "gcc":
        o.gcc = val;
        break;
      default:
        fatal(`flag provided but not defined: -${name}`);
    }
  }
  return o;
}

// ---------- 仓库根（Go mustRepoRoot：VITRO_ROOT → . / .. / ../..） ----------
function mustRepoRoot(): string {
  const env = process.env.VITRO_ROOT;
  if (env !== undefined && env !== "") return path.resolve(env);
  for (const cand of [".", "..", "../.."]) {
    try {
      if (fs.statSync(path.join(cand, "scripts", "realcode_diff")).isDirectory()) {
        return path.resolve(cand);
      }
    } catch {
      // 继续回退
    }
  }
  fatal("无法定位仓库根（请设 VITRO_ROOT）");
}

// ---------- 文件工具 ----------
function readFileUtf8(p: string): string {
  try {
    return fs.readFileSync(p, "utf8");
  } catch {
    return "";
  }
}

function relOf(repo: string, p: string): string {
  return path.relative(repo, p).split(path.sep).join("/");
}

function sortedDirents(dir: string): fs.Dirent[] {
  return fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => byteCompare(a.name, b.name));
}

function isDir(p: string): boolean {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function collectProject(dir: string): Project {
  const p: Project = { name: path.basename(dir), dir, files: [], units: [] };
  for (const e of sortedDirents(dir)) {
    if (e.isDirectory()) continue;
    const full = path.join(dir, e.name);
    if (e.name.endsWith(".c")) p.files.push(full);
    else if (e.name.endsWith(".h")) p.units.push(full);
  }
  p.files.sort(byteCompare);
  p.units.sort(byteCompare);
  return p;
}

function walkCFiles(dir: string, out: string[]): void {
  for (const e of sortedDirents(dir)) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walkCFiles(full, out);
    else if (e.name.endsWith(".c")) out.push(full);
  }
}

function dirIsGreen(green: readonly string[], dir: string): boolean {
  return green.includes(dir);
}

// ---------- 报告 ----------
function localDateTime(d = new Date()): string {
  const p = (n: number): string => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

export function writeReport(out: string, results: readonly FileResult[]): void {
  let clangRed = 0;
  let bothGreen = 0;
  let vitroRed = 0;
  const codeCount = new Map<string, number>();
  const warnFiles = new Map<string, string[]>();
  const layerCount = new Map<string, number>();
  for (const r of results) {
    const layer = r.vitro_layer ?? "";
    layerCount.set(layer, (layerCount.get(layer) ?? 0) + 1);
    if (!r.clang_ok) clangRed++;
    else if (r.vitro_errors === 0) bothGreen++;
    else vitroRed++;
    for (const d of r.vitro_diags ?? []) {
      if (d.severity === "error") {
        codeCount.set(d.code, (codeCount.get(d.code) ?? 0) + 1);
      } else if (d.code !== "") {
        const list = warnFiles.get(d.code) ?? [];
        list.push(r.path);
        warnFiles.set(d.code, list);
      }
    }
  }

  let b = "";
  b += "# Vitro vs Clang 对比勘探报告\n\n";
  b += `生成: ${localDateTime()}\n\n`;
  b += "## 分桶\n\n| 桶 | 数量 |\n|---|---|\n";
  b += `| 总文件 | ${results.length} |\n`;
  b += `| Clang 红(平台差异/真错/链接需求) | ${clangRed} |\n`;
  b += `| 双绿 | ${bothGreen} |\n`;
  b += `| Vitro 红(Clang 绿) | ${vitroRed} |\n\n`;

  b += "## Vitro 诊断码 top\n\n| 码 | 次数 |\n|---|---|\n";
  const codeEntries = [...codeCount.entries()].sort((x, y) => y[1] - x[1] || byteCompare(x[0], y[0]));
  for (const [k, v] of codeEntries) b += `| ${k} | ${v} |\n`;

  b += "\n## 层分布(Clang 绿样本)\n\n| 层 | 数量 |\n|---|---|\n";
  for (const l of ["ok", "typeck", "parse", "lex", ""]) {
    const n = layerCount.get(l) ?? 0;
    if (n > 0) b += `| ${l} | ${n} |\n`;
  }

  if (warnFiles.size > 0) {
    b += "\n## W 警告(serve 通道)\n\n| 码 | 文件 |\n|---|---|\n";
    for (const k of byteSort([...warnFiles.keys()])) {
      b += `| ${k} | ${(warnFiles.get(k) ?? []).join(", ")} |\n`;
    }
  }

  b += "\n## 运行对比(双绿桶)\n\n";
  const runCount = new Map<string, number>();
  for (const r of results) {
    const rc = r.run_compare ?? "";
    if (rc !== "") runCount.set(rc, (runCount.get(rc) ?? 0) + 1);
  }
  for (const k of byteSort([...runCount.keys()])) b += `- ${k}: ${runCount.get(k) ?? 0}\n`;
  b += "\n### 不一致明细\n\n";
  for (const r of results) {
    if (r.run_compare === "mismatch" || r.run_compare === "vitro_run_fail" || r.run_compare === "clang_build_fail") {
      b += `- \`${r.path}\`: ${r.run_compare} — ${r.run_detail ?? ""}\n`;
    }
  }

  b += "\n## Clang 红明细(前 40)\n\n";
  let n = 0;
  for (const r of results) {
    if (!r.clang_ok && n < 40) {
      b += `- \`${r.path}\`: ${r.clang_first_error ?? ""}\n`;
      n++;
    }
  }

  b += "\n## Vitro 红明细(层+首诊断, 前 60)\n\n";
  n = 0;
  for (const r of results) {
    if (r.clang_ok && r.vitro_errors > 0 && n < 60) {
      let first = "";
      for (const d of r.vitro_diags ?? []) {
        if (d.severity === "error") {
          first = `${d.code} ${d.line}:${d.column} ${d.message}`;
          break;
        }
      }
      const stripLayer = r.stripped_try ? (r.strip_layer ?? "") : "-";
      b += `- \`${r.path}\` [${r.vitro_layer ?? ""}] 剥壳层=${stripLayer}/${r.strip_errors ?? 0}: ${first}\n`;
      n++;
    }
  }

  fs.writeFileSync(path.join(out, "report.md"), b, "utf8");
}

// ---------- result.json（Go 结构体字段序 + omitempty） ----------
function toJSONResult(r: FileResult): Record<string, unknown> {
  const o: Record<string, unknown> = {
    path: r.path,
    clang_ok: r.clang_ok,
    gcc_ok: r.gcc_ok,
    clang_errors: r.clang_errors,
    clang_warnings: r.clang_warnings,
  };
  if (r.clang_first_error !== undefined && r.clang_first_error !== "") {
    o["clang_first_error"] = r.clang_first_error;
  }
  if (r.vitro_diags !== undefined && r.vitro_diags.length > 0) {
    o["vitro_diags"] = r.vitro_diags.map((d) => ({
      severity: d.severity,
      code: d.code,
      line: d.line,
      column: d.column,
      message: d.message,
    }));
  }
  o["vitro_errors"] = r.vitro_errors;
  o["vitro_warnings"] = r.vitro_warnings;
  if (r.vitro_layer !== undefined && r.vitro_layer !== "") o["vitro_layer"] = r.vitro_layer;
  o["stripped_try"] = r.stripped_try;
  if (r.strip_layer !== undefined && r.strip_layer !== "") o["strip_layer"] = r.strip_layer;
  if (r.strip_errors !== undefined && r.strip_errors !== 0) o["strip_errors"] = r.strip_errors;
  if (r.run_compare !== undefined && r.run_compare !== "") o["run_compare"] = r.run_compare;
  if (r.run_detail !== undefined && r.run_detail !== "") o["run_detail"] = r.run_detail;
  return o;
}

function writeResult(out: string, results: readonly FileResult[]): void {
  fs.writeFileSync(path.join(out, "result.json"), goJSONMarshalIndent(results.map(toJSONResult)), "utf8");
}

// ---------- 回填 / 分桶 ----------
function backfill(results: FileResult[], served: Map<string, Diag[]>): void {
  for (const r of results) {
    const diags = served.get(r.path);
    if (diags === undefined) continue;
    r.vitro_diags = diags;
    for (const d of diags) {
      if (d.severity === "error") r.vitro_errors++;
      else r.vitro_warnings++;
    }
    r.vitro_layer = layerOf(diags);
  }
}

function errCount(diags: readonly Diag[] | undefined): number {
  let n = 0;
  for (const d of diags ?? []) if (d.severity === "error") n++;
  return n;
}

// ---------- P4': 剥壳对照 ----------
async function runProbeDiff(
  vitroRoot: string,
  repoAbs: string,
  green: readonly string[],
  served: Map<string, Diag[]>,
  out: string,
): Promise<string[]> {
  const tmpDir = path.join(out, "_probe");
  fs.mkdirSync(tmpDir, { recursive: true });
  for (const e of sortedDirents(repoAbs)) {
    if (e.isDirectory() || !e.name.endsWith(".h")) continue;
    try {
      fs.copyFileSync(path.join(repoAbs, e.name), path.join(tmpDir, e.name));
    } catch {
      // 头文件复制失败不阻断主报告
    }
  }
  const rows: string[] = [
    "# 剥壳对照报告（GNU 语句表达式消解）",
    "",
    "> 目的：识别被 parse 层 E2005 洪水遮蔽的深层诊断。",
    "> 消解规则：`({ stmts; expr; })` → `{ stmts; int __vitro_sxN = expr; __vitro_sxN }`（保值语义）。",
    "> 保守边界：含 return/break/continue/goto 的语句体不消解。",
    "> 等价性已验：28 份消解副本的 Clang 错误数与原始逐份一致（28/28）；其中绿语料错误集逐字节一致（10/10）、红 3 份次生差异根因语料自身（README.corpus 口径注）。",
    "",
    "| 文件 | 消解处数 | 原始 errs | 剥壳后 errs | 原始首码 | 剥壳后码分布 |",
    "|---|---|---|---|---|---|",
  ];
  for (const p of green) {
    if (isDir(p)) continue;
    const rel = relOf(repoAbs, p);
    const orig = served.get(rel) ?? [];
    const origErrs = errCount(orig);
    const origFirst = orig.find((d) => d.severity === "error")?.code ?? "";
    const stripped = stripStmtExprs(readFileUtf8(p));
    if (stripped.count === 0) continue;
    const tmpFile = path.join(tmpDir, path.basename(p));
    try {
      fs.writeFileSync(tmpFile, stripped.src, "utf8");
    } catch {
      continue;
    }
    let diags: Diag[];
    try {
      diags = (await serveBatchFiles(vitroRoot, [rel], [{ path: tmpFile }])).get(rel) ?? [];
    } catch {
      continue;
    }
    const newErrs = errCount(diags);
    const codeCount = new Map<string, number>();
    for (const d of diags) {
      if (d.severity === "error") codeCount.set(d.code, (codeCount.get(d.code) ?? 0) + 1);
    }
    const codes = [...codeCount.entries()]
      .sort((a, b) => b[1] - a[1] || byteCompare(a[0], b[0]))
      .map(([k, v]) => `${k}×${v}`)
      .join(" ");
    rows.push(`| \`${rel}\` | ${stripped.count} | ${origErrs} | ${newErrs} | ${origFirst} | ${codes} |`);
  }
  return rows;
}

// ---------- -corpus 模式 ----------
export async function runCorpus(
  name: string,
  opts: CliOptions,
  root: string,
  vitroRoot: string,
): Promise<number> {
  const batch = requireBatch(opts);
  const corpusDir = path.join(root, "scripts", "realcode_diff", "corpus", name);
  if (!isDir(corpusDir)) fatal(`仓内语料批不存在: ${corpusDir}`);
  fs.mkdirSync(opts.out, { recursive: true });

  const all: string[] = [];
  const projects: Project[] = [];
  for (const e of sortedDirents(corpusDir)) {
    if (e.isDirectory()) {
      projects.push(collectProject(path.join(corpusDir, e.name)));
      continue;
    }
    if (e.name.endsWith(".c")) all.push(path.join(corpusDir, e.name));
  }
  all.sort(byteCompare);
  projects.sort((a, b) => byteCompare(a.name, b.name));

  let files = all;
  let projs = projects;
  if (opts.filter !== "") {
    files = files.filter((p) => path.resolve(p).split(path.sep).join("/").includes(opts.filter));
    projs = projs.filter((p) => p.name.includes(opts.filter));
  }
  if (opts.limit > 0 && files.length > opts.limit) files = files.slice(0, opts.limit);
  if (files.length === 0 && projs.length === 0) fatal(`语料批 ${name} 下无 .c 文件`);
  process.stderr.write(`[${name}] 单文件: ${files.length} ; 多文件工程: ${projs.length}\n`);

  const repoAbs = path.resolve(corpusDir);
  const results: FileResult[] = [];
  const green: string[] = [];

  for (const p of files) {
    const rel = relOf(repoAbs, p);
    const c = await clangCheck(p);
    results.push({
      path: rel,
      clang_ok: c.ok,
      gcc_ok: false,
      clang_errors: c.errs,
      clang_warnings: c.warns,
      clang_first_error: c.first,
      vitro_errors: 0,
      vitro_warnings: 0,
      stripped_try: false,
    });
    if (c.ok) green.push(p);
  }
  for (const pr of projs) {
    const c = await clangCheckProject(pr);
    results.push({
      path: pr.name + "/",
      clang_ok: c.ok,
      gcc_ok: false,
      clang_errors: c.errs,
      clang_warnings: 0,
      clang_first_error: c.first,
      vitro_errors: 0,
      vitro_warnings: 0,
      stripped_try: false,
    });
    if (c.ok) green.push(pr.dir);
  }
  process.stderr.write(
    `[${name}] Clang 绿: ${green.length} / 红: ${files.length + projs.length - green.length}\n`,
  );

  const gcc = findGcc(opts.gcc);
  if (gcc === "") {
    fatal(
      "gcc 分桶裁判不可用：--gcc 未指定、PATH 无 gcc、D:\\code\\mingw64\\bin\\gcc.exe 不存在（fail loud）",
    );
  }
  process.stderr.write(`[${name}] gcc: ${gcc}\n`);
  const gccRes = new Map<string, boolean>();
  for (const p of files) gccRes.set(relOf(repoAbs, p), (await gccCheck(gcc, p)).ok);
  for (const pr of projs) gccRes.set(pr.name + "/", (await gccCheckProject(gcc, pr)).ok);

  const served = new Map<string, Diag[]>();
  for (let i = 0; i < green.length; i += batch) {
    const end = Math.min(i + batch, green.length);
    const keys: string[] = [];
    const units: CompileFile[] = [];
    for (const p of green.slice(i, end)) {
      if (isDir(p)) continue;
      keys.push(relOf(repoAbs, p));
      units.push({ path: p });
    }
    if (keys.length > 0) {
      let res: Map<string, Diag[]>;
      try {
        res = await serveBatchFiles(vitroRoot, keys, units);
      } catch (e) {
        fatal(`serve 批失败(${i}..${end}): ${e instanceof Error ? e.message : String(e)}`);
      }
      for (const [k, v] of res) served.set(k, v);
    }
    process.stderr.write(`[${name}] serve ${end}/${green.length}\n`);
  }
  for (const pr of projs) {
    const key = pr.name + "/";
    if (!dirIsGreen(green, pr.dir)) continue;
    const units = [...pr.files, ...pr.units].map((p) => ({ path: p }));
    try {
      const res = await serveBatchFiles(vitroRoot, [key], units);
      for (const [k, v] of res) served.set(k, v);
      process.stderr.write(`[${name}] 工程 ${pr.name}: ${pr.files.length} .c + ${pr.units.length} .h\n`);
    } catch (e) {
      process.stderr.write(
        `[${name}] 工程 ${pr.name} serve 失败: ${e instanceof Error ? e.message : String(e)}\n`,
      );
    }
  }

  backfill(results, served);

  const probeRows = opts.probe ? await runProbeDiff(vitroRoot, repoAbs, green, served, opts.out) : [];

  for (const p of green) {
    if (isDir(p)) continue;
    const rel = relOf(repoAbs, p);
    if (errCount(served.get(rel)) > 0) continue;
    const idx = results.findIndex((r) => r.path === rel);
    if (idx < 0) continue;
    const hasRand = readFileUtf8(p).includes("rand(");
    const c = await runCompare(vitroRoot, p, path.join(opts.out, "_tmp"), false, hasRand);
    const r = results[idx] as FileResult;
    r.run_compare = c.verdict;
    r.run_detail = c.detail;
  }

  for (const r of results) {
    const ok = gccRes.get(r.path);
    if (ok !== undefined) r.gcc_ok = ok;
  }

  writeReport(opts.out, results);
  if (probeRows.length > 0) {
    fs.writeFileSync(path.join(opts.out, "probe_diff.md"), probeRows.join("\n"), "utf8");
  }
  writeResult(opts.out, results);
  process.stderr.write(`[${name}] 完成: ${opts.out}/report.md\n`);
  return compareWithGold(name, results, { summary: "stderr" });
}

// ---------- -repo 模式 ----------
export async function runRepo(opts: CliOptions, vitroRoot: string): Promise<number> {
  const batch = requireBatch(opts);
  fs.mkdirSync(opts.out, { recursive: true });
  const repoAbs = path.resolve(opts.repo);
  if (!isDir(repoAbs)) fatal(`-repo 目录不存在: ${repoAbs}`);

  let all: string[] = [];
  walkCFiles(repoAbs, all);
  all.sort(byteCompare);
  if (opts.filter !== "") {
    all = all.filter((p) => p.split(path.sep).join("/").includes(opts.filter));
  }
  if (opts.limit > 0 && all.length > opts.limit) all = all.slice(0, opts.limit);
  process.stderr.write(`文件数: ${all.length}\n`);

  const results: FileResult[] = [];
  const green: string[] = [];
  const tmpDir = path.resolve(path.join(opts.out, "_tmp"));
  fs.mkdirSync(tmpDir, { recursive: true });

  for (const p of all) {
    const rel = relOf(repoAbs, p);
    const c = await clangCheck(p);
    results.push({
      path: rel,
      clang_ok: c.ok,
      gcc_ok: false,
      clang_errors: c.errs,
      clang_warnings: c.warns,
      clang_first_error: c.first,
      vitro_errors: 0,
      vitro_warnings: 0,
      stripped_try: false,
    });
    if (c.ok) green.push(p);
  }
  process.stderr.write(`Clang 绿: ${green.length} / 红: ${all.length - green.length}\n`);

  const served = new Map<string, Diag[]>();
  for (let i = 0; i < green.length; i += batch) {
    const end = Math.min(i + batch, green.length);
    const slice = green.slice(i, end);
    const keys = slice.map((p) => relOf(repoAbs, p));
    let res: Map<string, Diag[]>;
    try {
      res = await serveBatchKeys(vitroRoot, keys, slice);
    } catch (e) {
      fatal(`serve 批失败(${i}..${end}): ${e instanceof Error ? e.message : String(e)}`);
    }
    for (const [k, v] of res) served.set(k, v);
    process.stderr.write(`serve ${end}/${green.length}\n`);
  }

  // P4：Vitro 红的文件做 stdbool 剥壳重试
  const stripSrc = new Map<string, string>();
  for (const p of green) {
    const rel = relOf(repoAbs, p);
    if (errCount(served.get(rel)) === 0) continue;
    const s = stripStdbool(readFileUtf8(p));
    if (s.changed) stripSrc.set(rel, s.src);
  }
  if (stripSrc.size > 0) {
    const rels = byteSort([...stripSrc.keys()]);
    for (let i = 0; i < rels.length; i += batch) {
      const end = Math.min(i + batch, rels.length);
      const keys: string[] = [];
      const paths: string[] = [];
      for (const rel of rels.slice(i, end)) {
        const tmp = path.join(tmpDir, `strip_${paths.length}.c`);
        fs.writeFileSync(tmp, stripSrc.get(rel) ?? "", "utf8");
        keys.push(rel);
        paths.push(tmp);
      }
      try {
        const res = await serveBatchKeys(repoAbs, keys, paths);
        for (const r of results) {
          const diags = res.get(r.path);
          if (diags === undefined) continue;
          r.stripped_try = true;
          r.strip_errors = errCount(diags);
          r.strip_layer = layerOf(diags);
        }
      } catch (e) {
        process.stderr.write(`剥壳批失败: ${e instanceof Error ? e.message : String(e)}\n`);
        continue;
      }
      process.stderr.write(`剥壳 ${end}/${rels.length}\n`);
    }
  }

  backfill(results, served);

  for (const p of green) {
    const rel = relOf(repoAbs, p);
    if (errCount(served.get(rel)) > 0) continue;
    const idx = results.findIndex((r) => r.path === rel);
    if (idx < 0) continue;
    const lower = rel.toLowerCase();
    const skipNet = rel.includes("client_server") || lower.includes("socket") || lower.includes("networking");
    const hasRand = readFileUtf8(p).includes("rand(");
    const c = await runCompare(vitroRoot, p, tmpDir, skipNet, hasRand);
    const r = results[idx] as FileResult;
    r.run_compare = c.verdict;
    r.run_detail = c.detail;
    process.stderr.write(`run: ${rel} → ${c.verdict}\n`);
  }

  writeReport(opts.out, results);
  writeResult(opts.out, results);
  process.stderr.write(`完成: ${opts.out}/report.md\n`);
  return 0;
}

function requireBatch(opts: CliOptions): number {
  if (opts.batch <= 0) fatal("-batch 必须 > 0");
  return opts.batch;
}

// ---------- main ----------
export async function main(argv: readonly string[]): Promise<number> {
  const root = mustRepoRoot();
  const opts = parseArgs(argv, root);
  if (opts.check) return runCheck(root);
  if (opts.aggregate !== "") {
    return runAggregate(opts.aggregate, {
      goldOut: opts.goldOut,
      aggRepo: opts.aggRepo,
      sourceFork: opts.aggSourceFork,
      sourceCommit: opts.aggSourceCommit,
    });
  }
  if (opts.corpus !== "") return runCorpus(opts.corpus, opts, root, opts.vitro);
  if (opts.repo === "") fatal("必填 -repo（或用 -aggregate/-check/-corpus 模式）");
  return runRepo(opts, opts.vitro);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e: unknown) => fatal(e instanceof Error ? e.message : String(e)),
  );
}
