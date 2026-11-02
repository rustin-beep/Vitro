#!/usr/bin/env node
// rust_narrative_check —— Rust 叙事闸（审阅 v2 批 A7'，R1b §⑥ 口径固化；PR #431 审阅处置扩面）。
//
// 问题本质：Rust 对照区 2026-10-05 工序④物理删除后，moonbit/ 源码注释里仍遍布
// 「照搬源：native/src/*.rs」死路径（A 类）、「与 Rust 一致/同构」失实背书（B 类）、
// 「照搬不修/在案/同病」僵尸义务（D 类）。#47 批五三件套（历史出处 + tag 可回溯 +
// 自主基线）此前是手工口径，CI 零拦截——新批次随时再引入。本闸把三件套机判化：
//   R1（死引用）     native/(src|crates|tests)|crates/vitro_|vitro_xxx/src/ 路径形态，
//                    ±window 行注释段内无档案 tag → 红；
//   R1b（蓝本文件引用）裸 `*.rs` 文件名/行号引用（排真文件 snapshot.rs）——量大且
//                    带算法来源技术价值：**文件头 file_head_lines 行内一次 tag 声明即
//                    整文件过闸**（PR #431 审阅 P2-1 处方 A），否则 ±window 同 R1；
//   R2（照搬不修活体）照搬不修|照搬在案|oracle 同病，无 tag 且窗口无 已修|销案|
//                    已翻转|已废弃|~~ 留痕 → 红；
//   R3（对齐声明）   与 Rust(侧)? (一致|同构|…)、Rust 侧(同构|…)、及 12 字内非紧邻
//                    `Rust…(同构|一致|对齐|逐字节)`，无 tag 且窗口无 历史|曾|旧|蓝本|
//                    语言 限定词 → 红（「Rust 语言」= 对语言语义的活引用，非 oracle 叙事）；
//   R4（照搬来源叙事）照搬 ?Rust 符号级来源陈述——三件套缺 tag：同 R1b 文件头形态。
// 规则外置 rules.json；存量过闸 exemptions.json（reason 必填）与命中集三向对账：
//   漏登记（命中未登记）红 / 僵尸例外（登记项不再命中）红 / 例外缺 reason 红。
// 扫描面：.mbt 只看不在字符串字面量内的首个 `//` 之后（多行字符串 `#|`/`$|` 行跳过）；
// .mbt.md 整行叙事；**@generated 文件照扫**（PR #431 审阅 P2-2：跳过=对再生源结构性
// 失明；命中即改生成器模板再生，禁手改——输出带〔@generated〕标记）。
//
// 用法（仓库根）：
//   node scripts/rust_narrative_check/main.mts            # 扫描并列出命中
//   node scripts/rust_narrative_check/main.mts -check     # 同上（本闸只读无写模式，
//                                                         #  -check 是与兄弟闸形态一致的别名）
//   node scripts/rust_narrative_check/main.mts --json     # 机器可读（命中/过闸/僵尸）
// 退出码：0 零命中且例外表无僵尸 / 1 任一向红 / 2 环境错（规则表坏/仓库根找不到）。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export interface Rule {
  id: string;
  name: string;
  pattern: string;
  exempt_words: string[];
  file_head_tag_exempt?: boolean;
  hint: string;
}

export interface Rules {
  scan_roots: string[];
  extensions: string[];
  prune_dirs: string[];
  generated_marker: string;
  generated_marker_head_lines: number;
  tag_markers: string[];
  window: number;
  file_head_lines: number;
  rules: Rule[];
}

export interface Exemption {
  file: string;
  rule: string;
  line_text: string;
  reason: string;
}

export interface Hit {
  file: string;
  line: number;
  rule: string;
  text: string;
  exempted: boolean;
  generated: boolean;
}

export interface ScanResult {
  files: number;
  generatedScanned: number;
  hits: Hit[];
  zombies: Exemption[];
}

function toSlash(p: string): string {
  return p.split(path.sep).join("/");
}

function fatal(msg: string): never {
  process.stderr.write("rust_narrative_check: " + msg + "\n");
  process.exit(2);
}

/** .mbt 注释段起点：首个不在字符串字面量内的 `//`；无则 -1。多行字符串 `#|`/`$|` 行视为非注释。 */
export function commentStart(line: string): number {
  const t = line.trimStart();
  if (t.startsWith("#|") || t.startsWith("$|")) return -1;
  let inStr = false;
  let inChar = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inStr) {
      if (c === "\\") {
        i++;
        continue;
      }
      if (c === '"') inStr = false;
      continue;
    }
    if (inChar) {
      if (c === "\\") {
        i++;
        continue;
      }
      if (c === "'") inChar = false;
      continue;
    }
    if (c === '"') {
      inStr = true;
      continue;
    }
    if (c === "'") {
      inChar = true;
      continue;
    }
    if (c === "/" && line[i + 1] === "/") return i;
  }
  return -1;
}

