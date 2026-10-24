#!/usr/bin/env node
// single_source：单一真相源清单校验器（Go→.mts 重写，refs #273；原架构审阅 v2 A 组 #7 / C-04）。
//
// 用法（**仓库根**）：
//   node scripts/moonbit/single_source/main.mts            # 报告清单 + 判定
//   node scripts/moonbit/single_source/main.mts -check     # 判定（CI 门禁用）
//   node scripts/moonbit/single_source/main.mts --selftest # J9：注入第二份实现必红
//
// 为什么需要它（C-04 裁决要点）：项目 L1 判据「同一概念多真相来源」只覆盖**仓内
// 同语言重复**，**不覆盖跨语言孪生**——迁移期每个单源在 MoonBit 侧都有一份孪生，
// 同步义务纯人工（"照搬不私改"）。本闸把清单入版本控制并做机判，让「悄悄长出
// 第二份实现」变成红。
//
// 三类条目：
//   enforced   —— 全仓按 def_pattern 扫定义点，命中**文件集**必须等于
//                 allowed_def_files（多 = 第二份真相；少 = 单源被删/改名）；
//   registered —— 单源形态是生成物或另有专用闸门，只校验声明两侧路径存在；
//   copies     —— 「多副本逐字节一致」：copies_must_match 全路径存在且逐字节相同。
//
// 判定：任一条目失败即红；清单为空亦红（空集不得绿）。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

export const RULES_PATH = "scripts/moonbit/single_source/rules.json";

export interface Entry {
  id: string;
  concept: string;
  kind: string;
  def_pattern: string;
  exclude_line_pattern: string;
  allowed_def_files: string[];
  copies_must_match: string[];
  rust_source: string;
  moonbit_source: string;
  sync: string;
  consumers: string[];
  anchor: string;
  upstream_ref: string;
}

export interface RulesDoc {
  schema: number;
  search_roots: string[];
  search_exclude_dirs: string[];
  entries: Entry[];
}

export interface Result {
  e: Entry;
  ok: boolean;
  hits: string[];
  missing: string[];
  extra: string[];
  msg: string;
}

