#!/usr/bin/env node
// realcode_diff/compare_gold —— 仓内语料批 gold 对账判红（TS 版）。
//
// #273 迁移批（2026-10-25）：原 Go 勘探器（vitro_clang_diff.go）已迁至
// main.mts 并删除 Go 版；本文件是**对账单源**——CI 的 realcode_corpus 实例
// 独立调用，main.mts 的 -corpus 内嵌对账 `compareWithGold` 亦复用本模块。
//
// 用法：
//   node scripts/realcode_diff/compare_gold.mts <corpus 名> <result.json 路径>
//   退出码：0=逐字段一致；1=漂移（已打印差异清单）；2=输入错误
//
// 对账面：
//   键集双向 + clang_ok / gcc_ok / vitro_errs / vitro_warns / layer / run /
//   码计数（vitro_diags 逐条累计 vs gold codes）。
import { readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

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

export interface CompareOptions {
  /** gold/corpora.json 所在目录；缺省 `scripts/realcode_diff`（仓库根相对）。 */
  dir?: string;
  /** 汇总行通道；勘探内嵌对账走 stderr（与 Go corpusCompareWithGold 同通道）。 */
  summary?: "stdout" | "stderr";
}

/** 本轮 []FileResult ↔ 在库 gold 逐字段对账。返回 0=一致；1=漂移（已打印差异清单）。 */
export function compareWithGold(
  name: string,
  results: FileResult[],
  opts: CompareOptions = {},
): number {
  const dir = opts.dir ?? path.join("scripts", "realcode_diff");
  const summary = opts.summary === "stderr" ? console.error : console.log;
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
  try {
    gold = JSON.parse(readFileSync(goldPath, "utf8")) as Gold;
  } catch (e) {
    fail(`金样本不可读 ${goldPath}（${String(e)}）——CI 形态下 gold 必须在库`);
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
    // 仓内语料 run 当前恒空（见 README.corpus「已知覆盖缺口」）；外置
    // gold_signatures 仍有真实 run 值，保留该比对面。
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
  summary(`realcode 对拍 OK：${Object.keys(gold.files).length} 条逐字段一致（${goldPath}）`);
  return 0;
}

function main(): number {
  const [, , name, resultPath] = process.argv;
  if (!name || !resultPath) {
    fail("用法: node scripts/realcode_diff/compare_gold.mts <corpus 名> <result.json 路径>");
  }
  let results: FileResult[];
  try {
    results = JSON.parse(readFileSync(resultPath, "utf8")) as FileResult[];
  } catch (e) {
    fail(`result.json 不可读 ${resultPath}（${String(e)}）`);
  }
  return compareWithGold(name, results);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main());
}
