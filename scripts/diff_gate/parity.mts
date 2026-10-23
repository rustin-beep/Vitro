#!/usr/bin/env node
// parity.mts —— 双轨对拍闸（#273 审阅 P2-2）。
//
// 问题：族 A 五 target 的 Go 版（CI 现役）与 .mts 版（scripts-ts 单测）长期并存，
// 而 .mts 侧单测只对自己产物 -check 自洽，**两版之间没有任何对账闸**——下一次
// 任一轨单独演进就静默分叉，切 CI 那天产物漂移无闸可拦。
//
// 口径：同一语料两侧各跑一次，比对「判定 + matched 数 + fork 数」三元组。
//   Go 自报行：PASS——N 指纹一致（fork 跳过 M[，VERIFY-RED=K]）
//   TS 自报行：PASS——N 个 case hash 与冻结基线一致（语料 X[，M 例 known-fork 跳过]）
// 两侧措辞本来就不同（TS 版重写过自报文案），故比语义三元组而非逐字节。
// 退出码：任一组合不符即 1。
import { spawnSync } from "node:child_process";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "../..");

/** 从自报末行提取 (verdict, matched, fork)。matched = PASS 后首个数字（两侧措辞不同）。 */
export function parseReport(line: string): { verdict: string; matched: number; fork: number } | null {
  const m = /PASS——(\d+)/.exec(line);
  if (m === null) return null;
  const fork = /fork 跳过 (\d+)/.exec(line) ?? /(\d+) 例 known-fork 跳过/.exec(line);
  return { verdict: line.includes("PASS") ? "PASS" : "FAIL", matched: Number(m[1]), fork: fork === null ? 0 : Number(fork[1]) };
}

/**
 * **异常行集合**（2026-10-24 强化）：提取所有「非 SAME」的 per-case 行的
 * (类型, case 名) 二元组并排序。
 *
 * 为什么必须比它：只比汇总三元组有致命盲区——Go 侧错 A 例、TS 侧错 B 例时
 * 两侧 matched/DIFF 计数相同，三元组却完全一致，parity 会说 OK（**假绿**）。
 * 比对异常集合能区分「错的是不是同一批用例」。
 *
 * 注：四家 golden 驱动全 PASS 时**不打印 per-case 行**（只给汇总），故此时
 * 只能靠三元组——但两侧都 PASS 意味着都精确复现同一份 golden_digest，等价性
 * 由冻结基线本身背书，不是弱证据。vm 则逐例打印，可全序列比对。
 */
export function anomalies(out: string): string[] {
  const rows: string[] = [];
  for (const raw of out.split("\n")) {
    const line = raw.trim();
    const m = /^(DIFF-KNOWN|DIFF|FORK\([^)]*\)|SKIP)\s+(\S+)/.exec(line);
    if (m !== null) rows.push(`${m[1]} ${caseName(m[2] ?? "")}`);
  }
  return rows.sort();
}

/** 取 case 名：截到首个冒号或破折号前（两侧 FORK/DIFF 行的 reason 文案不同，不能进比对）。 */
function caseName(s: string): string {
  return s.split(/[:：]|——/)[0] ?? s;
}

/** vm 的逐例序列（vm 每例都打印 SAME/DIFF）。 */
export function vmRows(out: string): string[] {
  const rows: string[] = [];
  for (const raw of out.split("\n")) {
    const line = raw.trim();
    const m = /^(SAME|DIFF-KNOWN|DIFF|SKIP)\s+(\S+)/.exec(line);
    if (m !== null) rows.push(`${m[1]} ${caseName(m[2] ?? "")}`);
  }
  return rows;
}

/** 跑一次，返回 { 自报末行, 完整输出 }（异常集合需要完整输出）。 */
function runFull(cmd: string, args: string[]): { self: string; full: string } {
  const r = spawnSync(cmd, args, { cwd: ROOT, encoding: "utf8", timeout: 900_000, maxBuffer: 64 * 1024 * 1024 });
  const out = (r.stdout ?? "") + (r.stderr ?? "");
  const lines = out.trim().split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i] ?? "";
    if (/PASS|FAIL|SAME=/.test(l)) return { self: l, full: out };
  }
  return { self: lines[lines.length - 1] ?? "", full: out };
}

