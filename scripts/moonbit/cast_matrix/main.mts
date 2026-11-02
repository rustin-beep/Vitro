#!/usr/bin/env node
// cast_matrix：cast/转换类对偶矩阵断言闸（审阅 v2 批 A7 / R1a 处方 R2，2026-11-02）。
//
// 背景（R1a ④ M2「对偶矩阵缺格」形态）：#345 修 u64→fp 正向时给 Q↔D 加了
// CastUQ2D/CastUQ2F，反向 fp→u64 至今饱和错值（F2）、float→LL 至今零发射
// （F1）——cast 分派是一张隐式的 (目标类型 × 源类型 × 符号性) 矩阵，修复只填
// 被报告的那格，其余格靠人肉记忆连坐。本闸把矩阵补全从「偶发审阅」变成
// 枚举断言，双面：
//   面 A（分支链完备性）：解析 codegen/cast.mbt 两个孪生函数的顶层 if-else
//     链条件（受限布尔语言求值器），对 (T,S,S_u) 全组合求值——**全不命中 =
//     零发射**（F1 的 C 形态：编译期无诊断、运行期位模式直出）。零发射组合
//     必须在 zero_emit_allowed（合法恒等/位模式兼容，带 reason）或
//     zero_emit_known_gaps（已知缺陷，带 issue 指向）——两表条目实际已命中
//     发射 = 僵尸红（修好后忘删即抓）。
//   面 B（opcode 对偶性）：从 opcode.mbt 抽 CastX2Y 指令全集——凡 X→Y 存在
//     则同值域反向 Y→X 须存在，或在 dual_exemptions（合法豁免：位模式通用
//     类）/dual_known_gaps（待修：F2 族饱和错值）。豁免/缺口条目指令已存在
//     = 僵尸红。
//
// 用法（**仓库根**）：
//   node scripts/moonbit/cast_matrix/main.mts             # 报告（零发射矩阵 + 对偶表）
//   node scripts/moonbit/cast_matrix/main.mts -check      # 判定（CI 门禁用）
//   node scripts/moonbit/cast_matrix/main.mts --selftest  # J9：四路内存注入必红
//   node scripts/moonbit/cast_matrix/main.mts --discover  # 列出现状全部零发射组合（填表辅助）
//
// fail loud：源/锚点/条件语法不认识 → exit 2（求值器对未知语法零容忍——静默
// 跳过会把「解析失败」伪装成「全覆盖」）；断言不过 → exit 1。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

export const RULES_PATH = "scripts/moonbit/cast_matrix/rules.json";

export interface ChainSource {
  name: string;
  file: string;
  anchor_start: string;
  note?: string;
}

export interface Reasoned {
  reason: string;
  issue?: string;
}

export interface RulesDoc {
  schema: number;
  kinds: string[];
  chain_sources: ChainSource[];
  opcode_source: { file: string; anchor_start: string; anchor_end: string };
  zero_emit_allowed: Record<string, Reasoned>;
  zero_emit_known_gaps: Record<string, Reasoned>;
  dual_exemptions: Record<string, Reasoned>;
  dual_known_gaps: Record<string, Reasoned>;
}

/** 求值绑定：T/S 是 TypeKind 短名（Int/Char/…），S_u 源符号性，T_u 目标符号性。 */
export interface Bindings {
  T: string;
  S: string;
  S_u: boolean;
  T_u: boolean;
}

type Pred = (b: Bindings) => boolean;

