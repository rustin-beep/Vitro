#!/usr/bin/env node
// perf_budget：性能假设预算闸（Go→.mts 重写，refs #273；原 2026-09-22 S5 收尾批）。
//
// 把「某项性能优化为什么不做」所依赖的**规模前提**变成可机判的红线：
// 每个 counter 的**单文件计数最大值**必须不超过其预算（按 corpus_dir 分档），
// 超阈即红并输出 on_exceed 指回裁决所在，迫使重估。
//
// 与 facts 的分工：facts 管「文档数字 ↔ 机器真值」一致性；本闸管「性能裁决的
// 规模前提是否仍成立」，是阈值断言。
//
// 规则外置 rules.json；0 语料文件即 fail loud（拒绝空转判绿）；--selftest 为 J9。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export const RULES_PATH = "scripts/perf_budget/rules.json";

export interface DirTier {
  dirs: string[];
  max_per_file: number;
}

export interface Counter {
  id: string;
  pattern: string;
  max_per_file: number;
  dir_tiers: DirTier[];
}

export interface Metric {
  id: string;
  concept: string;
  as_of: string;
  decision_ref: string;
  counters: Counter[];
  on_exceed: string;
}

export interface RulesDoc {
  schema: number;
  corpus_root: string;
  corpus_dirs: string[];
  file_ext: string;
  metrics: Metric[];
}

export interface Finding {
  metric: string;
  counter: string;
  /** 档位标签（"" = 顶层默认档；否则 corpus_dir 名） */
  tier: string;
  maxCount: number;
  maxFile: string;
  limit: number;
  exceed: boolean;
}

