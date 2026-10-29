#!/usr/bin/env node
// mutation_gate —— #368 第一层：scripts 面 diff 级突变闸（Stryker 封装）。
//
// 形态（report-only 观察期，2026-10-29 起）：对 diff 触达的 scripts 源文件
// 生成行级突变（Stryker instrument），以「传递导入闭包内的全部 node:test」
// 为杀阵逐突变体判定——survived 清单 = 新扩散面的机判定义（#368 论据：
// 引入瞬间无基线，任何既有测试对该面零判别力）。**survived 不阻断**
// （观察期先看信噪比）；基础设施失败（stryker 崩 / 判分失败）exit 1。
//
// 设计要点（#368 实测教训内嵌）：
//   - 杀阵 = 传递闭包而非单包（M3 教训：锚可能在别的闸/别的包的测试里，
//     杀阵窄了会批量假 survivor）；
//   - 杀阵干跑先验（环境红——如 Windows 无 sh 的 C17 形态——则该文件
//     跳过并大声报告，不静默、不误报 survived）；
//   - .test.mts 不突变（测试文件非生产码）；闭包为空的文件本身即
//     「零测试可达」发现，单列；
//   - 等价突变预期存在（#344 抽样 4/13）：观察期人工定性，白名单机制
//     随阈值阻断批落地（先证红再采信）。
//
// 用法：
//   node scripts/mutation_gate/main.mts [--base <ref>=origin/master] [--head <ref>=HEAD]
//   node scripts/mutation_gate/main.mts --files internal/canonicalize.mts   # 整文件模式（J9/手动）
// 产物：<out>/report.md + <out>/results.json（默认 tmp/mutation_gate/，gitignored）
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { projectRoot, fatal } from "../internal/capi.mts";

/** exit 1 = 基础设施失败（report-only 期 survived 不红） */
const EXIT_INFRA = 1;

export interface ParsedDiff {
  /** posix 相对 scripts/ 的文件路径 → 合并后的新侧行区间（含端点） */
  rangesByFile: Map<string, Array<[number, number]>>;
  /** diff 里出现但没有任何新侧改动区间的 .mts（纯删除/改名等） */
  skipped: string[];
}

/** 解析 `git diff --unified=0` 输出 → 新侧行区间（含端点）。 */
export function parseHunks(diffText: string): ParsedDiff {
  const rangesByFile = new Map<string, Array<[number, number]>>();
  const skipped: string[] = [];
  let current: string | null = null;
  let currentRanges: Array<[number, number]> | null = null;
  for (const line of diffText.split("\n")) {
    if (line.startsWith("+++ b/")) {
      const f = normalizeSlashes(line.slice("+++ b/".length));
      if (f.endsWith(".mts")) {
        current = f;
        currentRanges = [];
        rangesByFile.set(f, currentRanges);
      } else {
        current = null;
        currentRanges = null;
      }
      continue;
    }
    if (line.startsWith("@@")) {
      const m = /\+\d+(?:,(\d+))? @@/.exec(line);
      if (current !== null && currentRanges !== null && m !== null) {
        const count = m[1] === undefined ? 1 : Number(m[1]);
        const start = Number(/\+(\d+)/.exec(line)?.[1] ?? 0);
        if (count > 0 && start > 0) currentRanges.push([start, start + count - 1]);
      }
      continue;
    }
  }
  // 收尾：区间合并；无区间的（纯删除/改名相似行等）记 skipped
  const merged = new Map<string, Array<[number, number]>>();
  for (const [f, rs] of rangesByFile) {
    if (rs.length === 0) skipped.push(f);
    else merged.set(f, mergeRanges(rs));
  }
  return { rangesByFile: merged, skipped };
}

/** 相邻/重叠区间合并（gap<=1 视为相邻——省突变范围条目数）。 */
export function mergeRanges(rs: Array<[number, number]>): Array<[number, number]> {
  const sorted = [...rs].sort((a, b) => a[0] - b[0]);
  const out: Array<[number, number]> = [];
  for (const r of sorted) {
    const last = out[out.length - 1];
    if (last !== undefined && r[0] <= last[1] + 1) {
      last[1] = Math.max(last[1], r[1]);
    } else {
      out.push([r[0], r[1]]);
    }
  }
  return out;
}