function fatal(msg: string): never {
  process.stderr.write(`cast_matrix: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

// ── 面 A：条件语言 tokenizer + 递归下降求值器 ───────────────────────────
// 条件归一化（孪生两份变量名差异在此抹平）：
//   tk is TK_X → T is X；ik is/ek is TK_X → S is X；
//   inner_u/expr_u → SRC_U；target_type.is_unsigned()/target_ty.is_unsigned() → TGT_U；
//   target_is_fp → (T is Float || T is Double)
type Tok =
  | { t: "(" } | { t: ")" } | { t: "&&" } | { t: "||" } | { t: "!" }
  | { t: "is"; who: "T" | "S"; kind: string }
  | { t: "SRC_U" } | { t: "TGT_U" };

export function normalizeCond(raw: string): string {
  let s = raw.trim();
  s = s.replace(/\b(?:ik|ek) is (TK_\w+)/g, "S is $1");
  s = s.replace(/\btk is (TK_\w+)/g, "T is $1");
  s = s.replace(/\btarget_is_fp\b/g, "(T is TK_Float || T is TK_Double)");
  s = s.replace(/\b(?:inner_u|expr_u)\b/g, "SRC_U");
  s = s.replace(/\b(?:target_type|target_ty)\.is_unsigned\(\)/g, "TGT_U");
  return s;
}

export function tokenize(norm: string): Tok[] {
  const toks: Tok[] = [];
  let i = 0;
  const s = norm;
  while (i < s.length) {
    const rest = s.slice(i);
    if (/\s/.test(rest[0] ?? "")) { i++; continue; }
    if (rest.startsWith("&&")) { toks.push({ t: "&&" }); i += 2; continue; }
    if (rest.startsWith("||")) { toks.push({ t: "||" }); i += 2; continue; }
    if (rest[0] === "(") { toks.push({ t: "(" }); i++; continue; }
    if (rest[0] === ")") { toks.push({ t: ")" }); i++; continue; }
    if (rest[0] === "!") {
      // `!(...)` 形态：! 后必跟 (
      if (rest[1] !== "(") throw new Error(`归一化条件含裸 !（只支持括号否定）: ${norm}`);
      toks.push({ t: "!" }); i++; continue;
    }
    const mIs = /^([TS]) is (TK_\w+)/.exec(rest);
    if (mIs !== null) {
      toks.push({ t: "is", who: mIs[1] === "T" ? "T" : "S", kind: mIs[2] ?? "" });
      i += mIs[0].length;
      continue;
    }
    if (rest.startsWith("SRC_U")) { toks.push({ t: "SRC_U" }); i += 5; continue; }
    if (rest.startsWith("TGT_U")) { toks.push({ t: "TGT_U" }); i += 5; continue; }
    throw new Error(`条件 token 不认识（归一化后）: ${JSON.stringify(rest.slice(0, 30))} ← ${norm}`);
  }
  return toks;
}

/** 递归下降：or := and ('||' and)*；and := unary ('&&' unary)*；unary := '!' prim | prim；prim := '(' or ')' | is | flag */
export function parsePred(norm: string): Pred {
  const toks = tokenize(norm);
  let pos = 0;
  const peek = (): Tok | undefined => toks[pos];
  const eat = (): Tok => {
    const t = toks[pos];
    if (t === undefined) throw new Error(`条件提前结束: ${norm}`);
    pos++;
    return t;
  };
  const prim = (): Pred => {
    const t = eat();
    if (t.t === "(") {
      const p = orExpr();
      const c = eat();
      if (c.t !== ")") throw new Error(`括号不闭合: ${norm}`);
      return p;
    }
    if (t.t === "is") return (b) => (t.who === "T" ? b.T : b.S) === t.kind.slice(3); // TK_Int → Int
    if (t.t === "SRC_U") return (b) => b.S_u;
    if (t.t === "TGT_U") return (b) => b.T_u;
    throw new Error(`条件主语位置出现 ${String(t.t)}: ${norm}`);
  };
  const unary = (): Pred => {
    const t = peek();
    if (t !== undefined && t.t === "!") {
      eat();
      const p = prim();
      return (b) => !p(b);
    }
    return prim();
  };
  const andExpr = (): Pred => {
    let l = unary();
    for (;;) {
      const t = peek();
      if (t !== undefined && t.t === "&&") { eat(); const r = unary(); const ll = l; l = (b) => ll(b) && r(b); }
      else return l;
    }
  };
  const orExpr = (): Pred => {
    let l = andExpr();
    for (;;) {
      const t = peek();
      if (t !== undefined && t.t === "||") { eat(); const r = andExpr(); const ll = l; l = (b) => ll(b) || r(b); }
      else return l;
    }
  };
  const p = orExpr();
  if (pos !== toks.length) throw new Error(`条件尾有多余 token: ${norm}`);
  return p;
}

/** 抽取函数体顶层 if-else 链条件（2 空格缩进；多行条件以 `&&` 续行、`{` 收尾）。 */
export function extractChain(body: string): { conds: string[]; error?: string } {
  const lines = body.split("\n");
  const conds: string[] = [];
  let inCond = false;
  let cur = "";
  for (const line of lines) {
    if (!inCond) {
      // 顶层链首臂 `  if …` 与续臂 `  } else if …`（moon fmt 两空格缩进）
      const m = /^  (?:\} else )?if (.*)$/.exec(line);
      if (m !== null) {
        inCond = true;
        cur = m[1] ?? "";
        if (cur.endsWith("{")) { conds.push(cur.slice(0, -1).trim()); cur = ""; inCond = false; }
      }
    } else {
      cur += " " + line.trim();
      if (cur.endsWith("{")) { conds.push(cur.slice(0, -1).trim()); cur = ""; inCond = false; }
    }
  }
  if (inCond) return { conds, error: `顶层 if-else 链未闭合（尾部）: ${cur}` };
  if (conds.length === 0) return { conds, error: "未找到顶层 if（锚点切片可能失效）" };
  return { conds };
}

export interface Chain {
  name: string;
  preds: Pred[];
  srcPath: string;
  condTexts: string[];
}

export function mustChain(spec: ChainSource): Chain {
  let text: string;
  try {
    text = fs.readFileSync(abs(spec.file), "utf8");
  } catch (e) {
    fatal(`读源失败 ${spec.file}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const i = text.indexOf(spec.anchor_start);
  if (i < 0) fatal(`锚点未命中 ${spec.anchor_start}（${spec.file}）`);
  const rest = text.slice(i + spec.anchor_start.length);
  const mNext = /^fn /m.exec(rest);
  const body = mNext !== null && mNext.index > 0 ? rest.slice(0, mNext.index) : rest;
  const { conds, error } = extractChain(body);
  if (error !== undefined) fatal(`${spec.name}（${spec.file}）: ${error}`);
  const preds: Pred[] = [];
  const condTexts: string[] = [];
  for (const c of conds ?? []) {
    const norm = normalizeCond(c);
    try {
      preds.push(parsePred(norm));
      condTexts.push(norm);
    } catch (e) {
      fatal(`${spec.name} 条件语法不支持（求值器零容忍——扩展求值器前不得静默跳过）: ${c} → ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  return { name: spec.name, preds, srcPath: spec.file, condTexts };
}

/** 源符号性：fp/double/pointer 的 is_unsigned() 恒 false（求值域与引擎一致）。 */
function srcUnsigned(kind: string): boolean[] {
  return kind === "Int" || kind === "Char" || kind === "LongLong" ? [false, true] : [false];
}

export interface ZeroEmitHit {
  key: string;
  T: string;
  S: string;
  S_u: boolean;
}

/** 对全 (T,S,S_u) 组合求值：任一 pred 命中即「有发射」；全不命中 = 零发射。
 *
 * 目标符号性维度（T_u）**不枚举**（审阅 P3 勘误，2026-11-02——原代码此处是
 * `srcUnsigned(T).includes(true) ? false : false` 恒假死表达式）：cast.mbt 两条
 * 顶层链的条件里 TGT_U 只出现在 TK_Char 臂**嵌套**的 TruncByte/TruncUByte 选择
 * （4 空格缩进，不进顶层链抽取），枚举 T_u 两档对命中判定无差别、零判别力；
 * (unsigned) 目标的缺口（R1a-F2 的 `(unsigned)3.9e9` 饱和）由面 B 指令对偶
 * （dual_known_gaps 的 D2U/F2U 族）看守。若未来顶层链引入 TGT_U 条件，须把
 * T_u 纳入求值域（求值器已支持，只差这里展开组合）。 */
export function zeroEmitOf(chain: Chain, kinds: readonly string[]): ZeroEmitHit[] {
  const hits: ZeroEmitHit[] = [];
  for (const T of kinds) {
    for (const S of kinds) {
      for (const S_u of srcUnsigned(S)) {
        const b: Bindings = { T, S, S_u, T_u: false };
        const covered = chain.preds.some((p) => p(b));
        if (!covered) hits.push({ key: `${T}|${S}|${S_u ? "u" : "s"}`, T, S, S_u });
      }
    }
  }
  return hits;
}

// ── 面 B：opcode Cast 指令对偶 ─────────────────────────────────────────
const RE_CAST_INSTR = /^[ \t]*(Cast[A-Z]+2[A-Z]+)$/gm;

export function extractCastInstrs(body: string): string[] {
  const out: string[] = [];
  for (const m of body.matchAll(RE_CAST_INSTR)) out.push(m[1] ?? "");
  return out;
}

/** CastX2Y → [X, Y]（X/Y 为单词段：I/F/D/Q/U/UQ…）。 */
export function instrPair(instr: string): { from: string; to: string } | undefined {
  const m = /^Cast([A-Z]+)2([A-Z]+)$/.exec(instr);
  if (m === null) return undefined;
  return { from: m[1] ?? "", to: m[2] ?? "" };
}

export function main(argv: string[]): number {
  let mode = "check";
  for (const a of argv) {
    if (a === "-check" || a === "--check") mode = "check";
    else if (a === "--discover" || a === "-discover") mode = "discover";
    else if (a === "--selftest" || a === "-selftest") mode = "selftest";
    else if (a === "--report" || a === "-report") mode = "report";
    else fatal(`未知参数: ${a}（可用：-check / --discover / --selftest / --report）`);
  }
  const rd = loadRules();
  const chains = rd.chain_sources.map((s) => mustChain(s));

  if (mode === "discover") {
    for (const c of chains) {
      process.stdout.write(`chain ${c.name}（${c.srcPath}）：${c.preds.length} 个顶层条件\n`);
      for (const h of zeroEmitOf(c, rd.kinds)) process.stdout.write(`  零发射 ${h.key}\n`);
    }
    const opBody = readSlice(rd.opcode_source);
    const instrs = extractCastInstrs(opBody);
    process.stdout.write(`opcode Cast 指令 ${instrs.length} 个: ${instrs.join(" ")}\n`);
    return 0;
  }
  if (mode === "report") {
    for (const c of chains) {
      process.stdout.write(`chain ${c.name}: ${c.preds.length} 条件 → 零发射 ${zeroEmitOf(c, rd.kinds).length} 组合\n`);
    }
  }

  const verdictFn = (): boolean => verdict(rd, chains);
  if (mode === "selftest") return selftestRun(rd, chains);
  if (verdictFn()) {
    process.stdout.write("cast_matrix: PASS（分支链零发射全部在册；opcode 对偶无未登记缺口）\n");
    return 0;
  }
  process.stdout.write("cast_matrix: FAIL——cast 矩阵有未登记缺格（详见上方）\n");
  return 1;
}

function readSlice(spec: { file: string; anchor_start: string; anchor_end: string }): string {
  let text: string;
  try {
    text = fs.readFileSync(abs(spec.file), "utf8");
  } catch (e) {
    fatal(`读源失败 ${spec.file}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const i = text.indexOf(spec.anchor_start);
  if (i < 0) fatal(`锚点未命中 ${spec.anchor_start}（${spec.file}）`);
  const rest = text.slice(i + spec.anchor_start.length);
  const j = spec.anchor_end === "" ? -1 : rest.indexOf(spec.anchor_end);
  return j < 0 ? rest : rest.slice(0, j);
}

/** 面 A + 面 B 全判据。 */
export function verdict(rd: RulesDoc, chains: Chain[]): boolean {
  let ok = true;
  const say = (s: string): void => {
    process.stdout.write(`  ${s}\n`);
  };
  // ── 面 A ──
  const allHitKeys = new Set<string>();
  for (const c of chains) {
    const zs = zeroEmitOf(c, rd.kinds);
    for (const z of zs) allHitKeys.add(`${c.name}::${z.key}`);
    if (c.preds.length === 0) {
      ok = false;
      say(`[空链] ${c.name} 抽取 0 个条件——锚点或链形态已变，拒绝判定`);
    }
    for (const z of zs) {
      const fk = `${c.name}::${z.key}`;
      const inAllowed = rd.zero_emit_allowed[fk] !== undefined;
      const inKnown = rd.zero_emit_known_gaps[fk] !== undefined;
      if (!inAllowed && !inKnown) {
        ok = false;
        say(`[零发射未登记] ${c.name} (${z.key}) = 目标${z.T} ← 源${z.S}${z.S_u ? "(unsigned)" : ""} 全链不命中——零发射（位模式直出/静默丢弃）。合法恒等→zero_emit_allowed 带 reason；缺陷→zero_emit_known_gaps 带 issue`);
      }
    }
  }
  // 僵尸向：表内条目实际已有发射（链演化后忘删）
  for (const [table, label] of [["zero_emit_allowed", "合法白名单"], ["zero_emit_known_gaps", "known 缺口表"]] as const) {
    const tab = table === "zero_emit_allowed" ? rd.zero_emit_allowed : rd.zero_emit_known_gaps;
    for (const key of Object.keys(tab)) {
      const [chainName, combo] = key.split("::");
      if (chainName === undefined || combo === undefined || !chains.some((c) => c.name === chainName)) {
        ok = false;
        say(`[僵尸${label}] ${key} 引用的链 ${String(chainName)} 不存在（改名后忘删）`);
        continue;
      }
      if (!allHitKeys.has(key)) {
        ok = false;
        say(`[僵尸${label}] ${key} 该组合实际已命中发射——修好后忘删条目，清账`);
      }
    }
  }
  // ── 面 B ──
  const opBody = readSlice(rd.opcode_source);
  const instrs = extractCastInstrs(opBody);
  if (instrs.length === 0) {
    ok = false;
    say(`[空集] opcode Cast 指令抽取出 0 个——锚点失效，拒绝判定`);
  }
  const have = new Set(instrs);
  for (const instr of instrs) {
    const pr = instrPair(instr);
    if (pr === undefined) continue;
    const reverse = `Cast${pr.to}2${pr.from}`;
    if (have.has(reverse)) continue;
    const key = `${instr}::${reverse}`;
    const inEx = rd.dual_exemptions[key] !== undefined;
    const inGap = rd.dual_known_gaps[key] !== undefined;
    if (!inEx && !inGap) {
      ok = false;
      say(`[对偶缺口未登记] ${instr} 存在而反向 ${reverse} 缺——位模式通用豁免→dual_exemptions；缺陷→dual_known_gaps 带 issue`);
    }
  }
  for (const [table, label] of [["dual_exemptions", "豁免"], ["dual_known_gaps", "缺口"]] as const) {
    const tab = table === "dual_exemptions" ? rd.dual_exemptions : rd.dual_known_gaps;
    for (const key of Object.keys(tab)) {
      const [fwd, rev] = key.split("::");
      if (fwd === undefined || rev === undefined || !have.has(fwd)) {
        ok = false;
        say(`[僵尸对偶${label}] ${key} 前向指令已不存在（改名/删除后忘删条目）`);
        continue;
      }
      if (have.has(rev ?? "")) {
        ok = false;
        say(`[僵尸对偶${label}] ${key} 反向已存在——缺口修好后忘删条目，清账`);
      }
    }
  }
  return ok;
}

function cloneRules(rd: RulesDoc): RulesDoc {
  return JSON.parse(JSON.stringify(rd)) as RulesDoc;
}

function cloneChains(chains: Chain[]): Chain[] {
  return chains.map((c) => ({ name: c.name, preds: [...c.preds], srcPath: c.srcPath, condTexts: [...c.condTexts] }));
}

/** J9：基线须绿；四路注入（链少一臂→新零发射 / 表加假僵尸 / opcode 删反向臂 / 对偶表假僵尸）。 */
export function selftestRun(rd: RulesDoc, chains: Chain[]): number {
  const quiet = (fn: () => boolean): boolean => {
    const w = process.stdout.write.bind(process.stdout);
    process.stdout.write = (() => true) as typeof process.stdout.write;
    try {
      return fn();
    } finally {
      process.stdout.write = w;
    }
  };
  if (!quiet(() => verdict(rd, chains))) {
    process.stdout.write("cast_matrix: selftest ABORT——基线不绿，注入后的红无法归因\n");
    return 2;
  }
  let fails = 0;
  // 注入①：扫描式杀阵——逐臂试删，至少一个臂的删除须产生未登记零发射（红）；
  // 若任何单臂删除都绿，说明该链零发射看守权完全失守（所有新缺口都被 allowed 吞）
  {
    const first = chains[0];
    if (first === undefined || first.preds.length === 0) return 2;
    let anyRed = false;
    let killed = -1;
    for (let i = 0; i < first.preds.length; i++) {
      const c2 = cloneChains(chains);
      const victim = c2[0];
      if (victim === undefined) return 2;
      victim.preds.splice(i, 1);
      if (!quiet(() => verdict(rd, c2))) {
        anyRed = true;
        killed = i;
        break;
      }
    }
    process.stdout.write(`  注入① 链 ${first.name} 逐臂试删（杀阵扫描，${first.preds.length} 臂）→ ${anyRed ? `红（第 ${String(killed + 1)} 臂删除被捕获）` : "仍绿（闸失效）"}\n`);
    if (!anyRed) fails++;
  }
  // 注入②：合法白名单加一条**实际已发射**的组合（僵尸向——Double|LongLong 当前命中 CastD2Q 臂）
  {
    const rd2 = cloneRules(rd);
    const key = `${chains[0]?.name}::Double|LongLong|s`;
    rd2.zero_emit_allowed[key] = { reason: "僵尸探针" };
    const red = !quiet(() => verdict(rd2, chains));
    process.stdout.write(`  注入② 白名单加已发射组合 ${key} → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  // 注入③：对偶豁免表删一条（→ 未登记缺口）
  {
    const rd2 = cloneRules(rd);
    const firstKey = Object.keys(rd2.dual_exemptions)[0] ?? Object.keys(rd2.dual_known_gaps)[0];
    if (firstKey === undefined) return 2;
    delete (rd2.dual_exemptions[firstKey] !== undefined ? rd2.dual_exemptions : rd2.dual_known_gaps)[firstKey];
    const red = !quiet(() => verdict(rd2, chains));
    process.stdout.write(`  注入③ 对偶表删条目 ${firstKey} → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  // 注入④：known 缺口表加假前向（僵尸向——前向指令不存在）
  {
    const rd2 = cloneRules(rd);
    rd2.dual_known_gaps["CastZ9Z9::CastZ9Z9"] = { reason: "僵尸探针" };
    const red = !quiet(() => verdict(rd2, chains));
    process.stdout.write(`  注入④ known 表加不存在的前向指令 → ${red ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (!red) fails++;
  }
  if (fails > 0) {
    process.stdout.write(`cast_matrix: selftest FAIL——${fails} 路注入未被捕获\n`);
    return 1;
  }
  process.stdout.write("cast_matrix: selftest PASS——四路注入全部捕获（红），J9 证红成立\n");
  return 0;
}

export function loadRules(p = RULES_PATH): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(p), "utf8");
  } catch (e) {
    fatal(`读规则失败（须在仓库根运行）: ${e instanceof Error ? e.message : String(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`规则解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (rd.schema !== 1) fatal(`规则 schema 不支持: ${rd.schema}（期望 1）`);
  return rd;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
