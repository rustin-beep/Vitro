#!/usr/bin/env node
// coverage_snapshot —— MoonBit 行覆盖率逐包快照基线 + 趋势报告（审阅 v2 A8 批，refs #438；
// R5g 试点工具正式化——工具链内嵌 moon_cove，零外部依赖）。
//
// 用法（仓库根）：
//   node scripts/coverage_snapshot/main.mts                    # 采集 → 逐包聚合 → 对比基线 → 趋势报告（**不判红**）
//   node scripts/coverage_snapshot/main.mts --update-baseline  # 显式重锚 baseline.json（防静默漂移：默认只读基线）
//   node scripts/coverage_snapshot/main.mts --from <file>      # 跳过采集，用现成 full_summary 文本（CI 分步 / 单测 / 对账）
//   node scripts/coverage_snapshot/main.mts --out <dir>        # 报告落盘目录（默认 tmp/coverage_snapshot，gitignored）
//
// 定位（#438 拍板「快照基线」语义）：B 轮修复进行中，本工具只采**首采基线 + 逐包趋势**，
// 不设涨跌门——门限留后续批（coverage 差分亦是 #368 突变闸第三层的验收向量前科）。
// rc=0 恒成立，除非 fail loud 形态：采集失败 / 解析不到 Total / 逐文件之和与 Total 不闭合 /
// 基线损坏（rc=2 环境面）。
//
// 口径（R5g §1.6 三陷阱，正式接入前必读）：
//   ① 逐文件/逐包聚合**必须用 `-f full_summary`**——`summary` 只列未满 100% 的文件（Total 行却含
//      全部），用它聚合会系统性低估（R5g 回算 59.2% vs 真 60.1%）；本工具断言「逐文件之和 == Total」
//      作闭合校验，口径走错当场红。
//   ② summary 族走 stdout（`-o` 只对 cobertura/html/bisect 生效），须进程内捕获。
//   ③ cobertura.xml 行级口径与 summary 族不一致（剔除部分行），两族数字不可混用——本工具只用 summary 族。
//   覆盖域 = 默认 wasm 轮裸单测（native-only 包 gateway/cli 的用例不在内），与 facts 键
//   moonbit_coverage_uncovered_lines 同口径（该键 = Total 的 total−covered，本工具不改其采集链）。
//
// 基线（scripts/coverage_snapshot/baseline.json，入库）：键序显式构造（纪律 8 字节确定性）——
//   { schema, as_of, commit, total:{covered,total}, packages:{<pkg>:{covered,total}} }，pkg 字节序。
//   首采 2026-11-02（origin/master 5233ad65）：18480/30648 = 60.3%（R5g 基准 dbc62b6e 为 18427/30648
//   = 60.1%，差 53 行 = 其后几批测试增量）。
//
// 产物（--out 目录，CI 存 artifact；GITHUB_STEP_SUMMARY 在场时趋势表追加其后）：
//   full_summary.txt（CRLF 归一原文）/ per_package.json（本次逐包）/ trend.md（vs 基线）。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export const BASELINE_PATH = "scripts/coverage_snapshot/baseline.json";
export const DEFAULT_OUT = "tmp/coverage_snapshot";

export interface Ratio {
  covered: number;
  total: number;
}

export interface Snapshot {
  /** posix 相对路径（moonbit/ 下）→ 行覆盖 */
  files: Map<string, Ratio>;
  total: Ratio;
}

export interface Baseline {
  schema: 1;
  as_of: string;
  commit: string;
  total: Ratio;
  packages: Record<string, Ratio>;
}

function fatal(msg: string): never {
  process.stderr.write(`coverage_snapshot: ${msg}\n`);
  process.exit(2);
}