function fatal(msg: string): never {
  process.stderr.write(`single_source: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

/** POSIX 风格规范化（Go filepath.Clean + ToSlash）。 */
export function canon(p: string): string {
  return path.normalize(p).split(path.sep).join("/");
}

function orNone(s: string | undefined): string {
  // rules.json 里部分条目省略该字段（Go struct 零值 = ""）；undefined 不能当值打印
  return s === undefined || s === "" ? "(无——见 note)" : s;
}

/** 字节序排序（Go sort.Strings 口径）。 */
function byteSort(xs: string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

export function loadRules(p = RULES_PATH): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(p), "utf8");
  } catch (e) {
    fatal(`读清单失败（须在仓库根运行）: ${e instanceof Error ? e.message : String(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`清单解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (rd.schema !== 1) fatal(`清单 schema 不支持: ${rd.schema}（期望 1）`);
  if (!Array.isArray(rd.search_roots) || rd.search_roots.length === 0) fatal("清单缺 search_roots");
  return rd;
}

/**
 * scanDefs：在 search_roots 下按 pattern 逐行匹配**定义点**，返回命中的文件集
 * （相对 cwd、POSIX 风格）。跳过注释行（`//` `#` 开头）与 exclude_line_pattern；
 * 只扫 .rs / .mbt。
 */
export function scanDefs(rd: RulesDoc, pattern: string, excludeLine: string): string[] {
  let re: RegExp;
  try {
    re = new RegExp(pattern);
  } catch (e) {
    fatal(`def_pattern 非法 ${JSON.stringify(pattern)}: ${e instanceof Error ? e.message : String(e)}`);
  }
  let reExcl: RegExp | null = null;
  if (excludeLine !== "") {
    try {
      reExcl = new RegExp(excludeLine);
    } catch (e) {
      fatal(`exclude_line_pattern 非法 ${JSON.stringify(excludeLine)}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  const exclude = new Set(rd.search_exclude_dirs ?? []);
  const hits = new Set<string>();
  const walk = (dir: string): void => {
    // Go 的 Walk 对 root 自身也回调 IsDir 并检查 skip 集；这里必须同口径
    if (exclude.has(path.basename(dir))) return;
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(abs(dir), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1));
    } catch {
      return; // Go 版 Walk 的 err 分支也 return nil
    }
    for (const ent of ents) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (exclude.has(ent.name)) continue;
        walk(p);
        continue;
      }
      const ext = path.extname(ent.name);
      if (ext !== ".rs" && ext !== ".mbt") continue;
      let data: string;
      try {
        data = fs.readFileSync(abs(p), "utf8");
      } catch {
        continue;
      }
      for (const line of data.split("\n")) {
        const t = line.trim();
        if (t.startsWith("//") || t.startsWith("#")) continue;
        if (reExcl !== null && reExcl.test(line)) continue; // 方法形态（含 self），见 rules 的 _exclude_note
        if (re.test(line)) {
          // 相对基准用仓库根而非 cwd：Go 版 filepath.Rel(".", path) 隐含"从根跑"，
          // 迁到 TS 后调用方可能从 scripts/ 起跑（npm test），基准必须显式
          hits.add(canon(path.relative(projectRoot(), abs(p))));
          break;
        }
      }
    }
  };
  for (const root of rd.search_roots) walk(root);
  return byteSort([...hits]);
}

/** 单条目判定（report / selftest / 判定共用）。 */
export function judgeEntry(rd: RulesDoc, e: Entry): Result {
  const r: Result = { e, ok: true, hits: [], missing: [], extra: [], msg: "" };
  for (const p of [e.rust_source, e.moonbit_source]) {
    if (p === "") continue;
    if (!fs.existsSync(abs(p))) {
      r.ok = false;
      r.msg += `声明的源路径不存在: ${p}\n`;
    }
  }
  if (e.kind === "enforced") {
    if (e.def_pattern === "" || !Array.isArray(e.allowed_def_files) || e.allowed_def_files.length === 0) {
      r.ok = false;
      r.msg += "enforced 条目缺 def_pattern / allowed_def_files\n";
    } else {
      const hits = scanDefs(rd, e.def_pattern, e.exclude_line_pattern ?? "");
      r.hits = hits;
      const allow = new Set(e.allowed_def_files.map((f) => canon(f)));
      const hitSet = new Set(hits);
      r.extra = byteSort([...hitSet].filter((h) => !allow.has(h)));
      r.missing = byteSort([...allow].filter((a) => !hitSet.has(a)));
      if (r.extra.length > 0 || r.missing.length > 0) r.ok = false;
    }
  } else if (e.kind === "copies") {
    if (!Array.isArray(e.copies_must_match) || e.copies_must_match.length < 2) {
      r.ok = false;
      r.msg += "copies 条目须声明 ≥2 份路径（copies_must_match）\n";
    } else {
      let base: Buffer | null = null;
      let baseFile = "";
      for (const p of e.copies_must_match) {
        let b: Buffer;
        try {
          b = fs.readFileSync(abs(p));
        } catch (err) {
          r.ok = false;
          r.msg += `副本缺失: ${p} (${err instanceof Error ? err.message : String(err)})\n`;
          continue;
        }
        if (baseFile === "") {
          base = b;
          baseFile = p;
        } else if (base !== null && !base.equals(b)) {
          r.ok = false;
          r.msg += `副本漂移: ${p} 与 ${baseFile} 不一致（连坐改动须全量同步）\n`;
        }
      }
    }
  } else if (e.kind !== "registered") {
    r.ok = false;
    r.msg += `未知 kind: ${e.kind}\n`;
  }
  return r;
}

export function printEntry(r: Result): void {
  const mark = r.ok ? "OK " : "BAD";
  process.stdout.write(`  [${mark}][${r.e.kind}] ${r.e.id} — ${r.e.concept}\n`);
  process.stdout.write(`        rust  : ${orNone(r.e.rust_source)}\n`);
  process.stdout.write(`        moon  : ${orNone(r.e.moonbit_source)}\n`);
  process.stdout.write(`        sync  : ${r.e.sync}\n`);
  if (r.e.kind === "enforced") {
    process.stdout.write(`        定义点: ${r.hits.length} 处命中（allowed ${(r.e.allowed_def_files ?? []).length}）\n`);
  }
  process.stdout.write(`        anchor: ${r.e.anchor}\n`);
  if ((r.e.consumers ?? []).length > 0) {
    process.stdout.write(`        消费点: ${r.e.consumers.join(", ")}\n`);
  }
  if (r.e.upstream_ref !== undefined && r.e.upstream_ref !== "") {
    process.stdout.write(`        上游  : ${r.e.upstream_ref}\n`);
  }
  if (!r.ok) {
    if (r.msg !== "") process.stdout.write(`        !! ${r.msg}`);
    if (r.extra.length > 0) process.stdout.write(`        !! 多出第二份实现: ${r.extra.join(", ")}\n`);
    if (r.missing.length > 0) process.stdout.write(`        !! 单源缺失（声明有而实际无）: ${r.missing.join(", ")}\n`);
  }
}

/** J9：先确认基线绿（否则注入后的红无法归因），再注入虚构第二份实现，必须变红。 */
export function selftestRun(rd: RulesDoc, results: Result[]): number {
  if (results.some((r) => !r.ok)) {
    process.stdout.write("single_source: selftest ABORT——基线不绿，注入后的红无法归因\n");
    return 2;
  }
  const idx = results.findIndex((r) => r.e.kind === "enforced");
  if (idx < 0) {
    process.stdout.write("single_source: selftest ABORT——清单无 enforced 条目\n");
    return 2;
  }
  const e = results[idx]!.e;
  const fake = "moonbit/ast/__selftest_second_copy.mbt";
  const hitSet = new Set([fake, ...(results[idx]!.hits ?? [])]);
  const allow = new Set((e.allowed_def_files ?? []).map((f) => canon(f)));
  const extra = [...hitSet].filter((h) => !allow.has(h)).length;
  process.stdout.write(`single_source: selftest 已注入第二份实现 ${fake}（条目 ${e.id}）\n`);
  if (extra === 0) {
    process.stdout.write("single_source: selftest FAIL——注入的第二份实现未被判定为多出，闸门失效\n");
    return 1;
  }
  process.stdout.write("single_source: selftest PASS——注入的第二份实现被捕获（红），J9 证红成立\n");
  return 0;
}

export function main(argv: string[]): number {
  let check = false;
  let selftest = false;
  for (const a of argv) {
    if (a === "-check") check = true;
    else if (a === "--selftest" || a === "-selftest") selftest = true;
    else fatal(`未知参数: ${a}（可用：-check / --selftest）`);
  }
  const rd = loadRules();
  if (!Array.isArray(rd.entries) || rd.entries.length === 0) fatal("清单为空——空集不得绿");

  const results = rd.entries.map((e) => judgeEntry(rd, e));

  if (selftest) return selftestRun(rd, results);
  if (!check) {
    process.stdout.write("单一真相源清单（跨语言孪生层；判据 C-04 —— L1 只覆盖同语言重复）\n");
    for (const r of results) printEntry(r);
  }

  const bad = results.filter((r) => !r.ok).length;
  if (bad > 0) {
    if (check) for (const r of results) if (!r.ok) printEntry(r);
    process.stdout.write(`single_source: FAIL——${bad}/${results.length} 条单源未通过\n`);
    return 1;
  }
  process.stdout.write(`single_source: PASS——${results.length} 条单源清单全部成立（定义点唯一性 + 两侧路径在）\n`);
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
