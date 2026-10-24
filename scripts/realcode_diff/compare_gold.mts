#!/usr/bin/env node
// realcode_diff/compare_gold —— 仓内语料批 gold 对账判红（TS 版，2026-10-24 接线批）。
//
// #273 纪律 8 形态：对账判据是功能结构变更（新增 CI 判红面）——新增代码
// 新语言（.mts 四件套），Go 工具（vitro_clang_diff.go -corpus）保持勘探
// 产出职责；CI 的 realcode_corpus 实例「Go 勘探 → TS 判红」分工，双轨期
// Go 版内嵌对账（corpusCompareWithGold）与本 TS 版双跑逐位对拍互证。
//
// 用法：
//   node scripts/realcode_diff/compare_gold.mts <corpus 名> <result.json 路径>
//   退出码：0=逐字段一致；1=漂移（已打印差异清单）；2=输入错误
//
// 对账面（与 Go 版 corpusCompareWithGold 逐位一致——双轨互证的契约）：
//   键集双向 + clang_ok / gcc_ok / vitro_errs / vitro_warns / layer / run /
//   码计数（vitro_diags 逐条累计 vs gold codes）。
import { readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";

interface Diag {
  code: string;
  severity: string;
}

interface FileResult {
  path: string;
  clang_ok: boolean;
  gcc_ok?: boolean;
  vitro_errors: number;
  vitro_warnings: number;
  vitro_layer?: string;
  run_compare?: string;
  vitro_diags?: Diag[];
}

interface GoldEntry {
  clang_ok: boolean;
  gcc_ok?: boolean;
  vitro_errs: number;
  vitro_warns: number;
  layer: string;
  run: string;
  codes: Record<string, number>;
}

interface Gold {
  files: Record<string, GoldEntry>;
}

interface CorporaReg {
  corpora: Record<string, { gold: string }>;
}

function fail(msg: string): never {
  console.error(`compare_gold: ${msg}`);
  process.exit(2);
}

function main(): number {
  const [, , name, resultPath] = process.argv;
  if (!name || !resultPath) {
    fail("用法: node scripts/realcode_diff/compare_gold.mts <corpus 名> <result.json 路径>");
  }
  // gold 位置：corpora.json 的 gold 字段单源，缺省 gold_<name>.json
  const dir = path.join("scripts", "realcode_diff");
  let goldFile = `gold_${name}.json`;
  try {
    const reg = JSON.parse(readFileSync(path.join(dir, "corpora.json"), "utf8")) as CorporaReg;
    const entry = reg.corpora[name];
    if (entry?.gold) goldFile = entry.gold;
  } catch {
    // 登记表缺失→缺省名（gold 必须在库，读失败即 fail）
  }
  const goldPath = path.join(dir, goldFile);
  let gold: Gold;
  let results: FileResult[];
  try {
    gold = JSON.parse(readFileSync(goldPath, "utf8")) as Gold;
  } catch (e) {
    fail(`金样本不可读 ${goldPath}（${String(e)}）——CI 形态下 gold 必须在库`);
  }
  try {
    results = JSON.parse(readFileSync(resultPath, "utf8")) as FileResult[];
  } catch (e) {
    fail(`result.json 不可读 ${resultPath}（${String(e)}）`);
  }

  const now = new Map<string, FileResult>();
  for (const r of results) now.set(r.path, r);

  const bad: string[] = [];
  const report = (rel: string, msg: string): void => {
    console.error(`  [漂移] ${rel}: ${msg}`);
    bad.push(rel);
  };

  for (const [rel, g] of Object.entries(gold.files)) {
    const r = now.get(rel);
    if (!r) {
      report(rel, "本轮结果缺失（语料被删或未跑）");
      continue;
    }
    if (r.clang_ok !== g.clang_ok) report(rel, `clang_ok ${g.clang_ok} → ${r.clang_ok}`);
    const gGcc = g.gcc_ok ?? false;
    const rGcc = r.gcc_ok ?? false;
    if (gGcc !== rGcc) report(rel, `gcc_ok ${gGcc} → ${rGcc}`);
    if (r.vitro_errors !== g.vitro_errs) report(rel, `vitro_errs ${g.vitro_errs} → ${r.vitro_errors}`);
    if (r.vitro_warnings !== g.vitro_warns) report(rel, `vitro_warnings ${g.vitro_warns} → ${r.vitro_warnings}`);
    const rLayer = r.vitro_layer ?? "";
    if (rLayer !== g.layer) report(rel, `layer "${g.layer}" → "${rLayer}"`);
    const rRun = r.run_compare ?? "";
    if (rRun !== g.run) report(rel, `run "${g.run}" → "${rRun}"`);
    const rc = new Map<string, number>();
    for (const d of r.vitro_diags ?? []) rc.set(d.code, (rc.get(d.code) ?? 0) + 1);
    const gcKeys = Object.keys(g.codes).sort();
    const rcKeys = [...rc.keys()].sort();
    if (gcKeys.length !== rcKeys.length || gcKeys.some((k, i) => k !== rcKeys[i])) {
      report(rel, `码集 ${JSON.stringify(g.codes)} → ${JSON.stringify(Object.fromEntries(rc))}`);
    } else {
      for (const [k, v] of Object.entries(g.codes)) {
        if ((rc.get(k) ?? 0) !== v) report(rel, `码 ${k} 计数 ${v} → ${rc.get(k) ?? 0}`);
      }
    }
  }
  for (const rel of now.keys()) {
    if (!(rel in gold.files)) report(rel, "gold 缺该条（新语料未冻结——重跑 -aggregate + 提交）");
  }

  if (bad.length > 0) {
    console.error(`realcode 对拍 FAIL：${bad.length} 处漂移（${goldPath} ↔ ${name}）`);
    return 1;
  }
  console.log(`realcode 对拍 OK：${Object.keys(gold.files).length} 条逐字段一致（${goldPath}）`);
  return 0;
}

process.exit(main());
