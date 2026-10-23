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

const CASES: { target: string; goDir: string; corpora: string[] }[] = [
  { target: "lexer", goDir: "lexer_diff", corpora: ["gap"] },
  { target: "typeck", goDir: "typeck_diff", corpora: ["gap"] },
  { target: "parser", goDir: "parser_diff", corpora: ["gap"] },
  { target: "codegen", goDir: "codegen_diff", corpora: ["gap"] },
];

let bad = 0;
for (const c of CASES) {
  for (const d of c.corpora) {
    const goLine = run("go", ["run", `./scripts/${c.goDir}`, `corpus/${d}`]);
    const tsLine = run("node", ["scripts/diff_gate/main.mts", c.target, `corpus/${d}`]);
    const g = parseReport(goLine);
    const t = parseReport(tsLine);
    const ok =
      g !== null && t !== null && g.verdict === t.verdict && g.matched === t.matched && g.fork === t.fork;
    if (!ok) {
      bad++;
      process.stdout.write(
        `PARITY-DIFF ${c.target}/${d}\n  go: ${goLine}\n  ts: ${tsLine}\n`,
      );
    } else {
      process.stdout.write(`PARITY-OK   ${c.target}/${d}（${g.verdict} matched=${g.matched} fork=${g.fork}）\n`);
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