function byteSort(xs: string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

export function pct(r: Ratio): string {
  return r.total === 0 ? "n/a" : `${((100 * r.covered) / r.total).toFixed(1)}%`;
}

const RE_LINE = /^(.+?):\s*(\d+)\/(\d+)\s*$/;

/**
 * 解析 `moon coverage report -f full_summary` 文本：逐行 `path: covered/total`，末行 `Total: covered/total`。
 * 路径 `\` 归一为 `/`（Windows 产出，纪律 9 的 [/\] 双兼容）。
 * fail loud：无 Total 行 / 逐文件之和与 Total 不闭合（= 用错了 summary 口径或上游格式变了）→ throw。
 */
export function parseFullSummary(text: string): Snapshot {
  const files = new Map<string, Ratio>();
  let total: Ratio | null = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line === "") continue;
    const m = RE_LINE.exec(line);
    if (m === null) continue; // 非数据行（moon 的进度/警告输出）一律忽略
    const key = m[1]!.trim();
    const r: Ratio = { covered: Number.parseInt(m[2]!, 10), total: Number.parseInt(m[3]!, 10) };
    if (key === "Total") {
      total = r;
      continue;
    }
    const posix = key.replace(/\\/g, "/");
    if (files.has(posix)) throw new Error(`full_summary 重复文件行：${posix}`);
    files.set(posix, r);
  }
  if (total === null) throw new Error("full_summary 无 Total: covered/total 行——报告格式变化或采集失败");
  let sc = 0;
  let st = 0;
  for (const r of files.values()) {
    sc += r.covered;
    st += r.total;
  }
  if (sc !== total.covered || st !== total.total) {
    throw new Error(
      `逐文件之和 ${sc}/${st} 与 Total ${total.covered}/${total.total} 不闭合——须用 -f full_summary（summary 只列未满 100% 文件，聚合会低估）`,
    );
  }
  return { files, total };
}

/** 文件 → 所在目录作为包名（`fs/fs.mbt` → `fs`；`lexer/internal/pp/x.mbt` → `lexer/internal/pp`）。 */
export function packageOf(file: string): string {
  const i = file.lastIndexOf("/");
  return i < 0 ? "(root)" : file.slice(0, i);
}

export function aggregateByPackage(snap: Snapshot): Record<string, Ratio> {
  const acc = new Map<string, Ratio>();
  for (const [f, r] of snap.files) {
    const p = packageOf(f);
    const cur = acc.get(p) ?? { covered: 0, total: 0 };
    cur.covered += r.covered;
    cur.total += r.total;
    acc.set(p, cur);
  }
  const out: Record<string, Ratio> = {};
  for (const k of byteSort([...acc.keys()])) out[k] = acc.get(k)!;
  return out;
}

/** 基线序列化：键序显式、逐包字节序、2 空格缩进 + 末行换行（字节确定性）。 */
export function serializeBaseline(b: Baseline): string {
  const pk: Record<string, Ratio> = {};
  for (const k of byteSort(Object.keys(b.packages))) {
    const r = b.packages[k]!;
    pk[k] = { covered: r.covered, total: r.total };
  }
  const ordered = {
    schema: b.schema,
    as_of: b.as_of,
    commit: b.commit,
    total: { covered: b.total.covered, total: b.total.total },
    packages: pk,
  };
  return JSON.stringify(ordered, null, 2) + "\n";
}

export function parseBaseline(text: string): Baseline {
  let j: unknown;
  try {
    j = JSON.parse(text);
  } catch (e) {
    throw new Error(`baseline.json 非法 JSON：${e instanceof Error ? e.message : String(e)}`);
  }
  const o = j as Partial<Baseline>;
  if (o.schema !== 1) throw new Error(`baseline.json schema 不支持：${String(o.schema)}（期望 1）`);
  if (typeof o.as_of !== "string" || typeof o.commit !== "string") throw new Error("baseline.json 缺 as_of/commit");
  if (!o.total || typeof o.total.covered !== "number" || typeof o.total.total !== "number") throw new Error("baseline.json 缺 total");
  if (!o.packages || typeof o.packages !== "object") throw new Error("baseline.json 缺 packages");
  return { schema: 1, as_of: o.as_of, commit: o.commit, total: o.total, packages: o.packages };
}

