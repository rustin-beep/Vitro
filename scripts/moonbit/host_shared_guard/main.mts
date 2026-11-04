#!/usr/bin/env node
// host_shared_guard：host 层共享逻辑守卫与消费方对账闸（审阅 v2 批 A7 / R1a 处方 R4，2026-11-02）。
//
// 背景（R1a ④ M4「函数族口径分叉」形态 + 总报告造因②）双面：
//   面 A（负 n 守卫覆盖）——带 n 内存写族 strncpy/memcpy/memmove/strncat 修了负号形
//     trap（705582d6，DIFF-LIB-STRNCPY-01），但同族的 memset 走 clamp 0xFFFFFFFF 软夹
//     静写满（F6：memset(buf,0x41,-1) clang segfault rc=139 / vitro 双臂静默成功 rc=0
//     ——最差形态：学生无感知）；strncmp/memcmp/memchr 只读族无前置 trap（受检 load 兜底）。判据：
//     **全部带长度参数的 pub host_ 函数**必须 ①体内有负域 trap 守卫、或 ②转发给有
//     守卫的同族函数（memcpy→memmove 形态）、或 ③豁免表带 reason——三态机判，新函数
//     带长度参数入库即被枚举抓面。
//   面 B（共享函数消费方登记）——json_escape/utf8 族是 host/core 层被多包消费的共享
//     逻辑（审阅 v2 M06：三臂分叉案根因在共享层），改共享函数时「有哪些消费方」此前
//     靠人脑。判据：登记表的消费方文件集合 == 实际 grep 集合（双向差集红）——新增/
//     删除消费方不更新登记即红；改共享函数时登记表就是强制的对账清单。
//     消费面扫描口径（2026-11-04 审阅 P3⑤）：剥行注释后做词边界匹配——
//     判据边界（URL 字面量假阴性 / 块注释仍命中）单源登记在 conv_specs
//     stripLineComments 的 docstring，两闸共用同一实现与口径。
//
// 用法（**仓库根**）：
//   node scripts/moonbit/host_shared_guard/main.mts             # 报告
//   node scripts/moonbit/host_shared_guard/main.mts -check      # 判定（CI 门禁用）
//   node scripts/moonbit/host_shared_guard/main.mts --selftest  # J9：四路内存注入必红
//   node scripts/moonbit/host_shared_guard/main.mts --discover  # 列出消费方现状（填表辅助）
//
// fail loud：源/锚点失效 → exit 2；判据不过 → exit 1。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";
import { stripLineComments } from "../conv_specs/main.mts";

export const RULES_PATH = "scripts/moonbit/host_shared_guard/rules.json";

export interface NegLenExemption {
  reason: string;
  issue?: string;
}

export interface SharedFn {
  def: string;
  /** 定义锚点（须在 def 文件命中——防「文件里只是注释提及函数名」被 \b 匹配误当定义在位；审阅 P3-2 真校验） */
  def_anchor: string;
  consumers: string[];
  note?: string;
}

export interface RulesDoc {
  schema: number;
  neg_len_source: { file: string };
  neg_len_exemptions: Record<string, NegLenExemption>;
  shared_functions: Record<string, SharedFn>;
}

export interface HostFn {
  name: string;
  hasLenParam: boolean;
  lenParam: string;
  hasTrap: boolean;
  forwardsTo: string;
}