function fatal(msg: string): never {
  process.stderr.write(`FATAL: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

/** 粗去块注释与行注释（统计语料规模量级，粗粒度足够；两侧口径一致即可复现）。 */
export function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
}

/** 语料目录下全部目标扩展名文件的仓库根相对路径（正斜杠，排序）。 */
export function collectFiles(root: string, rd: RulesDoc): string[] {
  const ext = rd.file_ext === "" || rd.file_ext === undefined ? ".c" : rd.file_ext;
  const out: string[] = [];
  for (const d of rd.corpus_dirs) {
    const base = path.join(root, rd.corpus_root, d);
    let st: fs.Stats;
    try {
      st = fs.statSync(abs(base));
    } catch (e) {
      fatal(`语料目录不存在: ${base} (${e instanceof Error ? e.message : String(e)})`);
    }
    if (!st.isDirectory()) fatal(`语料目录不存在: ${base} (not a directory)`);
    const walk = (dir: string): void => {
      for (const ent of fs.readdirSync(abs(dir), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
        const p = `${dir}/${ent.name}`;
        if (ent.isDirectory()) {
          walk(p);
          continue;
        }
        if (!ent.name.endsWith(ext)) continue;
        out.push(path.relative(root, abs(p)).split(path.sep).join("/"));
      }
    };
    walk(base);
  }
  const sorted = [...out].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
  if (sorted.length === 0) fatal(`0 个 ${ext} 语料文件（corpus_root/corpus_dirs/file_ext 配置有误），拒绝判绿`);
  return sorted;
}

/** 文件所属档位（counter 的 dir_tiers 首个前缀命中；无命中顶层档）。 */
export function tierOf(c: Counter, f: string): { tier: DirTier; label: string } {
  for (const t of c.dir_tiers ?? []) {
    for (const d of t.dirs) {
      if (f.startsWith(`corpus/${d}/`)) return { tier: t, label: d };
    }
  }
  return { tier: { dirs: [], max_per_file: c.max_per_file }, label: "" };
}

/** 档位目录存在性守卫（P3-2：档位目录名写错会静默落顶层档 → 配置空转而闸绿）。 */
export function validateDirTiers(rd: RulesDoc): void {
  const seen = new Set<string>();
  for (const m of rd.metrics) {
    for (const c of m.counters) {
      for (const t of c.dir_tiers ?? []) {
        for (const d of t.dirs) {
          if (seen.has(d)) continue;
          seen.add(d);
          if (!fs.existsSync(abs(`corpus/${d}`))) {
            fatal(`dir_tiers 档位目录 corpus/${d} 不存在（配置空转：文件将静默落顶层档）`);
          }
        }
      }
    }
  }
}

export function scan(root: string, rd: RulesDoc): { findings: Finding[]; files: number } {
  const files = collectFiles(root, rd);
  const out: Finding[] = [];
  for (const m of rd.metrics) {
    if (m.counters.length === 0) fatal(`metric ${JSON.stringify(m.id)} 无 counters——拒绝空转`);
    for (const c of m.counters) {
      let re: RegExp;
      try {
        re = new RegExp(c.pattern, "g");
      } catch (e) {
        fatal(`counter ${JSON.stringify(c.id)} 的 pattern 非法: ${e instanceof Error ? e.message : String(e)}`);
      }
      /** 分档聚合：档位 → (maxN, maxF)；每档一条 finding（#236） */
      const byTier = new Map<string, { n: number; f: string }>();
      const tierLimit = new Map<string, number>();
      for (const f of files) {
        let body: string;
        try {
          body = fs.readFileSync(abs(path.join(root, f)), "utf8");
        } catch (e) {
          fatal(`读语料 ${f} 失败: ${e instanceof Error ? e.message : String(e)}`);
        }
        const n = [...stripComments(body).matchAll(re)].length;
        const { tier, label } = tierOf(c, f);
        const key = label === "" ? "(default)" : label;
        const cur = byTier.get(key);
        if (cur === undefined || n > cur.n) byTier.set(key, { n, f });
        tierLimit.set(key, tier.max_per_file);
      }
      // 输出序稳定：default 档在前，其余按名
      const rest = [...byTier.keys()].filter((k) => k !== "(default)").sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
      const keys = byTier.has("(default)") ? ["(default)", ...rest] : rest;
      for (const k of keys) {
        const a = byTier.get(k)!;
        const limit = tierLimit.get(k)!;
        out.push({
          metric: m.id,
          counter: c.id,
          tier: k === "(default)" ? "" : k,
          maxCount: a.n,
          maxFile: a.f,
          limit,
          exceed: a.n > limit,
        });
      }
    }
  }
  return { findings: out, files: files.length };
}

export function report(rd: RulesDoc, findings: Finding[], nFiles: number): void {
  process.stdout.write(`perf_budget: 语料 ${nFiles} 个 ${rd.file_ext} 文件（${rd.corpus_root}/${rd.corpus_dirs.join("+")}）\n`);
  for (const m of rd.metrics) {
    process.stdout.write(`  [${m.id}] ${m.concept}\n`);
    process.stdout.write(`    基准（${m.as_of}）| 裁决见 ${m.decision_ref}\n`);
  }
  for (const f of findings) {
    const mark = f.exceed ? "OVER" : "ok  ";
    process.stdout.write(
      `  ${mark} ${f.counter.padEnd(26)} [tier ${f.tier.padEnd(9)}] max=${String(f.maxCount).padEnd(6)} limit=${String(f.limit).padEnd(6)} @ ${f.maxFile}\n`,
    );
  }
}

/** J9：把全部 counter 预算压到 0（任何 >0 计数即超），断言必红；finally 恢复规则文件。 */
export function selftest(root: string, rd: RulesDoc): number {
  const absRules = abs(path.join(root, RULES_PATH));
  let orig: string;
  try {
    orig = fs.readFileSync(absRules, "utf8");
  } catch (e) {
    process.stdout.write(`perf_budget: selftest ABORT——读规则失败: ${e instanceof Error ? e.message : String(e)}\n`);
    return 2;
  }
  let restored = false;
  const restore = (): void => {
    if (restored) return;
    try {
      fs.writeFileSync(absRules, orig, "utf8");
    } catch (e) {
      process.stdout.write(`perf_budget: selftest 严重——恢复 rules.json 失败: ${e instanceof Error ? e.message : String(e)}\n`);
    }
    restored = true;
  };
  const inj: RulesDoc = {
    ...rd,
    metrics: rd.metrics.map((m) => ({
      ...m,
      counters: m.counters.map((c) => ({ ...c, max_per_file: 0 })),
    })),
  };
  try {
    fs.writeFileSync(absRules, JSON.stringify(inj, null, 2), "utf8");
    process.stdout.write("perf_budget: selftest 已把全部 counter 预算压到 0\n");
    const { findings } = scan(root, inj);
    const over = findings.filter((f) => f.exceed).length;
    restore();
    if (over === 0) {
      process.stdout.write("perf_budget: selftest FAIL——预算压到 0 后仍无 counter 超阈，闸门失效\n");
      return 1;
    }
    process.stdout.write(`perf_budget: selftest PASS——${over}/${findings.length} 个 counter 超阈被判红，J9 证红成立\n`);
    return 0;
  } finally {
    restore();
  }
}

export function loadRules(root: string): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(path.join(root, RULES_PATH)), "utf8");
  } catch (e) {
    fatal(`读规则失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`解析规则失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  return rd;
}

export function main(argv: string[]): number {
  let selftestMode = false;
  for (const a of argv) {
    if (a === "-check" || a === "--check") continue; // 与兄弟闸门调用形态一致，无独立语义
    if (a === "-selftest" || a === "--selftest") selftestMode = true;
    else {
      process.stderr.write(`perf_budget: 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  const root = projectRoot();
  const rd = loadRules(root);
  validateDirTiers(rd);
  if (rd.corpus_root === "" || rd.corpus_dirs.length === 0 || rd.metrics.length === 0) {
    fatal("规则缺 corpus_root / corpus_dirs / metrics");
  }
  if (selftestMode) return selftest(root, rd);

  const { findings, files } = scan(root, rd);
  report(rd, findings, files);
  const over = findings.filter((f) => f.exceed);
  if (over.length === 0) {
    process.stdout.write("perf_budget: PASS——全部性能假设的规模前提仍在预算内\n");
    return 0;
  }
  process.stdout.write("\n");
  for (const f of over) {
    for (const m of rd.metrics) {
      if (m.id === f.metric) {
        process.stdout.write(`perf_budget: ${f.counter} 超阈（${f.maxCount} > ${f.limit}，@ ${f.maxFile}）\n`);
        process.stdout.write(`  ⇒ ${m.on_exceed}\n`);
      }
    }
  }
  process.stdout.write("perf_budget: FAIL——性能裁决的规模前提已失效\n");
  return 1;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