/** 文件每行的「叙事段」：.mbt.md 整行；.mbt 取注释段（无注释为空串）。 */
export function narrativeLines(filePath: string, body: string): string[] {
  const lines = body.split(/\r?\n/);
  if (filePath.endsWith(".mbt.md")) return lines;
  return lines.map((l) => {
    const s = commentStart(l);
    return s < 0 ? "" : l.slice(s);
  });
}

export function isGenerated(body: string, marker: string, headLines: number): boolean {
  const head = body.split(/\r?\n/, headLines);
  return head.some((l) => l.includes(marker));
}

export function loadRules(dir: string): Rules {
  const p = path.join(dir, "rules.json");
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (e) {
    fatal(`读规则表失败 ${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  let r: Rules;
  try {
    r = JSON.parse(raw) as Rules;
  } catch {
    fatal("规则表 JSON 坏");
  }
  if (!Array.isArray(r.rules) || r.rules.length === 0) fatal("规则表 rules 为空——fail loud");
  for (const rule of r.rules) {
    if (!rule.id || !rule.pattern) fatal(`规则缺 id/pattern: ${JSON.stringify(rule)}`);
    try {
      new RegExp(rule.pattern);
    } catch {
      fatal(`规则 ${rule.id} 正则非法: ${rule.pattern}`);
    }
  }
  if (!Array.isArray(r.tag_markers) || r.tag_markers.length === 0) fatal("tag_markers 为空");
  if (!Number.isInteger(r.window) || r.window < 0) fatal("window 须为非负整数");
  if (!Number.isInteger(r.file_head_lines) || r.file_head_lines < 1) fatal("file_head_lines 须为正整数");
  return r;
}

export function loadExemptions(dir: string): Exemption[] {
  const p = path.join(dir, "exemptions.json");
  if (!fs.existsSync(p)) return [];
  let arr: Exemption[];
  try {
    arr = JSON.parse(fs.readFileSync(p, "utf8")) as Exemption[];
  } catch {
    fatal("例外表 JSON 坏");
  }
  if (!Array.isArray(arr)) fatal("例外表须为数组");
  for (const e of arr) {
    if (!e.file || !e.rule || !e.line_text) fatal(`例外缺 file/rule/line_text: ${JSON.stringify(e)}`);
    if (!e.reason || e.reason.trim() === "") {
      process.stderr.write(`rust_narrative_check: 例外 ${e.file} [${e.rule}] 缺 reason（例外必须自证）\n`);
      process.exit(1);
    }
  }
  return arr;
}

function listFiles(root: string, rules: Rules): string[] {
  const out: string[] = [];
  const prune = new Set(rules.prune_dirs);
  const walk = (dir: string): void => {
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    ents.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (const ent of ents) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (prune.has(ent.name)) continue;
        walk(p);
        continue;
      }
      if (rules.extensions.some((ext) => ent.name.endsWith(ext))) out.push(p);
    }
  };
  for (const r of rules.scan_roots) walk(path.join(root, r));
  return out;
}

function windowHas(narr: string[], idx: number, window: number, words: string[]): boolean {
  if (words.length === 0) return false;
  const lo = Math.max(0, idx - window);
  const hi = Math.min(narr.length - 1, idx + window);
  for (let j = lo; j <= hi; j++) {
    const s = narr[j] ?? "";
    for (const w of words) if (s.includes(w)) return true;
  }
  return false;
}

/** 文件头 N 行叙事段内是否有档案 tag（R1b/R4 的整文件过闸判据）。 */
export function fileHeadHasTag(narr: string[], rules: Rules): boolean {
  const head = narr.slice(0, rules.file_head_lines);
  return head.some((s) => rules.tag_markers.some((t) => s.includes(t)));
}

/** 单文件判定（纯函数，测试直调）。 */
export function scanFile(relFile: string, body: string, rules: Rules, generated = false): Hit[] {
  const narr = narrativeLines(relFile, body);
  const headTag = fileHeadHasTag(narr, rules);
  const hits: Hit[] = [];
  const compiled = rules.rules.map((r) => ({ r, re: new RegExp(r.pattern) }));
  for (let i = 0; i < narr.length; i++) {
    const seg = narr[i] ?? "";
    if (seg === "") continue;
    for (const { r, re } of compiled) {
      if (!re.test(seg)) continue;
      if (r.file_head_tag_exempt === true && headTag) continue;
      if (windowHas(narr, i, rules.window, rules.tag_markers)) continue;
      if (windowHas(narr, i, rules.window, r.exempt_words)) continue;
      hits.push({ file: relFile, line: i + 1, rule: r.id, text: seg.trim(), exempted: false, generated });
    }
  }
  return hits;
}

export function scanRepo(root: string, rules: Rules, exemptions: Exemption[]): ScanResult {
  const files = listFiles(root, rules);
  if (files.length === 0) fatal("扫描面为空——fail loud（空集不得绿）");
  let generatedScanned = 0;
  const hits: Hit[] = [];
  for (const abs of files) {
    const rel = toSlash(path.relative(root, abs));
    let body: string;
    try {
      body = fs.readFileSync(abs, "utf8");
    } catch {
      continue;
    }
    const gen = isGenerated(body, rules.generated_marker, rules.generated_marker_head_lines);
    if (gen) generatedScanned++;
    hits.push(...scanFile(rel, body, rules, gen));
  }
  // 三向对账：命中 ↔ 例外
  const used = new Set<number>();
  for (const h of hits) {
    const k = exemptions.findIndex((e, idx) => !used.has(idx) && e.file === h.file && e.rule === h.rule && e.line_text === h.text);
    if (k >= 0) {
      used.add(k);
      h.exempted = true;
    }
  }
  const zombies = exemptions.filter((_, idx) => !used.has(idx));
  return { files: files.length, generatedScanned, hits, zombies };
}

export function main(argv: string[]): number {
  let json = false;
  let repo = "";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    if (a === "-check" || a === "--check") continue; // 只读闸：别名，无写模式
    if (a === "--json") {
      json = true;
      continue;
    }
    if (a === "-repo" || a === "--repo") {
      const v = argv[++i];
      if (v === undefined) {
        process.stderr.write("rust_narrative_check: -repo 缺值\n");
        return 2;
      }
      repo = v;
      continue;
    }
    process.stderr.write(`rust_narrative_check: 未知参数 ${JSON.stringify(a)}\n`);
    return 2;
  }
  const root = repo === "" ? projectRoot() : path.resolve(repo);
  const selfDir = import.meta.dirname;
  const rules = loadRules(selfDir);
  const exemptions = loadExemptions(selfDir);
  const res = scanRepo(root, rules, exemptions);
  const live = res.hits.filter((h) => !h.exempted);
  const exempted = res.hits.length - live.length;
  const byRule = new Map<string, number>();
  for (const h of live) byRule.set(h.rule, (byRule.get(h.rule) ?? 0) + 1);
  const ruleSummary = rules.rules.map((r) => `${r.id} ${byRule.get(r.id) ?? 0}`).join(" / ");
  const genLive = live.filter((h) => h.generated).length;

  if (json) {
    const out = {
      files: res.files,
      generated_scanned: res.generatedScanned,
      live: live.map((h) => ({ file: h.file, line: h.line, rule: h.rule, text: h.text, generated: h.generated })),
      exempted,
      zombies: res.zombies,
    };
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
  } else {
    for (const h of live) {
      const rule = rules.rules.find((r) => r.id === h.rule);
      const tag = h.generated ? "〔@generated：改模板再生〕" : "";
      process.stdout.write(`${h.file}:${h.line} [${h.rule} ${rule?.name ?? ""}]${tag} ${h.text}\n`);
    }
    for (const z of res.zombies) {
      process.stdout.write(`僵尸例外: ${z.file} [${z.rule}] ${JSON.stringify(z.line_text)}——不再命中，例外条目应删\n`);
    }
    if (live.length > 0) {
      const hinted = new Set(live.map((h) => h.rule));
      for (const r of rules.rules) {
        if (hinted.has(r.id)) process.stdout.write(`  处方 ${r.id}（${r.name}）：${r.hint}\n`);
      }
    }
  }
  const failed = live.length > 0 || res.zombies.length > 0;
  // --json 只出 JSON（机器消费面不混文本行），退出码同文本模式。
  if (json) return failed ? 1 : 0;
  if (failed) {
    process.stdout.write(
      `rust_narrative_check: FAIL——扫描 ${res.files} 文件（@generated 扫入 ${res.generatedScanned}）/ 活命中 ${live.length}（${ruleSummary}；@generated 内 ${genLive}）/ 过闸 ${exempted} / 僵尸例外 ${res.zombies.length}\n`,
    );
    return 1;
  }
  process.stdout.write(
    `rust_narrative_check: PASS——扫描 ${res.files} 文件（@generated 扫入 ${res.generatedScanned}）/ 活命中 0 / 过闸 ${exempted} / 例外表 ${exemptions.length} 零僵尸\n`,
  );
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