function fatal(msg: string): never {
  throw new Error(`host_shared_guard: ${msg}`);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

const RE_PUB_FN = /^pub fn (host_\w+)\(/gm;
/** 负域 trap 守卫形态：`if n < 0 {` 或 `if (n|size) > 0x… {`，块内**紧跟** `return trap_only(`。 */
const RE_NEG_TRAP = /if (?:n < 0|(?:n|size) > 0x[0-9A-Fa-f]+U?L?) \{\s*\n\s*return trap_only\(/;

/** 解析 host_string.mbt：带长度参数（n/size/count : Int32|UInt64）的 pub host_ 函数三态。 */
export function parseHostFns(text: string): HostFn[] {
  const fns: HostFn[] = [];
  for (const m of text.matchAll(RE_PUB_FN)) {
    const name = m[1] ?? "";
    // 函数体 = 签名行起到下一个顶层项（^pub fn / ^fn / ^///| 皆可收——用 ^(?:pub )?fn 即可）
    const bodyStart = m.index + m[0].length;
    const next = /^(?:pub )?fn |^\/\/\||^extern /m.exec(text.slice(bodyStart));
    const body = next !== null ? text.slice(bodyStart, bodyStart + next.index) : text.slice(bodyStart);
    // 参数段：签名起止（签名本身可能多行——按平衡括号扫）
    const sigEnd = balancedEnd(text, m.index + m[0].length - 1);
    const params = text.slice(m.index + m[0].length, sigEnd);
    const lenM = /\b(n|size|count) : (Int32|UInt64)\b/.exec(params);
    // 负域 trap 判据只认仓内已有先例形态：`if n < 0`（strncpy/memmove，Int32 域）。
    // 注意 memset 的 NULL 区 trap_only + `size > 0xFFFFFFFF` clamp 是**软夹**（F6）
    // 不是负域 trap——不得因「含 trap_only 且含 0xFFFF」误判覆盖（首版实错，已修）。
    // 判据两形态（审阅 P3-3 扩展，2026-11-02）：①Int32 域 `if n < 0 {` + 块内紧跟 return trap
    // （strncpy/memmove 先例）；②u64 域巨量 `if (n|size) > 0x… {` + 块内紧跟 return trap
    // （**现仓零实例**——F6 修复批给 u64 族补守卫时本判据即生效；在此之前 u64 函数一律
    // 经豁免入账，豁免 reason 须注明 u64 域）。
    // **块内紧跟 return trap_only** 是关键：memset/strncat 的 clamp 是表达式 if
    // （`if size > 0xFFFFFFFFUL { 0xFFFFFFFFUL } else { size }`——块内是值非 return），
    // 松判据「含比较 + 含 trap_only」会被 NULL 区 trap_only 搭配 clamp 误判覆盖（本批实踩两次）。
    const trap = RE_NEG_TRAP.test(body);
    let forwards = "";
    for (const c of body.matchAll(/\b(host_\w+)\(/g)) {
      if ((c[1] ?? "") !== name) {
        forwards = c[1] ?? "";
        break;
      }
    }
    fns.push({
      name,
      hasLenParam: lenM !== null,
      lenParam: lenM !== null ? (lenM[0] ?? "") : "",
      hasTrap: trap,
      forwardsTo: forwards,
    });
  }
  return fns;
}

/** 从 openIdx（含 `{` 或 `(` 的位置起）找平衡闭括号位置。 */
function balancedEnd(text: string, openIdx: number): number {
  const open = text[openIdx];
  const close = open === "(" ? ")" : "}";
  let depth = 0;
  for (let i = openIdx; i < text.length; i++) {
    const ch = text[i] ?? "";
    if (ch === open) depth++;
    else if (ch === close) {
      depth--;
      if (depth === 0) return i;
    }
  }
  return Math.min(text.length, openIdx + 2000);
}

/** 面 A 三态：有守卫 / 转发有守卫者 / 豁免在册。 */
export function negLenVerdict(fns: HostFn[], exemptions: Record<string, NegLenExemption>): { ok: boolean; issues: string[] } {
  const issues: string[] = [];
  const lenFns = fns.filter((f) => f.hasLenParam);
  if (lenFns.length === 0) {
    issues.push("[空集] 带 n/size 长度参数的 pub host_ 函数枚举出 0 个——源或解析形态已变，拒绝判定");
    return { ok: false, issues };
  }
  const guarded = new Set(fns.filter((f) => f.hasTrap).map((f) => f.name));
  for (const f of lenFns) {
    if (f.hasTrap) continue;
    if (f.forwardsTo !== "" && guarded.has(f.forwardsTo)) continue; // 转发覆盖（memcpy→memmove）
    if (exemptions[f.name] !== undefined) continue;
    issues.push(
      `[负 n 守卫缺失未登记] host_${f.name.slice(5)}（${f.lenParam}）：无负域 trap 也无转发覆盖——补守卫（strncpy 同款 if n < 0 trap / u64 域等价巨量检查），或在 neg_len_exemptions 带 reason 登记`,
    );
  }
  for (const [name, ex] of Object.entries(exemptions)) {
    const f = lenFns.find((x) => x.name === name);
    if (f === undefined) {
      issues.push(`[僵尸豁免] ${name} 不在带长度参数函数集（改名/删参后忘删条目），清账`);
      continue;
    }
    if (f.hasTrap || (f.forwardsTo !== "" && guarded.has(f.forwardsTo))) {
      issues.push(`[僵尸豁免] ${name} 已有守卫/转发覆盖——修好后忘删豁免，清账（reason=${ex.reason.slice(0, 40)}…）`);
    }
  }
  return { ok: issues.length === 0, issues };
}

/** 面 B：实际消费方集合（moonbit/ 下 grep 定义名，排除 _build 与定义文件自身）。 */
export function actualConsumers(fnName: string, defFile: string): string[] {
  const root = abs("moonbit");
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      if (ent.name === "_build" || ent.name === "tools" || ent.name === "target") continue;
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        walk(p);
        continue;
      }
      if (!ent.name.endsWith(".mbt")) continue;
      const rel = path.relative(abs("moonbit"), p).split(path.sep).join("/");
      if (rel === defFile) continue;
      const text = fs.readFileSync(p, "utf8");
      // 消费 = 出现定义名（定义/调用/引用皆算——改共享函数时全部要对账）。
      // 2026-11-03 剥行注释后匹配（B3 批 cli_zero_anchor_wbtest 注释提及
      // utf8_bytes 实锤误命中——「不经 util 包的 utf8_bytes，免给 surface
      // 边表添一条消费边」的防登记说明文字反被当消费；与 twin_fingerprint
      // 同款剥注释口径，A7 两闸自此一致）
      if (new RegExp(`\\b${fnName}\\b`).test(stripLineComments(text))) out.push(rel);
    }
  };
  walk(root);
  return out.sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

export function sharedVerdict(rd: RulesDoc): { ok: boolean; issues: string[] } {
  const issues: string[] = [];
  if (Object.keys(rd.shared_functions).length === 0) {
    issues.push("[空表] shared_functions 登记 0 条——消费方对账面为空，拒绝判定");
    return { ok: false, issues };
  }
  for (const [fnName, decl] of Object.entries(rd.shared_functions)) {
    const defPath = abs(path.join("moonbit", decl.def));
    if (!fs.existsSync(defPath)) {
      issues.push(`[定义缺失] ${fnName} 的 def 文件不存在: ${decl.def}`);
      continue;
    }
    const defText = fs.readFileSync(defPath, "utf8");
    if (!new RegExp(`\\b${fnName}\\b`).test(defText)) {
      issues.push(`[定义缺失] ${fnName} 在 ${decl.def} 中无出现——改名后忘更新登记`);
      continue;
    }
    // 审阅 P3-2 真校验（2026-11-02）：def_anchor 必须命中——\b 名字匹配会被
    // 「文件里注释提及该函数」误当定义在位（json_escape_string 在 util/json_escape.mbt
    // 的注释里被提及即此类）；锚点未中 = 定义不在/已改名。
    if (decl.def_anchor === "" || !defText.includes(decl.def_anchor)) {
      issues.push(`[定义锚点失效] ${fnName} 的 def_anchor ${JSON.stringify(decl.def_anchor)} 在 ${decl.def} 不命中——函数定义改名/移位后登记失实`);
      continue;
    }
    const actual = actualConsumers(fnName, decl.def);
    const want = new Set(decl.consumers);
    const extra = actual.filter((c) => !want.has(c));
    const missing = [...want].filter((c) => !actual.includes(c));
    if (extra.length > 0) {
      issues.push(`[消费方漂移] ${fnName} 实际新增消费方未登记: ${extra.join(", ")}——改共享函数时此清单即对账面，新增消费必须连坐登记`);
    }
    if (missing.length > 0) {
      issues.push(`[消费方漂移] ${fnName} 登记的消费方已不存在（文件删/改名/不再消费）: ${missing.join(", ")}`);
    }
    if (decl.consumers.length === 0) {
      issues.push(`[零消费] ${fnName} 登记消费方 0 个——共享函数至少有定义包外一个消费方才有登记意义`);
    }
  }
  return { ok: issues.length === 0, issues };
}


export function selftestRun(rd: RulesDoc, fns: HostFn[]): number {
  const a0 = negLenVerdict(fns, rd.neg_len_exemptions);
  const b0 = sharedVerdict(rd);
  if (!a0.ok || !b0.ok) {
    process.stdout.write(`host_shared_guard: selftest ABORT——基线不绿\n`);
    for (const s of [...a0.issues, ...b0.issues]) process.stdout.write(`  ${s}\n`);
    return 2;
  }
  let fails = 0;
  // 注入①：给 memset（F6 known）去掉豁免（→ 守卫缺失未登记）
  {
    const ex2 = { ...rd.neg_len_exemptions };
    delete ex2["host_memset"];
    const r = negLenVerdict(fns, ex2);
    process.stdout.write(`  注入① 删 memset 豁免 → ${!r.ok ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (r.ok) fails++;
  }
  // 注入②：给 memmove（已有守卫）加豁免（→ 僵尸向）
  {
    const ex2 = { ...rd.neg_len_exemptions, host_memmove: { reason: "僵尸探针" } };
    const r = negLenVerdict(fns, ex2);
    process.stdout.write(`  注入② 给已有守卫的 memmove 加豁免 → ${!r.ok ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (r.ok) fails++;
  }
  // 注入③：共享函数消费方加假文件（→ 漂移）
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as RulesDoc;
    const firstKey = Object.keys(rd2.shared_functions)[0]!;
    rd2.shared_functions[firstKey]!.consumers.push("ghost/never_exists.mbt");
    const r = sharedVerdict(rd2);
    process.stdout.write(`  注入③ 消费方登记加幽灵文件 → ${!r.ok ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (r.ok) fails++;
  }
  // 注入④：把 memset 豁免指向不存在的函数名（→ 僵尸豁免向）
  {
    const ex2 = { ...rd.neg_len_exemptions, host_ghost_fn: { reason: "僵尸探针" } };
    const r = negLenVerdict(fns, ex2);
    process.stdout.write(`  注入④ 豁免表加不存在函数 → ${!r.ok ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (r.ok) fails++;
  }
  if (fails > 0) {
    process.stdout.write(`host_shared_guard: selftest FAIL——${fails} 路注入未被捕获\n`);
    return 1;
  }
  process.stdout.write("host_shared_guard: selftest PASS——四路注入全部捕获（红），J9 证红成立\n");
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

export function main(argv: string[]): number {
  let mode = "check";
  for (const a of argv) {
    if (a === "-check" || a === "--check") mode = "check";
    else if (a === "--discover" || a === "-discover") mode = "discover";
    else if (a === "--selftest" || a === "-selftest") mode = "selftest";
    else fatal(`未知参数: ${a}（可用：-check / --discover / --selftest）`);
  }
  const rd = loadRules();
  let text: string;
  try {
    text = fs.readFileSync(abs(rd.neg_len_source.file), "utf8");
  } catch (e) {
    fatal(`读源失败 ${rd.neg_len_source.file}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const fns = parseHostFns(text);
  if (fns.length === 0) fatal(`pub host_ 函数枚举 0 个——${rd.neg_len_source.file} 形态已变`);
  if (mode === "discover") {
    process.stdout.write(`带长度参数的 pub host_ 函数（${fns.filter((f) => f.hasLenParam).length} 个）：\n`);
    for (const f of fns.filter((f) => f.hasLenParam)) {
      process.stdout.write(`  ${f.name.padEnd(16)} ${f.lenParam.padEnd(14)} trap=${f.hasTrap} forwards=${f.forwardsTo}\n`);
    }
    for (const [fnName, decl] of Object.entries(rd.shared_functions)) {
      process.stdout.write(`共享函数 ${fnName}（${decl.def}）消费方 ${decl.consumers.length} + 实际 ${actualConsumers(fnName, decl.def).length}:\n`);
      for (const c of actualConsumers(fnName, decl.def)) process.stdout.write(`    ${c}\n`);
    }
    return 0;
  }
  if (mode === "selftest") return selftestRun(rd, fns);
  const a = negLenVerdict(fns, rd.neg_len_exemptions);
  const b = sharedVerdict(rd);
  for (const s of a.issues) process.stdout.write(`  ${s}\n`);
  for (const s of b.issues) process.stdout.write(`  ${s}\n`);
  if (a.ok && b.ok) {
    process.stdout.write("host_shared_guard: PASS（负 n 守卫三态全覆盖；共享函数消费方账实相符）\n");
    return 0;
  }
  process.stdout.write("host_shared_guard: FAIL——host 共享面守卫/消费方已分叉（详见上方）\n");
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