/** 从源文本抽取相对导入（含 export-from），解析为相对某文件的 posix 规范路径。 */
export function extractRelativeImports(src: string, selfRel: string): string[] {
  const out: string[] = [];
  const re = /(?:from\s*|import\s*)(["'])(\.[^"']+)\1/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    const spec = m[2] ?? "";
    const joined = path.posix.normalize(path.posix.join(path.posix.dirname(selfRel), spec));
    out.push(joined);
  }
  return out;
}

/** 传递导入闭包内的全部测试文件（杀阵）。graph: 被导入文件 → 导入者集合。 */
export function testClosureFor(
  file: string,
  graph: Map<string, Set<string>>,
  allTestFiles: Set<string>,
): string[] {
  const seen = new Set<string>([file]);
  const queue = [file];
  const tests: string[] = [];
  while (queue.length > 0) {
    const cur = queue.shift();
    if (cur === undefined) break;
    if (cur !== file && allTestFiles.has(cur)) {
      tests.push(cur);
      continue; // 测试文件不再上溯其导入面（杀阵以测试为终点）
    }
    for (const importer of graph.get(cur) ?? []) {
      if (!seen.has(importer)) {
        seen.add(importer);
        queue.push(importer);
      }
    }
  }
  return tests.sort();
}

export interface StrykerConfig {
  testRunner: "command";
  commandRunner: { command: string };
  mutate: string[];
  ignorePatterns: string[];
  reporters: string[];
  jsonReporter: { fileName: string };
  concurrency: number;
  timeoutMS: number;
  tempDirName: string;
}

export function buildStrykerConfig(
  testFiles: string[],
  mutateSpecs: string[],
  reportRelPath: string,
  concurrency: number,
): StrykerConfig {
  return {
    testRunner: "command",
    commandRunner: { command: "node --test --test-concurrency=1 " + testFiles.join(" ") },
    mutate: mutateSpecs,
    ignorePatterns: ["tsconfig.json"],
    reporters: ["json"],
    jsonReporter: { fileName: reportRelPath },
    concurrency,
    timeoutMS: 120_000,
    tempDirName: ".stryker-tmp",
  };
}

export interface MutantLike {
  status: string;
  location: { start: { line: number } };
  mutatorName?: string;
  replacement?: string;
  description?: string;
}

export interface FileSummary {
  file: string;
  killed: number;
  survived: number;
  timeout: number;
  noCoverage: number;
  errors: number;
  total: number;
}

export function summarizeMutationReport(json: {
  files: Record<string, { mutants?: MutantLike[] }>;
}): { summaries: FileSummary[]; survivedList: string[] } {
  const summaries: FileSummary[] = [];
  const survivedList: string[] = [];
  for (const [file, body] of Object.entries(json.files)) {
    const mutants = body.mutants ?? [];
    const count = (s: string) => mutants.filter((x) => x.status === s).length;
    const total = mutants.length;
    if (total === 0) continue;
    summaries.push({
      file,
      killed: count("Killed"),
      survived: count("Survived"),
      timeout: count("Timeout"),
      noCoverage: count("NoCoverage"),
      errors: count("CompileError") + count("RuntimeError"),
      total,
    });
    for (const mu of mutants) {
      if (mu.status === "Survived") {
        survivedList.push(
          `${normalizeSlashes(file)}:${mu.location.start.line} [${mu.mutatorName ?? "?"}] ${
            (mu.description ?? "").slice(0, 90)
          }`,
        );
      }
    }
  }
  return { summaries, survivedList };
}

/** diff 侧文件（带 scripts/ 前缀，git pathspec 口径）→ 杀阵图键（相对 scripts/）。CI 首跑实锤：前缀不匹配 ⇒ 闭包空 ⇒ 全部误判零测试可达。 */
export function toScriptsRel(f: string): string {
  return f.startsWith("scripts/") ? f.slice("scripts/".length) : f;
}

function normalizeSlashes(p: string): string {
  return p.replaceAll("\\", "/");
}

function usage(msg?: string): never {
  if (msg !== undefined) process.stderr.write("参数错: " + msg + "\n");
  process.stderr.write(
    "用法: node scripts/mutation_gate/main.mts [--base <ref>=origin/master] [--head <ref>=HEAD] [--files <a.mts,b.mts>] [--out <dir>] [--concurrency <n>]\n",
  );
  process.exit(2);
}

interface FileRunResult {
  file: string;
  tests: string[];
  summaries: FileSummary[];
  survivedList: string[];
}

function main(): void {
  const argv = process.argv.slice(2);
  let base = "origin/master";
  let head = "HEAD";
  let filesOverride: string[] | null = null;
  let outDir = "";
  let concurrency = Math.max(2, Math.min(6, Math.floor(os.cpus().length / 4)));
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    const next = argv[i + 1];
    if (a === "--base" && next) { base = next; i++; }
    else if (a === "--head" && next) { head = next; i++; }
    else if (a === "--files" && next) { filesOverride = next.split(",").map((s) => normalizeSlashes(s.trim())).filter(Boolean); i++; }
    else if (a === "--out" && next) { outDir = next; i++; }
    else if (a === "--concurrency" && next) { concurrency = Number(next); i++; }
    else usage("未知参数或缺值: " + a);
  }
  const root = projectRoot();
  const scriptsDir = path.join(root, "scripts");
  const outAbs = path.resolve(root, outDir !== "" ? outDir : "tmp/mutation_gate");
  fs.mkdirSync(outAbs, { recursive: true });
  const outRelFromScripts = path.relative(scriptsDir, outAbs).replaceAll("\\", "/");

  // 1) 变更面
  let targets: Array<{ file: string; whole: boolean; ranges: Array<[number, number]> }> = [];
  if (filesOverride !== null) {
    targets = filesOverride
      .filter((f) => !f.endsWith(".test.mts"))
      .map((file) => ({ file, whole: true, ranges: [] }));
  } else {
    const diff = spawnSync("git", ["-C", root, "diff", "--unified=0", base, head, "--", "scripts"], {
      encoding: "utf8",
    });
    if (diff.status !== 0) fatal("git diff 失败: " + (diff.stderr ?? ""));
    const parsed = parseHunks(diff.stdout ?? "");
    targets = [...parsed.rangesByFile.entries()]
      .filter(([f]) => !f.endsWith(".test.mts"))
      // parseHunks 产出带 scripts/ 前缀（git pathspec 口径），杀阵图键相对
      // scripts/（CI 首跑实锤：前缀不匹配 ⇒ 闭包空 ⇒ 全部误判「零测试可达」）
      .map(([file, ranges]) => ({
        file: toScriptsRel(file),
        whole: false,
        ranges,
      }));
    for (const s of parsed.skipped) process.stdout.write(`跳过（无新侧行区间）: ${s}\n`);
  }
  if (targets.length === 0) {
    process.stdout.write("mutation_gate: 无可突变 scripts 面（diff 零 .mts 或全部为测试文件）\n");
    return;
  }

  // 2) 导入图 + 杀阵闭包
  const allMts: string[] = [];
  const walk = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name === "node_modules" || e.name === ".stryker-tmp" || e.name.startsWith(".")) continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".mts")) allMts.push(path.relative(scriptsDir, p).replaceAll("\\", "/"));
    }
  };
  walk(scriptsDir);
  const graph = new Map<string, Set<string>>();
  const allTestFiles = new Set<string>(allMts.filter((f) => f.endsWith(".test.mts")));
  for (const f of allMts) {
    const src = fs.readFileSync(path.join(scriptsDir, f), "utf8");
    for (const dep of extractRelativeImports(src, f)) {
      if (!graph.has(dep)) graph.set(dep, new Set());
      graph.get(dep)?.add(f);
    }
  }

  const results: FileRunResult[] = [];
  const envRed: string[] = [];
  const zeroTest: string[] = [];
  for (const t of targets) {
    const tests = testClosureFor(t.file, graph, allTestFiles);
    if (tests.length === 0) {
      zeroTest.push(t.file);
      continue;
    }
    // 杀阵干跑先验（环境红跳过——不静默）
    const dry = spawnSync("node", ["--test", "--test-concurrency=1", ...tests], {
      cwd: scriptsDir,
      encoding: "utf8",
    });
    if (dry.status !== 0) {
      envRed.push(t.file);
      process.stdout.write(`杀阵干跑红（环境缺口，跳过突变——CI 侧 Linux 覆盖）: ${t.file}\n`);
      continue;
    }
    const mutateSpecs = t.whole ? [t.file] : t.ranges.map(([a, b]) => `${t.file}:${a}-${b}`);
    const slug = t.file.replaceAll("/", "__").replace(/\.mts$/, "");
    const cfg = buildStrykerConfig(tests, mutateSpecs, `${outRelFromScripts}/${slug}.mutation.json`, concurrency);
    const cfgPath = path.join(outAbs, `${slug}.stryker.json`);
    fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 1));
    const strykerBin = path.join(scriptsDir, "node_modules", "@stryker-mutator", "core", "bin", "stryker.js");
    const run = spawnSync(process.execPath, [strykerBin, "run", path.relative(scriptsDir, cfgPath).replaceAll("\\", "/")], {
      cwd: scriptsDir,
      encoding: "utf8",
    });
    const reportPath = path.join(outAbs, `${slug}.mutation.json`);
    if (run.status !== 0 || !fs.existsSync(reportPath)) {
      process.stdout.write(run.stdout ?? "");
      process.stderr.write(run.stderr ?? "");
      process.stderr.write(`FATAL: stryker 失败（${t.file}）exit ${run.status}\n`);
      process.exit(EXIT_INFRA);
    }
    const report = JSON.parse(fs.readFileSync(reportPath, "utf8")) as { files: Record<string, { mutants?: MutantLike[] }> };
    const { summaries, survivedList } = summarizeMutationReport(report);
    results.push({ file: t.file, tests, summaries, survivedList });
    const tot = summaries[0] ?? null;
    process.stdout.write(
      `[${t.file}] mutants=${tot?.total ?? 0} killed=${tot?.killed ?? 0} survived=${tot?.survived ?? 0} timeout=${tot?.timeout ?? 0} nocov=${tot?.noCoverage ?? 0} err=${tot?.errors ?? 0}\n`,
    );
    fs.rmSync(path.join(scriptsDir, ".stryker-tmp"), { recursive: true, force: true });
  }

  // 3) 汇总产物
  const agg = results.reduce(
    (acc: { total: number; killed: number; survived: number; timeout: number; noCoverage: number; errors: number }, r) => {
      const s = r.summaries[0];
      if (s) {
        acc.total += s.total; acc.killed += s.killed; acc.survived += s.survived;
        acc.timeout += s.timeout; acc.noCoverage += s.noCoverage; acc.errors += s.errors;
      }
      return acc;
    },
    { total: 0, killed: 0, survived: 0, timeout: 0, noCoverage: 0, errors: 0 },
  );
  const score = agg.total > 0 ? ((agg.killed / agg.total) * 100).toFixed(1) : "n/a";
  const md: string[] = [
    "# mutation_gate 报告（report-only 观察期）",
    "",
    `- 基准：${filesOverride !== null ? "--files 整文件模式" : `${base}..${head}`}`,
    `- 突变体：${agg.total}（killed ${agg.killed} / survived ${agg.survived} / timeout ${agg.timeout} / nocov ${agg.noCoverage} / err ${agg.errors}）——score ${score}%`,
    `- 环境红跳过：${envRed.length > 0 ? envRed.join(", ") : "无"}`,
    `- 零测试可达：${zeroTest.length > 0 ? zeroTest.join(", ") : "无"}`,
    "",
    "## survived 清单（新扩散面机判定义——人工定性：真缺口补锚 / 等价突变白名单）",
    "",
    ...(results.flatMap((r) => r.survivedList).map((s) => "- " + s)),
  ];
  fs.writeFileSync(path.join(outAbs, "report.md"), md.join("\n") + "\n");
  fs.writeFileSync(
    path.join(outAbs, "results.json"),
    JSON.stringify({ agg, envRed, zeroTest, results }, null, 1),
  );
  process.stdout.write(
    `mutation_gate: ${results.length} 文件 / ${agg.total} 突变体——survived ${agg.survived}（report-only 不阻断）；报告 ${normalizeSlashes(path.relative(root, outAbs))}/report.md\n`,
  );
}

if (normalizeSlashes(process.argv[1] ?? "").endsWith("mutation_gate/main.mts")) {
  main();
}