export interface TrendRow {
  pkg: string;
  base: Ratio | null;
  now: Ratio | null;
  /** 覆盖行数差（now.covered − base.covered）；任一侧缺席为 null */
  dCovered: number | null;
  /** 百分点差 */
  dPct: number | null;
}

export function trend(base: Baseline, nowPkgs: Record<string, Ratio>, nowTotal: Ratio): { rows: TrendRow[]; total: TrendRow } {
  const keys = byteSort([...new Set([...Object.keys(base.packages), ...Object.keys(nowPkgs)])]);
  const mk = (pkg: string, b: Ratio | null, n: Ratio | null): TrendRow => {
    const pctOf = (r: Ratio): number => (r.total === 0 ? 0 : (100 * r.covered) / r.total);
    return {
      pkg,
      base: b,
      now: n,
      dCovered: b && n ? n.covered - b.covered : null,
      dPct: b && n ? pctOf(n) - pctOf(b) : null,
    };
  };
  const rows = keys.map((k) => mk(k, base.packages[k] ?? null, nowPkgs[k] ?? null));
  return { rows, total: mk("TOTAL", base.total, nowTotal) };
}

export function renderTrend(base: Baseline, t: { rows: TrendRow[]; total: TrendRow }, commit: string): string {
  const fmt = (r: Ratio | null): string => (r === null ? "—" : `${r.covered}/${r.total} (${pct(r)})`);
  const d = (row: TrendRow): string => {
    if (row.dCovered === null || row.dPct === null) return row.base === null ? "**新增包**" : "**包消失**";
    const sgn = row.dCovered > 0 ? "+" : "";
    const psgn = row.dPct > 0 ? "+" : "";
    return `${sgn}${row.dCovered} 行 / ${psgn}${row.dPct.toFixed(1)} pt`;
  };
  const lines: string[] = [];
  lines.push(`## MoonBit 行覆盖率趋势（快照基线语义，不判红）`);
  lines.push("");
  lines.push(`- 基线：${base.as_of} @ ${base.commit} → ${fmt(base.total)}`);
  lines.push(`- 本次：@ ${commit} → ${fmt(t.total.now)}　**Δ ${d(t.total)}**`);
  lines.push(`- 口径：\`moon coverage report -f full_summary\` 逐文件闭合聚合；默认 wasm 轮裸单测域（gateway/cli native-only 用例不在内）`);
  lines.push("");
  lines.push("| 包 | 基线 | 本次 | Δ |");
  lines.push("|---|---|---|---|");
  // 变动行在前（按 |dPct| 降序），零变动在后字节序——读者先看到动了什么
  const moved = t.rows.filter((r) => r.dCovered !== 0 || r.dPct === null);
  const still = t.rows.filter((r) => r.dCovered === 0 && r.dPct !== null);
  moved.sort((a, b) => Math.abs(b.dPct ?? 999) - Math.abs(a.dPct ?? 999) || Buffer.compare(Buffer.from(a.pkg), Buffer.from(b.pkg)));
  for (const r of [...moved, ...still]) lines.push(`| ${r.pkg} | ${fmt(r.base)} | ${fmt(r.now)} | ${d(r)} |`);
  lines.push("");
  lines.push(`_变动 ${moved.length} 包 / 持平 ${still.length} 包。重锚基线：\`node scripts/coverage_snapshot/main.mts --update-baseline\`（显式动作，diff 即评审物）。_`);
  lines.push("");
  return lines.join("\n");
}

function run(cwd: string, cmd: string, args: readonly string[], timeoutMs: number): { code: number; out: string } {
  const r = spawnSync(cmd, args, { cwd, encoding: "utf8", shell: process.platform === "win32", timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 });
  if (r.error) return { code: -1, out: `${r.error.message}\n${r.stdout ?? ""}${r.stderr ?? ""}` };
  return { code: r.status ?? -1, out: `${r.stdout ?? ""}${r.stderr ?? ""}` };
}