function run(cmd: string, args: string[]): string {
  const r = spawnSync(cmd, args, { cwd: ROOT, encoding: "utf8", timeout: 900_000, maxBuffer: 64 * 1024 * 1024 });
  const out = (r.stdout ?? "") + (r.stderr ?? "");
  const lines = out.trim().split("\n");
  // 自报行含 PASS——/FAIL/SAME=；`[裁判切换]` 警示走 stderr，会混在输出尾部，
  // 故从后往前找第一条自报行（2026-10-23 实测：直接取末行会拿到警示）。
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i] ?? "";
    if (/PASS|FAIL|SAME=/.test(l)) return l;
  }
  return lines[lines.length - 1] ?? "";
}

// 2026-10-24：语料从 gap 扩到全五套——此前只覆盖 20/492 例（4%），
// 基线主体（baseline）与规模压力源（llm_scale）完全没被双轨比对。
const ALL_CORPORA = ["baseline", "knr", "leetcode", "gap", "llm_scale"];

const CASES: { target: string; goDir: string; corpora: string[] }[] = [
  { target: "lexer", goDir: "lexer_diff", corpora: ALL_CORPORA },
  { target: "typeck", goDir: "typeck_diff", corpora: ALL_CORPORA },
  { target: "parser", goDir: "parser_diff", corpora: ALL_CORPORA },
  { target: "codegen", goDir: "codegen_diff", corpora: ALL_CORPORA },
];

let bad = 0;
for (const c of CASES) {
  for (const d of c.corpora) {
    const goOut = runFull("go", ["run", `./scripts/${c.goDir}`, `corpus/${d}`]);
    const tsOut = runFull("node", ["scripts/diff_gate/main.mts", c.target, `corpus/${d}`]);
    const g = parseReport(goOut.self);
    const t = parseReport(tsOut.self);
    const summaryOK =
      g !== null && t !== null && g.verdict === t.verdict && g.matched === t.matched && g.fork === t.fork;
    // 异常集合比对：区分「两侧错的是不是同一批用例」（三元组做不到）
    const ga = anomalies(goOut.full);
    const ta = anomalies(tsOut.full);
    const anomaliesOK = ga.join("\n") === ta.join("\n");
    if (!summaryOK || !anomaliesOK) {
      bad++;
      const why = !summaryOK
        ? `汇总不符 go=${g === null ? "?" : `${g.verdict}/${g.matched}/${g.fork}`} ts=${t === null ? "?" : `${t.verdict}/${t.matched}/${t.fork}`}`
        : `异常集合不符（go ${ga.length} 条 / ts ${ta.length} 条）`;
      process.stdout.write(`PARITY-DIFF ${c.target}/${d}：${why}\n`);
      if (!anomaliesOK) {
        const onlyGo = ga.filter((x) => !ta.includes(x));
        const onlyTs = ta.filter((x) => !ga.includes(x));
        for (const x of onlyGo.slice(0, 5)) process.stdout.write(`    仅 go: ${x}\n`);
        for (const x of onlyTs.slice(0, 5)) process.stdout.write(`    仅 ts: ${x}\n`);
      }
    } else {
      process.stdout.write(
        `PARITY-OK   ${c.target}/${d}（${g?.verdict} matched=${g?.matched} fork=${g?.fork}，异常 ${ga.length} 条一致）\n`,
      );
    }
  }
}

// vm：自报形态是 SAME=/DIFF-KNOWN=/DIFF=/SKIP= 计数，单独比对
{
  const goLine = run("go", ["run", "./scripts/vm_diff", "--corpus", "gap"]);
  const tsLine = run("node", ["scripts/diff_gate/main.mts", "vm", "--corpus", "gap"]);
  const counts = (s: string): Record<string, number> => {
    const out: Record<string, number> = {};
    for (const m of s.matchAll(/(SAME|DIFF-KNOWN|DIFF|SKIP)=(\d+)/g)) out[m[1] ?? ""] = Number(m[2]);
    return out;
  };
  const g = counts(goLine);
  const t = counts(tsLine);
  const keys = ["SAME", "DIFF-KNOWN", "DIFF", "SKIP"];
  const ok = keys.every((k) => (g[k] ?? 0) === (t[k] ?? 0));
  if (!ok) {
    bad++;
    process.stdout.write(`PARITY-DIFF vm/gap\n  go: ${goLine}\n  ts: ${tsLine}\n`);
  } else {
    process.stdout.write(`PARITY-OK   vm/gap（SAME=${g.SAME ?? 0}）\n`);
  }
}

if (bad > 0) {
  process.stdout.write(`\nparity: FAIL——${bad} 组双轨不一致\n`);
  process.exit(1);
}
process.stdout.write("\nparity: PASS——双轨判定一致\n");
