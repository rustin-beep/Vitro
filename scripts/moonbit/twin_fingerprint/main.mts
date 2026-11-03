#!/usr/bin/env node
// twin_fingerprint：孪生复制件指纹对拍闸（审阅 v2 批 A7 / R1a 处方 R1，2026-11-02）。
//
// 背景（R1a ④ M1「手工孪生复制件」形态）：同一段逻辑因包不可互 import（cmd 层）
// 或历史分层被复制成 N 份——cast.mbt 的 gen_cast_expr ↔ gen_expr_with_cast、
// dump 四家 main.mbt 的参数段。修复落在触发报告的那份，其余份靠「改这里时想起
// 那里」（#345 在 cast 孪生间做对了连坐、但新缺口同样两处同漏；dump_compile 的
// 三道门禁其余三家至今没有——F5）。本闸把「孪生份间的语义差」变成显式登记账：
//
//   ① 每集成员抽**结构指纹**（cast 链 = 归一化条件 + 每臂发射指令序列；dump 参数段
//      = 门禁谓词集合），集内成员间指纹差集逐条列出
//   ② 每条差必须在本集 divergences 表带 reason（合法分叉 / known 缺口均可，但必须说清）
//   ③ divergences 条目在实际差集里已消失（双份同步消除）= 僵尸红——修好忘删即抓
//   ④ 指纹抽取空集 = 锚点失效 fail loud
//
// 用法（**仓库根**）：
//   node scripts/moonbit/twin_fingerprint/main.mts             # 报告（各集指纹与差集）
//   node scripts/moonbit/twin_fingerprint/main.mts -check      # 判定（CI 门禁用）
//   node scripts/moonbit/twin_fingerprint/main.mts --selftest  # J9：三路内存注入必红
//   node scripts/moonbit/twin_fingerprint/main.mts --discover  # 列出现状全部指纹差（填表辅助）
//
// fail loud：源/锚点失效 → exit 2；判据不过 → exit 1。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";
import { normalizeCond } from "../cast_matrix/main.mts";
import { stripLineComments } from "../conv_specs/main.mts";

export const RULES_PATH = "scripts/moonbit/twin_fingerprint/rules.json";

export interface MemberSpec {
  name: string;
  file: string;
  anchor_start: string;
  note?: string;
}

export interface DivergenceDecl {
  item: string;
  only_in: string;
  reason: string;
}

export interface TwinSet {
  name: string;
  extractor: "cast_chain" | "dump_arg_guards";
  members: MemberSpec[];
  divergences: DivergenceDecl[];
  note?: string;
}

export interface RulesDoc {
  schema: number;
  twin_sets: TwinSet[];
}

/** 指纹项：cast 链 = "条件 => 指令序列"；dump 参数段 = 谓词名。 */
export interface Fingerprint {
  member: string;
  items: string[];
}

