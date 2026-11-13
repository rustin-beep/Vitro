#!/usr/bin/env node
// prove_bucket —— moon prove proof.json infra/goal 分桶判定器（PR #509 审阅 P3-3 处置，2026-11-13）。
//
// 单源背景：why3server 起服期 prover 全灭时 moon prove 的 stdout 只有
// 「0 goals proved, N failure」（不含 no configured provers 等可 grep 形态），
// 分桶真值唯一在场 = _build/verif/<pkg>/<basename>.proof.json 的
// failures[].result（"(no prover available)" 形态；summary 含 valid/timeout/
// oom/failure 分桶）——moonbit/AGENTS.md 陷阱 46。pre-push 钩子原以 node -e
// 内联实现该判据（逃出 #273 四件套门，改正则无闸拦）——本文件抽出单源，
// 钩子只调用（diff_ledger --selftest 先例；J9 五形态负例在 main.test.mts）。
//
// 判定（保守 fail loud——读不到/空 failures/混合形态一律非 infra）：
//   failures 非空且全为 no-prover 形态 → infra 红（exit 0——对钩子即「不阻断」）
//   其余（含真 goal 红 / 混合 / failures 空 / 文件缺/坏 JSON）→ exit 1
//
// 用法：node scripts/prove_bucket/main.mts <proof.json 路径>
import fs from "node:fs";
import process from "node:process";

export interface ProofFailure {
  result?: string;
}

export interface ProofReport {
  failures?: ProofFailure[];
}

/** failures 非空且全为 no-prover 形态 → true（infra 红） */
export function isInfraOnly(report: ProofReport): boolean {
  const f = report.failures ?? [];
  return f.length > 0 && f.every((x) => /\(no prover available\)/.test(x.result ?? ""));
}

/** CLI 入口（可测）：argv = [路径]；返回进程退出码 */
export function main(argv: string[]): number {
  const target = argv[0];
  if (!target) {
    console.error("prove_bucket: 缺 proof.json 路径参数");
    return 1;
  }
  let report: ProofReport;
  try {
    report = JSON.parse(fs.readFileSync(target, "utf8")) as ProofReport;
  } catch (e) {
    console.error(`prove_bucket: 读文件/解析失败 ${target}（${e instanceof Error ? e.message : String(e)}）`);
    return 1;
  }
  return isInfraOnly(report) ? 0 : 1;
}

if (process.argv[1] !== undefined && import.meta.url === new URL(`file:///${process.argv[1].replaceAll("\\", "/")}`).href) {
  process.exit(main(process.argv.slice(2)));
}