/** 采集：插桩全量裸单测 + full_summary 报告（冷态分钟级——与 R5g 实测同链）。 */
export function collect(root: string): string {
  const moonbit = path.join(root, "moonbit");
  const t = run(moonbit, "moon", ["test", "--enable-coverage"], 30 * 60_000);
  if (t.code !== 0) fatal(`moon test --enable-coverage rc=${t.code}：\n${t.out.slice(-2000)}`);
  const r = run(moonbit, "moon", ["coverage", "report", "-f", "full_summary"], 5 * 60_000);
  if (r.code !== 0) fatal(`moon coverage report -f full_summary rc=${r.code}：\n${r.out.slice(-2000)}`);
  return r.out.replace(/\r/g, "");
}

function gitHead(root: string): string {
  const r = run(root, "git", ["rev-parse", "--short=8", "HEAD"], 10_000);
  return r.code === 0 ? r.out.trim() : "unknown";
}

export function main(argv: string[]): number {
  let update = false;
  let from: string | null = null;
  let out = DEFAULT_OUT;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--update-baseline") update = true;
    else if (a === "--from") from = argv[++i] ?? fatal("--from 缺参数");
    else if (a === "--out") out = argv[++i] ?? fatal("--out 缺参数");
    else fatal(`未知参数: ${a}（可用：--update-baseline / --from <file> / --out <dir>）`);
  }
  const root = projectRoot();
  const text = from !== null ? fs.readFileSync(path.isAbsolute(from) ? from : path.join(root, from), "utf8").replace(/\r/g, "") : collect(root);
  let snap: Snapshot;
  try {
    snap = parseFullSummary(text);
  } catch (e) {
    fatal(e instanceof Error ? e.message : String(e));
  }
  const pkgs = aggregateByPackage(snap);
  const commit = gitHead(root);
  const outDir = path.isAbsolute(out) ? out : path.join(root, out);
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, "full_summary.txt"), text);
  fs.writeFileSync(path.join(outDir, "per_package.json"), serializeBaseline({ schema: 1, as_of: new Date().toISOString().slice(0, 10), commit, total: snap.total, packages: pkgs }));

  const basePath = path.join(root, BASELINE_PATH);
  const baseExists = fs.existsSync(basePath);
  if (update || !baseExists) {
    const b: Baseline = { schema: 1, as_of: new Date().toISOString().slice(0, 10), commit, total: snap.total, packages: pkgs };
    fs.writeFileSync(basePath, serializeBaseline(b));
    process.stdout.write(`coverage_snapshot: ${baseExists ? "基线已重锚" : "首采基线已写入"} ${BASELINE_PATH} —— ${snap.total.covered}/${snap.total.total} (${pct(snap.total)})，${Object.keys(pkgs).length} 包 / ${snap.files.size} 文件\n`);
    if (!baseExists) process.stdout.write("coverage_snapshot: 首采无趋势可比；下次运行起输出 vs 基线趋势\n");
    return 0;
  }
  let base: Baseline;
  try {
    base = parseBaseline(fs.readFileSync(basePath, "utf8"));
  } catch (e) {
    fatal(e instanceof Error ? e.message : String(e));
  }
  const t = trend(base, pkgs, snap.total);
  const md = renderTrend(base, t, commit);
  fs.writeFileSync(path.join(outDir, "trend.md"), md);
  process.stdout.write(md);
  const stepSummary = process.env["GITHUB_STEP_SUMMARY"];
  if (stepSummary !== undefined && stepSummary !== "") fs.appendFileSync(stepSummary, md);
  process.stdout.write(`coverage_snapshot: 报告落盘 ${out}/{full_summary.txt,per_package.json,trend.md}（不判红，rc=0）\n`);
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