/** 基础设施失败（源缺失/锚点失效/规则坏）：进程内 throw（可测），CLI 入口统一转 exit 2。 */
function fatal(msg: string): never {
  throw new Error(`twin_fingerprint: ${msg}`);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

function readSlice(file: string, anchor: string): string {
  let text: string;
  try {
    text = fs.readFileSync(abs(file), "utf8");
  } catch (e) {
    fatal(`读源失败 ${file}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const i = text.indexOf(anchor);
  if (i < 0) fatal(`锚点未命中 ${anchor}（${file}）`);
  // 从锚点**之后**起算——锚点串自身不得进切片（否则 ^fn 收尾会命中锚点自己）
  return text.slice(i + anchor.length);
}

/** 抽顶层 if-else 链的 (条件, 臂体) 块——复用 cast_matrix 的链形态约定（moon fmt 两空格缩进、&& 续行、{ 收尾）。 */
export function extractChainBlocks(body: string): { conds: string[]; bodies: string[] } {
  const lines = body.split("\n");
  const conds: string[] = [];
  const bodies: string[] = [];
  let inCond = false;
  let cur = "";
  for (let li = 0; li < lines.length; li++) {
    const line = lines[li] ?? "";
    if (!inCond) {
      const m = /^  (?:\} else )?if (.*)$/.exec(line);
      if (m !== null) {
        inCond = true;
        cur = m[1] ?? "";
        if (cur.endsWith("{")) { conds.push(cur.slice(0, -1).trim()); bodies.push(""); inCond = false; }
      }
    } else {
      cur += " " + line.trim();
      if (cur.endsWith("{")) {
        conds.push(cur.slice(0, -1).trim());
        // 臂体 = 本臂首行之后到下一顶层臂起始行之前
        bodies.push("");
        inCond = false;
      }
    }
  }
  // 第二遍填体：每臂体 = [startLine+1, 下一臂 startLine) 的行（顶层臂以 `  if` / `  } else if` / 收尾 `  }` 为界）
  const starts: number[] = [];
  let inC2 = false;
  for (let li = 0; li < lines.length; li++) {
    const line = lines[li] ?? "";
    if (!inC2) {
      if (/^  (?:\} else )?if /.test(line)) {
        starts.push(li);
        inC2 = !line.trimEnd().endsWith("{");
      }
    } else if (line.trimEnd().endsWith("{")) {
      inC2 = false;
    }
  }
  for (let k = 0; k < starts.length; k++) {
    const from = starts[k] ?? 0;
    const to = k + 1 < starts.length ? (starts[k + 1] ?? lines.length) : lines.length;
    bodies[k] = lines.slice(from + 1, to).join("\n");
  }
  return { conds, bodies };
}

/** 德摩根归一：`!(A is X || B is Y)` → `!(A is X) && !(B is Y)`——孪生两份对同一语义
 *  的两种写法（显式链拆两段否定、隐式链整体否定）不得算指纹差。 */
export function demorganNorm(s: string): string {
  return s.replace(/!\(([TS]) is (TK_\w+) \|\| ([TS]) is (TK_\w+)\)/g, "!($1 is $2) && !($3 is $4)");
}

/** cast 链指纹：归一化条件 => 臂体 OpCode 发射序列 + [嵌套条件序列]（嵌套指令全算）。
 *
 * 嵌套条件（≥4 空格缩进的 if/else-if，如 TK_Char 臂内 S 分型 + TGT_U 的
 * TruncByte/TruncUByte 选择）归一后按序拼进指纹——审阅 P3-4 收窄（2026-11-02）：
 * 原指纹只对齐指令**出现序列**，同一序列不同「嵌套条件⇄指令」配对会同指纹（假绿）。
 * 追加嵌套条件序列后配对错乱大幅可辨；完整配对需 AST，此为文本层边界（注释即账）。 */
export function castChainFingerprint(member: MemberSpec): Fingerprint {
  const raw = readSlice(member.file, member.anchor_start);
  const mFn = /^fn /m.exec(raw);
  const body = mFn !== null && mFn.index > 0 ? raw.slice(0, mFn.index) : raw;
  const { conds, bodies } = extractChainBlocks(body);
  if (conds.length === 0) fatal(`${member.name}（${member.file}）链抽取 0 臂——锚点或链形态已变`);
  const items: string[] = [];
  for (let k = 0; k < conds.length; k++) {
    const armBody = bodies[k] ?? "";
    const ops = [...armBody.matchAll(/OpCode::(\w+)/g)].map((m) => m[1] ?? "").join(",");
    const nested = [...armBody.matchAll(/^    (?:\} else )?if (.*) \{$/gm)].map((m) => demorganNorm(normalizeCond(m[1] ?? "")));
    items.push(`${demorganNorm(normalizeCond(conds[k] ?? ""))} => ${ops}${nested.length > 0 ? ` [${nested.join("; ")}]` : ""}`);
  }
  return { member: member.name, items };
}

const DUMP_PREDICATES: { key: string; test: RegExp; desc: string }[] = [
  { key: "guard:lower_bound", test: /(?:positional|args)\.length\(\) < \d+/, desc: "参数下界门禁（缺参 fail loud）" },
  { key: "guard:upper_bound", test: /(?:positional|args)\.length\(\) > \d+/, desc: "参数上界门禁（过多 fail loud）——限定 positional/args 前缀，防文件名长度检查（name.length() > 2）误命中" },
  { key: "guard:target_eq_out", test: /target == out_dir|positional\[0\] == positional\[1\]/, desc: "target==out_dir 拒写门禁（防 dump 产物污染语料目录）" },
  { key: "sort:lexical", test: /sort_files_lex/, desc: "字典序排序（陷阱 #29 口径）" },
  { key: "sort:builtin", test: /files\.sort\(\)/, desc: "内置 String sort（非字典序——陷阱 #29）" },
  { key: "rc:usage_4", test: /c_exit\(4\)/, desc: "用法错 rc=4" },
];

/** dump 参数段指纹：门禁谓词集合（参数个数差异不进指纹——各家参数面本不同）。
 *  谓词在**剥行注释后**的函数体上匹配（2026-11-03 实锤：A7' 批把 dump_tokens 的注释改成
 *  「…与 dump_compile 的 sort_files_lex 口径不一…」，行为未变而 /sort_files_lex/ 被注释
 *  命中——rebase 后本闸假红一次；谓词面必须只看代码）。 */
export function dumpGuardsFingerprint(member: MemberSpec): Fingerprint {
  const raw = readSlice(member.file, member.anchor_start); // 已从锚点后起算
  const mFn = /^(pub )?fn /m.exec(raw); // 下一个顶层 fn 收尾（main 若是最后一个 fn 则到文件尾）
  const body = stripLineComments(mFn !== null && mFn.index > 0 ? raw.slice(0, mFn.index) : raw);
  const items: string[] = [];
  for (const p of DUMP_PREDICATES) {
    if (p.test.test(body)) items.push(p.key);
  }
  if (items.length === 0) fatal(`${member.name}（${member.file}）谓词抽取 0 条——锚点失效`);
  return { member: member.name, items };
}

export function fingerprintOf(member: MemberSpec, extractor: string): Fingerprint {
  if (extractor === "cast_chain") return castChainFingerprint(member);
  if (extractor === "dump_arg_guards") return dumpGuardsFingerprint(member);
  fatal(`未知 extractor: ${extractor}`);
}

/** 差集双向（审阅 P1 修复，2026-11-02）：
 *  ① 独有向——只在某成员出现的指纹项（原判据）；
 *  ② 缺项向——出现次数 ≥2 的项、某成员没有。多成员集只看「独有」会放行中间态：
 *     修了两三家漏最后一家时，缺项方项集里没有该项、有项方互相看见不算独有 ⇒ 零报告
 *     ——正是 R1a 要治的形态。两向同样要求在 divergences 登记（only_in = 不一致方）。 */
export interface DiffEntry {
  item: string;
  only_in: string;
  /** only = 独有向（只有 only_in 有）；missing = 缺项向（其他 ≥2 家有、only_in 缺） */
  kind: "only" | "missing";
}

export function diffOf(set: TwinSet, fps: Fingerprint[]): DiffEntry[] {
  const itemCount = new Map<string, number>();
  for (const fp of fps) {
    for (const it of new Set(fp.items)) itemCount.set(it, (itemCount.get(it) ?? 0) + 1);
  }
  const out: DiffEntry[] = [];
  for (const fp of fps) {
    const own = new Set(fp.items);
    for (const it of fp.items) {
      if ((itemCount.get(it) ?? 0) === 1) out.push({ item: it, only_in: fp.member, kind: "only" });
    }
    for (const [it, cnt] of itemCount) {
      if (cnt >= 2 && !own.has(it)) out.push({ item: it, only_in: fp.member, kind: "missing" });
    }
  }
  void set;
  return out.sort((a, b) => (a.only_in + a.item < b.only_in + b.item ? -1 : 1));
}

export function verdict(rd: RulesDoc, fpsBySet: Record<string, Fingerprint[]>): boolean {
  let ok = true;
  const say = (s: string): void => {
    process.stdout.write(`  ${s}\n`);
  };
  for (const set of rd.twin_sets) {
    const fps = fpsBySet[set.name];
    if (fps === undefined || fps.length !== set.members.length) {
      ok = false;
      say(`[集失] ${set.name} 指纹数 ${String(fps?.length ?? 0)} ≠ 成员数 ${set.members.length}`);
      continue;
    }
    if (set.members.length < 2) {
      ok = false;
      say(`[集小] ${set.name} 成员 < 2——孪生集至少两份`);
    }
    const diffs = diffOf(set, fps);
    for (const d of diffs) {
      const declared = set.divergences.some((x) => x.only_in === d.only_in && x.item === d.item);
      if (!declared) {
        ok = false;
        const shape = d.kind === "only"
          ? `只在 ${d.only_in} 有 "${d.item}"——改一份没跟另一份`
          : `${d.only_in} 缺 "${d.item}"（集内其他成员已有）——修了几家漏这家`;
        say(`[孪生分叉未登记] ${set.name}: ${shape}（M1 形态）。同步，或在 divergences 带 reason 登记（only_in=${d.only_in}）`);
      }
    }
    for (const dec of set.divergences) {
      const alive = diffs.some((d) => d.only_in === dec.only_in && d.item === dec.item);
      if (!alive) {
        ok = false;
        say(`[僵尸登记] ${set.name}: divergences 条目 (only_in=${dec.only_in}, "${dec.item}") 实际指纹已不含——双份同步消除后忘删，清账`);
      }
    }
  }
  return ok;
}

function cloneFps(m: Record<string, Fingerprint[]>): Record<string, Fingerprint[]> {
  const out: Record<string, Fingerprint[]> = {};
  for (const [k, v] of Object.entries(m)) out[k] = v.map((f) => ({ member: f.member, items: [...f.items] }));
  return out;
}

function quiet(fn: () => boolean): boolean {
  const w = process.stdout.write.bind(process.stdout);
  process.stdout.write = (() => true) as typeof process.stdout.write;
  try {
    return fn();
  } finally {
    process.stdout.write = w;
  }
}

export function selftestRun(rd: RulesDoc, fpsBySet: Record<string, Fingerprint[]>): number {
  if (!quiet(() => verdict(rd, fpsBySet))) {
    process.stdout.write("twin_fingerprint: selftest ABORT——基线不绿\n");
    return 2;
  }
  let fails = 0;
  // 注入①：给首集首成员追加一个假指纹项（模拟单边改一份）
  {
    const m2 = cloneFps(fpsBySet);
    const first = rd.twin_sets[0];
    if (first === undefined) return 2;
    m2[first.name]?.[0]?.items.push("T is TK_Zombie => CastZ9Z9");
    const red = !quiet(() => verdict(rd, m2));
    process.stdout.write(`  注入① ${first.name} 单边追加假指纹项 → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  // 注入②：删掉一条已登记 divergence（→ 分叉未登记）
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as RulesDoc;
    const set2 = rd2.twin_sets[0];
    if (set2 === undefined || set2.divergences.length === 0) return 2;
    const victim = set2.divergences[0]!;
    set2.divergences = set2.divergences.filter((x) => x !== victim);
    const red = !quiet(() => verdict(rd2, fpsBySet));
    process.stdout.write(`  注入② 删 divergence 登记条目 → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  // 注入③：加一条僵尸登记（实际指纹不含）
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as RulesDoc;
    const set2 = rd2.twin_sets[0];
    if (set2 === undefined) return 2;
    set2.divergences.push({ item: "T is TK_Zombie2 => CastZ9Z9", only_in: "zz", reason: "僵尸探针" });
    const red = !quiet(() => verdict(rd2, fpsBySet));
    process.stdout.write(`  注入③ 加僵尸 divergence 条目 → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  // 注入④（审阅 P1 缺项向常驻锚）：四成员集 2 有 2 无——dump_compile/dump_ast 补
  // upper_bound 而 tokens/typeck 仍缺 ⇒ 原独有登记变僵尸 + 两条缺项未登记，双红
  {
    const m2 = cloneFps(fpsBySet);
    const dump = m2["dump_four"];
    if (dump === undefined || dump.length < 4) return 2;
    dump[0]!.items.push("guard:upper_bound");
    dump[1]!.items.push("guard:upper_bound");
    const red = !quiet(() => verdict(rd, m2));
    process.stdout.write(`  注入④ dump 四家 2 有 2 无中间态（F5 修一半）→ ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  if (fails > 0) {
    process.stdout.write(`twin_fingerprint: selftest FAIL——${fails} 路注入未被捕获\n`);
    return 1;
  }
  process.stdout.write("twin_fingerprint: selftest PASS——四路注入全部捕获（红），J9 证红成立\n");
  return 0;
}

export function loadRules(p = RULES_PATH): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(p), "utf8");
  } catch (e) {
    fatal(`读规则失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`规则解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (rd.schema !== 1) fatal(`规则 schema 不支持: ${rd.schema}`);
  return rd;
}

export function allFingerprints(rd: RulesDoc): Record<string, Fingerprint[]> {
  const out: Record<string, Fingerprint[]> = {};
  for (const set of rd.twin_sets) out[set.name] = set.members.map((m) => fingerprintOf(m, set.extractor));
  return out;
}

export function main(argv: string[]): number {
  let mode = "check";
  for (const a of argv) {
    if (a === "-check" || a === "--check") mode = "check";
    else if (a === "--discover" || a === "-discover") mode = "discover";
    else if (a === "--selftest" || a === "-selftest") mode = "selftest";
    else fatal(`未知参数: ${a}（可用：-check / --discover / --selftest）`);
  }
  const rd = loadRules();
  const fpsBySet = allFingerprints(rd);
  if (mode === "discover") {
    for (const set of rd.twin_sets) {
      process.stdout.write(`set ${set.name}（${set.extractor}）：\n`);
      for (const fp of fpsBySet[set.name] ?? []) {
        process.stdout.write(`  member ${fp.member}: ${fp.items.length} 项\n`);
        for (const it of fp.items) process.stdout.write(`    ${it}\n`);
      }
      process.stdout.write(`  差集 ${diffOf(set, fpsBySet[set.name] ?? []).length} 条\n`);
    }
    return 0;
  }
  if (mode === "selftest") return selftestRun(rd, fpsBySet);
  if (verdict(rd, fpsBySet)) {
    process.stdout.write("twin_fingerprint: PASS（孪生集指纹差全部在册登记；无僵尸条目）\n");
    return 0;
  }
  process.stdout.write("twin_fingerprint: FAIL——孪生复制件有未登记分叉（详见上方）\n");
  return 1;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (e) {
    process.stderr.write(`${e instanceof Error ? e.message : String(e)}\n`);
    process.exit(2);
  }
}
