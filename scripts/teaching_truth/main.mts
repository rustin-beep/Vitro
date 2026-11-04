#!/usr/bin/env node
// teaching_truth —— B11 教学真值源对拍闸（issue #435；审阅 v2 批 B11，2026-11-02；
// PR #453 审阅处置批 2026-11-03：豁免粒度升 shape 级 / J9 锚外置常量 /
// --only 僵尸限定 / 原语有牙自检 / -1 放行词法 / 预算与可达性硬锚）。
//
// 定位：为教学推断器（detect 算法识别 + infer step 帧 label/文案）建立
// **以引擎实际行为为真值**的对拍对象——与 teaching_annotation_diff 的分工：
//   · annotation_diff = 防回归（golden 锁**当前**行为——golden 本身是 Vitro
//     自证历史快照，只能防漂移不能证正确）；
//   · 本闸 = 证正确（期望写**算术事实/算法语义/帧状态可推导的真值**；当前
//     已知失真面经 known_divergences.json 显式豁免，修复批 #436 逐条翻面
//     ——A2 批「双形态锚」先例的机制化形态）。
//
// 真值源（AGENTS 纪律 13「机器判定规则表走 .json 直接入库」）：
//   cases/<name>/expect.json —— 逐帧期望标注（人审真值：算术事实 + 算法语义）
//   cases/<name>/source.c   —— 红例变体语料（正例主干引用 templates/<t>/source.c）
//   known_divergences.json  —— 已知失真面登记（17+ 形态；#436 翻面索引）
//
// 判定原语（七种；两通道统一扫——algorithm_step.description 与 semantic_label）：
//   detect_set            compile.algorithm_matches 的算法名集 == 期望集
//   mod_arithmetic        「计算 X % Y = Z」的 Z == X%Y（算术事实）
//   index_claims_grounded 文案下标声称值 ∈ 源码行下标表达式用帧 local_vars
//                         求值集（∪ 行内字面整数）——数值必须能在「引擎实际
//                         行为」里找到出处，编造即红
//   index_bound           「下标/pivot=N」声称值 ∈ [0, 数组上界]
//   no_sentinel_minus_one 文案负下标/负节点且源码窗口无负字面（词法判定，
//                         n-1/len-1 减法形态不算——PR #453 审阅 P2-4）
//   var_claims            「name=value」与帧同名变量值对拍（当前语料零失真 =
//                         正例不变量；接线由 selftest 原语自检背书）
//   expect_frame / forbid_frame  逐帧稀疏锚（phase±line±vars±desc 正则；forbid
//                         必带 line 且该行帧流可达——安慰性锚结构性不可能）
//   root_cause            trap 帧 root_cause_hint.category == 期望
//
// 豁免对账（D19 僵尸审计同款；粒度 = (case, assertion, shape) 三级——PR #453
// 审阅 P1-1/P2-1 处置）：失败命中 → EXPECTED_RED 放行；同键**新形态**（shape
// 未登记）→ RED；豁免条目/形态当轮未被命中 → ZOMBIE 红（粒度到 shape——
// 部分形态消失即报「N/M 已消失」，翻面收窄或删条目）。invariant 类原语条目
// 必须带 shapes[]；帧锚/detect/root_cause 单形态断言可省（assertion 即粒度）。
//
// J9 锚外置（P2-1 处置）：J9_ANCHORS / CASE_NAMES 常量与豁免表/cases 目录
// 双向对账——锚集合不由被证对象（豁免表/目录）自己定义，删条目/删 case 即红。
//
// 用法（仓库根；前置 `cd moonbit && MOON_CC=clang moon build --target native
// cmd/serve`，exe 新鲜度由 internal/freshness 兜底）：
//   node scripts/teaching_truth/main.mts [--only a,b] [--json] [--no-exempt]
//                                        [--selftest] [--list] [--emit-shapes]
//                                        [--backend-wasm]
// 退出码：0 全绿（含 EXPECTED_RED 均命中）/ 1 判定红 / 2 规则或前置错误。
// --only 的僵尸对账限定到本次跑到的 case 集（局部验证可用——P2-2 处置）；
// --emit-shapes 输出全部失败的 shape 键（豁免回填用，不跑对账）。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";
import { ensureFresh } from "../internal/freshness.mts";

/** J9 证红锚清单（外置常量——P2-1 处置：与豁免表 j9 标记双向对账，
 *  锚集合不得由被证对象自身定义）。B12（#436）完成全部 39 条失真翻面后
 *  语料级红例清零——闸的牙证由 --selftest 的原语有牙自检（合成 fixture
 *  逐原语证红，P2-3「不依赖语料碰巧触发」）持续承担；新失真面再登记
 *  时三处连坐：本常量 + 豁免条目 j9=true + 语料 expect.json。 */
export const J9_ANCHORS: readonly { case: string; assertion: string }[] = [];

/** cases 目录全名清单（selftest 锚定目录数与目录名——缺 expect.json 的
 *  目录 fail loud 而非静默跳过，防锚静默缩水）。 */
export const CASE_NAMES: readonly string[] = [
  "bfs_reset_visited",
  "bfs_std",
  "binary_std",
  "bubble_no_minus_i",
  "bubble_nonadjacent_swap",
  "bubble_std",
  "detect_binary_structural",
  "detect_merge_linkedlist",
  "detect_quick_structural",
  "dfs_reset_visited",
  "gcd_std",
  "gcd_tmp_variant",
  "heap_std",
  "insertion_std",
  "is_prime_std",
  "kmp_std",
  "quick_inline_partition",
  "quick_std",
  "selection_std",
  "string_reverse_print_loop",
  "string_reverse_std",
  "topo_std",
  "trace_offbyone_hint",
];

export interface FrameVar {
  name: string;
  value: string;
}

export interface StepFrame {
  step_index: number;
  code_line: number;
  func_name: string;
  semantic_label: string;
  algorithm_step: {
    algorithm_name: string;
    display_name: string;
    phase: string;
    description: string;
  } | null;
  local_vars: FrameVar[];
  root_cause_hint: { category: string; one_liner: string } | null;
}

export interface AlgorithmMatch {
  name: string;
  func_name: string;
  confidence: number;
  evidence: string;
}

/** 帧的可对拍文本（两通道）。 */
export function frameTexts(f: StepFrame): string[] {
  const ts: string[] = [];
  if (f.algorithm_step !== null) ts.push(f.algorithm_step.description);
  if (f.semantic_label !== "") ts.push(f.semantic_label);
  return ts;
}

// ── 判定原语：mod_arithmetic ─────────────────────────────────────────

export function checkModArithmetic(text: string): string | null {
  const m = /计算 (-?\d+) % (-?\d+) = (-?\d+)/.exec(text);
  if (m === null) return null;
  const a = Number(m[1]);
  const b = Number(m[2]);
  const c = Number(m[3]);
  // JS % 与 C 同号语义（截断除），算术事实直接对拍
  if (a % b !== c) {
    return `算式失真：${text}（真值 ${a} % ${b} = ${a % b}）`;
  }
  return null;
}

// ── 判定原语：index_claims_grounded ──────────────────────────────────

/** 简单下标表达式求值：标识符 / 整数 / + - * 与括号（arr[j+1]、len-i-1 等）。
 *  求不出（变量不在帧 local_vars / 非整数形态）返回 null。 */
export function evalIndexExpr(expr: string, vars: Map<string, number>): number | null {
  const cleaned = expr.replace(/\s+/g, "");
  if (!/^[A-Za-z0-9_+\-*/()]+$/.test(cleaned)) return null;
  const matched = cleaned.match(/[A-Za-z_][A-Za-z0-9_]*|\d+|[+\-*/()]/g);
  if (matched === null || matched.length === 0) return null;
  const tokens: string[] = matched;
  let pos = 0;
  function parseExpr(): number | null {
    let v = parseTerm();
    if (v === null) return null;
    while (pos < tokens.length) {
      const op = tokens[pos];
      if (op !== "+" && op !== "-") break;
      pos++;
      const r = parseTerm();
      if (r === null) return null;
      v = op === "+" ? v + r : v - r;
    }
    return v;
  }
  function parseTerm(): number | null {
    let v = parseUnary();
    if (v === null) return null;
    while (pos < tokens.length) {
      const op = tokens[pos];
      if (op !== "*" && op !== "/") break;
      pos++;
      const r = parseUnary();
      if (r === null) return null;
      if (op === "*") v *= r;
      else {
        if (r === 0) return null;
        v = Math.trunc(v / r);
      }
    }
    return v;
  }
  function parseUnary(): number | null {
    if (pos < tokens.length && tokens[pos] === "-") {
      pos++;
      const v = parseUnary();
      return v === null ? null : -v;
    }
    return parsePrimary();
  }
  function parsePrimary(): number | null {
    const t = tokens[pos];
    if (t === undefined) return null;
    if (t === "(") {
      pos++;
      const v = parseExpr();
      if (v === null || tokens[pos] !== ")") return null;
      pos++;
      return v;
    }
    if (/^\d+$/.test(t)) {
      pos++;
      return Number(t);
    }
    if (/^[A-Za-z_]/.test(t)) {
      pos++;
      const v = vars.get(t);
      return v === undefined ? null : v;
    }
    return null;
  }
  const v = parseExpr();
  return v === null || pos !== tokens.length ? null : v;
}

/** 源码行的 grounding 集：所有 `<name>[expr]` 下标表达式求值 ∪ 行内字面整数。 */
export function lineGrounding(srcLine: string, vars: Map<string, number>): { values: Set<number>; idxExprs: string[] } {
  const values = new Set<number>();
  const idxExprs: string[] = [];
  for (const m of srcLine.matchAll(/([A-Za-z_][A-Za-z0-9_]*)\[([^\][]+)\]/g)) {
    const expr = m[2] ?? "";
    idxExprs.push(expr);
    const v = evalIndexExpr(expr, vars);
    if (v !== null) values.add(v);
  }
  for (const m of srcLine.matchAll(/(?<!\w)(-?\d+)(?!\w)/g)) {
    values.add(Number(m[1]));
  }
  return { values, idxExprs };
}

/** 声称值提取：带数组名的下标声称（arr[N]）。「位置 a 和 b」（string 族真
 *  文案跨表达式推导）与「节点/顶点 N」（graph 族 u/v 变量值播报）不是下标
 *  声称——不判 grounding，交给 expect_frame 定点断言与 no_sentinel_minus_one。 */
export function extractIndexClaims(text: string): number[] {
  const claims: number[] = [];
  for (const m of text.matchAll(/[A-Za-z_][A-Za-z0-9_]*\[(-?\d+)\]/g)) claims.push(Number(m[1]));
  return claims;
}

export function checkIndexClaimsGrounded(
  text: string,
  windowLines: string[],
  vars: Map<string, number>,
): string | null {
  const claims = extractIndexClaims(text);
  if (claims.length === 0) return null;
  // grounding 窗口 = 当前行 + 前两行（三行交换组 temp=a[j]; a[j]=a[j+1];
  // a[j+1]=temp 的组语义跨行——单行 grounding 会把组首下标误判无出处）。
  // PR #463 审阅 P2-1：求值源保持帧末态单源（不为回溯/假比较类语句放宽
  // 到行入口态——审阅实证 39 条翻面里仅 KMP 2 条依赖入口值，已按处方 b
  // 改文案不拼下标数字；「本行任一时刻出现过的值」当出处会放走新旧值
  // 混用——恰是 M34b A2/A4 的病根）。
  const values = new Set<number>();
  const idxExprs: string[] = [];
  for (const l of windowLines) {
    const g = lineGrounding(l, vars);
    for (const v of g.values) values.add(v);
    idxExprs.push(...g.idxExprs);
  }
  const srcLine = windowLines[windowLines.length - 1] ?? "";
  for (const c of claims) {
    if (!values.has(c)) {
      const grounding = [...values].sort((x, y) => x - y).join(", ");
      return `下标声称 ${c} 无出处：文案「${text}」；源码行「${srcLine.trim()}」下标表达式 [${idxExprs.join(" ; ")}] 求值/字面集 = {${grounding === "" ? "空" : grounding}}`;
    }
  }
  return null;
}

// ── 判定原语：no_sentinel_minus_one ──────────────────────────────────

/** 源码窗口含**负数字面**（词法判定，PR #453 审阅 P2-4 处置——裸子串
 *  includes("-1") 会被 n-1/len-1 等减法形态整族免疫）。放行形态：
 *  `= -1` / `(…, -1` / `return -1`（负字面赋值/传参/返回）与 `[-1]`（负下标
 *  字面，如 next[0] = -1 的对拍行）。`n-1`/`len - 1` 的负号前是标识符 →
 *  是减法，不放行。 */
export function lineHasNegativeLiteral(line: string): boolean {
  if (/\[\s*-\d+\s*\]/.test(line)) return true;
  return /(?:[=(,]|\breturn)\s*-\d+/.test(line);
}

/** 哨兵 -1 直拼：文案出现负下标/负节点（arr[-1] / 节点 -1 等）而源码窗口
 *  无负数字面即红——M34b A3/C2「变量取不到时 -1 直拼进文案」族 +
 *  collector arr[-1]↔arr[0] 形态。 */
export function checkNoSentinelMinusOne(text: string, windowLines: string[]): string | null {
  const neg = /\[-\d+\]|(?:节点|顶点|位置|下标) -\d+/.exec(text);
  if (neg === null) return null;
  if (windowLines.some((l) => lineHasNegativeLiteral(l))) return null;
  return `负哨兵直拼：文案「${text}」（源码窗口无负数字面）`;
}

// ── 判定原语：index_bound ────────────────────────────────────────────

export function checkIndexBound(text: string, arrayLen: number): string | null {
  // 只判「下标声称」形态（落位下标 pivot=N / 下标 N / 节点·顶点 N）——
  // collector 变量播报「循环 … pivot=50」是变量真值非下标声称，不在此判
  for (const m of text.matchAll(/(?:落位下标 pivot=|下标 |节点 |顶点 )(-?\d+)/g)) {
    const v = Number(m[1]);
    if (v < 0 || v >= arrayLen) {
      return `下标越界声称 ${v}：文案「${text}」（数组界 [0, ${arrayLen - 1}]）`;
    }
  }
  return null;
}

// ── 判定原语：变量声称对拍（name=value 形态，vars 同名才判——别名半边不判，M34b C1 另行登记）──

export function checkVarClaims(text: string, vars: Map<string, number>): string | null {
  for (const m of text.matchAll(/([A-Za-z_][A-Za-z0-9_]*)=(-?\d+)/g)) {
    const name = m[1] ?? "";
    const claimed = Number(m[2]);
    const actual = vars.get(name);
    if (actual !== undefined && actual !== claimed) {
      return `变量声称 ${name}=${claimed} 与帧实际 ${name}=${actual} 不符：文案「${text}」`;
    }
  }
  return null;
}

// ── 期望规则类型 ─────────────────────────────────────────────────────

export interface FrameExpectation {
  id: string;
  kind: "expect" | "forbid";
  phase: string;
  /** forbid 必填（可达性锚：帧流该行须有帧，否则「安慰性锚」红）；
   *  expect 可选。 */
  line?: number;
  vars?: Record<string, number>;
  desc?: string;
  note?: string;
}

export interface Expectation {
  case: string;
  source: string;
  note?: string;
  step_budget?: number;
  /** 预算锚开关（缺省 true）：trap 族语料终结后 step.next 恒产幽灵帧且
   *  finished 恒 false（M31 A-2 形态，另案处置）——预算锚对该族无效。 */
  budget_check?: boolean;
  array_len?: number;
  detect?: string[];
  invariants?: Partial<Record<"mod_arithmetic" | "index_claims_grounded" | "index_bound" | "var_claims" | "no_sentinel_minus_one", boolean>>;
  frames?: FrameExpectation[];
  root_cause?: { category: string; note?: string };
}

export interface DivergenceEntry {
  id: string;
  case: string;
  /** 断言锚：invariant 名或 frames[].id——失败对账键（第二级） */
  assertion: string;
  /** 第三级对账键：该豁免覆盖的失真形态清单（invariant 类原语必填——
   *  同 (case, assertion) 键下出现清单外新形态即红；帧锚/detect/root_cause
   *  单形态断言可省 = assertion 即粒度）。值 = failureShape() 输出。 */
  shapes?: string[];
  title: string;
  current?: string;
  truth?: string;
  root?: string;
  source: string;
  /** J9 证红锚（七处主红例 true）——与 J9_ANCHORS 常量双向对账 */
  j9?: boolean;
  /** 失真通道：steps / collector / detect（登记信息，闸不消费） */
  channel?: string;
}

export interface DivergenceRules {
  as_of: string;
  /** 在册豁免所属修复批（issue 号）；null = 翻面完成态（entries 须空）。
   *  PR #463 审阅 P3-2：字段必填（缺键/类型错 fail loud——此前删字段后
   *  输出「修复批 undefined」无人察觉）。 */
  fix_batch: string | null;
  _doc?: string[];
  entries: DivergenceEntry[];
}

/** invariant 类原语（多形态）——豁免条目必须带 shapes（粒度强制）。 */
export const INVARIANT_ASSERTIONS: readonly string[] = [
  "mod_arithmetic",
  "index_claims_grounded",
  "index_bound",
  "no_sentinel_minus_one",
  "var_claims",
];

// ── 失败形态（shape）──────────────────────────────────────────────────

export interface Failure {
  case: string;
  assertion: string;
  detail: string;
  /** 同形态聚合计数——逐帧红只报首例 */
  count: number;
  /** 失真指纹（对账第三级）：行号保留、其余数字归一、grounding 尾巴剥除
   *  （其元素集随帧态漂，非失真指纹）。 */
  shape: string;
}

/** 失真指纹：detail 剥 step 号与「；源码行…」grounding 尾巴，保 L<行号>，
 *  其余数字归一 #——PR #453 审阅 P1-1/P3-2 处置（行号参与 shape，豁免
 *  粒度 = case+assertion+shape 三级）。 */
export function failureShape(detail: string): string {
  const stripped = detail.replace(/^step \d+ /, "").split("；源码行")[0] ?? "";
  // 单趟归一：L<行号> token 保留（行参与失真指纹），纯数字归一 #
  return stripped.replace(/L\d+|\d+/g, (tok) => (tok.startsWith("L") ? tok : "#"));
}

/** 聚合键（case, assertion, shape 全键）。 */
export function failureShapeKey(f: { case: string; assertion: string; detail: string }): string {
  return `${f.case}\u0000${f.assertion}\u0000${failureShape(f.detail)}`;
}

export function aggregateFailures(raw: { case: string; assertion: string; detail: string }[]): Failure[] {
  const m = new Map<string, Failure>();
  for (const f of raw) {
    const k = failureShapeKey(f);
    const cur = m.get(k);
    if (cur === undefined) m.set(k, { ...f, count: 1, shape: failureShape(f.detail) });
    else cur.count++;
  }
  return [...m.values()];
}

// ── 帧期望匹配 ───────────────────────────────────────────────────────

export function frameMatches(f: StepFrame, e: FrameExpectation, reCache?: Map<string, RegExp>): boolean {
  if (f.algorithm_step === null) return false;
  if (f.algorithm_step.phase !== e.phase) return false;
  if (e.line !== undefined && f.code_line !== e.line) return false;
  if (e.vars !== undefined) {
    const m = new Map(f.local_vars.map((v) => [v.name, Number(v.value)] as const));
    for (const [name, want] of Object.entries(e.vars)) {
      if (m.get(name) !== want) return false;
    }
  }
  if (e.desc !== undefined) {
    let re: RegExp;
    if (reCache !== undefined) {
      const hit = reCache.get(e.desc);
      if (hit !== undefined) re = hit;
      else {
        re = new RegExp(e.desc);
        reCache.set(e.desc, re);
      }
    } else {
      re = new RegExp(e.desc);
    }
    if (!re.test(f.algorithm_step.description)) return false;
  }
  return true;
}

// ── serve 驱动（annotation_diff 同款批量形态） ────────────────────────

interface RespLine {
  id?: number;
  result?: unknown;
  error?: unknown;
}

export function serveExe(root: string): string {
  const override = process.env["VITRO_SERVE_MB"];
  if (override !== undefined && override !== "") return override;
  return path.join(root, "moonbit", "_build", "native", "debug", "build", "cmd", "serve", "serve.exe");
}

export interface CaseRun {
  matches: AlgorithmMatch[];
  frames: StepFrame[];
  /** 末个 step.next 响应的 finished——budget 耗尽仍未完即判定红（覆盖不全
   *  的判定不可信，PR #453 审阅 P3-4 处置）。 */
  finished: boolean;
}

export function runServeCase(exe: string, source: string, budget: number, nodeShell = false): CaseRun {
  const lines: string[] = [];
  let id = 0;
  id++;
  lines.push(JSON.stringify({ id, method: "compile", params: { source } }));
  id++;
  lines.push(`{"id": ${id}, "method": "run"}`);
  id++;
  lines.push(`{"id": ${id}, "method": "step.begin"}`);
  for (let i = 0; i < budget; i++) {
    id++;
    lines.push(`{"id": ${id}, "method": "step.next"}`);
  }
  // nodeShell：wasm 臂——统一入口壳形态 `node <shell> serve`
  const r = nodeShell
    ? spawnSync("node", [exe, "serve"], {
        input: lines.join("\n") + "\n",
        encoding: "utf8",
        timeout: 120_000,
        maxBuffer: 64 * 1024 * 1024,
      })
    : spawnSync(exe, [], {
    input: lines.join("\n") + "\n",
    encoding: "utf8",
    timeout: 120_000,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (r.error !== undefined) throw new Error(`serve 启动失败: ${String(r.error)}`);
  if (r.stdout === undefined) throw new Error("serve 无 stdout");
  const matches: AlgorithmMatch[] = [];
  const frames: StepFrame[] = [];
  let sawCompile = false;
  let finished = false;
  for (const line of r.stdout.split("\n")) {
    if (line.trim() === "") continue;
    let resp: RespLine;
    try {
      resp = JSON.parse(line) as RespLine;
    } catch {
      throw new Error(`响应行非 JSON: ${line.slice(0, 200)}`);
    }
    if (resp.error !== undefined && resp.error !== null) {
      throw new Error(`serve 错误帧 (id=${resp.id ?? -1}): ${JSON.stringify(resp.error).slice(0, 300)}`);
    }
    const res = resp.result as
      | { ok?: boolean; algorithm_matches?: AlgorithmMatch[]; payloads?: StepFrame[]; finished?: boolean }
      | undefined;
    if (res === undefined) continue;
    if (res.algorithm_matches !== undefined) {
      matches.push(...res.algorithm_matches);
      sawCompile = true;
    }
    if (Array.isArray(res.payloads)) frames.push(...res.payloads);
    if (res.finished === true) finished = true;
  }
  if (!sawCompile) throw new Error("compile 响应缺失（algorithm_matches 字段未见）");
  return { matches, frames, finished };
}

// ── 单 case 判定 ─────────────────────────────────────────────────────

/** 数组界推导：`T name[N]`（N 数字或 #define 宏名）；多数组程序取**最大**
 *  界（保守——只用 max 判越界不误报，多数组小界越界归 expect 定点锚）。
 *  推不出返回 -1（index_bound 静默关 + 运行输出可见化）。 */
export function parseArrayLen(srcLines: string[]): number {
  const defines = new Map<string, number>();
  for (const l of srcLines) {
    const dm = /#\s*define\s+(\w+)\s+(\d+)\b/.exec(l);
    if (dm !== null) defines.set(dm[1] ?? "", Number(dm[2]));
  }
  let best = -1;
  for (const l of srcLines) {
    for (const m of l.matchAll(/\b(?:int|char|long|short|unsigned|double|float|[A-Za-z_]\w*)\s+(\w+)\s*\[\s*(\w+)\s*\]/g)) {
      const sizeTok = m[2] ?? "";
      let n = Number(sizeTok);
      if (!Number.isInteger(n) || n <= 0) n = defines.get(sizeTok) ?? -1;
      if (n > best) best = n;
    }
  }
  return best;
}

export function judgeCase(exp: Expectation, srcLines: string[], run: CaseRun, reCache?: Map<string, RegExp>): Failure[] {
  const failures: { case: string; assertion: string; detail: string }[] = [];
  const c = exp.case;
  const inv = {
    mod_arithmetic: true,
    index_claims_grounded: true,
    index_bound: true,
    var_claims: true,
    no_sentinel_minus_one: true,
    ...exp.invariants,
  };
  const arrayLen = exp.array_len ?? parseArrayLen(srcLines);
  const lineHit = new Map<number, boolean>();
  for (const f of run.frames) lineHit.set(f.code_line, true);

  if (exp.detect !== undefined) {
    const actual = [...new Set(run.matches.map((m) => m.name))].sort();
    const want = [...exp.detect].sort();
    if (actual.join(",") !== want.join(",")) {
      failures.push({
        case: c,
        assertion: "detect_set",
        detail: `算法识别集失真：实际 [${actual.join(", ")}] vs 真值 [${want.join(", ")}]（全部命中：${run.matches.map((m) => `${m.name}@${m.func_name}(${m.evidence})`).join("; ")}）`,
      });
    }
  }

  for (const f of run.frames) {
    const line = f.code_line >= 1 && f.code_line <= srcLines.length ? (srcLines[f.code_line - 1] ?? "") : "";
    const vars = new Map<string, number>();
    for (const v of f.local_vars) {
      const n = Number(v.value);
      if (Number.isFinite(n)) vars.set(v.name, n);
    }
    for (const text of frameTexts(f)) {
      if (inv.mod_arithmetic) {
        const msg = checkModArithmetic(text);
        if (msg !== null) failures.push({ case: c, assertion: "mod_arithmetic", detail: `step ${f.step_index} L${f.code_line}: ${msg}` });
      }
      if (inv.index_claims_grounded && line !== "") {
        const w0 = f.code_line >= 3 ? (srcLines[f.code_line - 3] ?? "") : "";
        const w1 = f.code_line >= 2 ? (srcLines[f.code_line - 2] ?? "") : "";
        const msg = checkIndexClaimsGrounded(text, [w0, w1, line], vars);
        if (msg !== null) failures.push({ case: c, assertion: "index_claims_grounded", detail: `step ${f.step_index} L${f.code_line}: ${msg}` });
      }
      if (inv.no_sentinel_minus_one) {
        const w0 = f.code_line >= 3 ? (srcLines[f.code_line - 3] ?? "") : "";
        const w1 = f.code_line >= 2 ? (srcLines[f.code_line - 2] ?? "") : "";
        const msg = checkNoSentinelMinusOne(text, [w0, w1, line]);
        if (msg !== null) failures.push({ case: c, assertion: "no_sentinel_minus_one", detail: `step ${f.step_index} L${f.code_line}: ${msg}` });
      }
      if (inv.index_bound && arrayLen > 0) {
        const msg = checkIndexBound(text, arrayLen);
        if (msg !== null) failures.push({ case: c, assertion: "index_bound", detail: `step ${f.step_index} L${f.code_line}: ${msg}` });
      }
      if (inv.var_claims) {
        const msg = checkVarClaims(text, vars);
        if (msg !== null) failures.push({ case: c, assertion: "var_claims", detail: `step ${f.step_index} L${f.code_line}: ${msg}` });
      }
    }
  }

  for (const e of exp.frames ?? []) {
    // forbid 可达性锚（P3-3 处置）：行零帧 = 安慰性锚（恒绿锁），结构性红
    if (e.kind === "forbid" && e.line !== undefined && !lineHit.get(e.line)) {
      failures.push({
        case: c,
        assertion: e.id,
        detail: `forbid 锚行不可达：L${e.line} 在帧流中零帧（安慰性锚——场景不可达时删锚或换语料）${e.note !== undefined ? `（${e.note}）` : ""}`,
      });
      continue;
    }
    const hit = run.frames.some((f) => frameMatches(f, e, reCache));
    if (e.kind === "expect" && !hit) {
      failures.push({
        case: c,
        assertion: e.id,
        detail: `期望帧未见：phase=${e.phase}${e.line !== undefined ? ` L${e.line}` : ""}${e.vars !== undefined ? ` vars=${JSON.stringify(e.vars)}` : ""}${e.desc !== undefined ? ` desc~/${e.desc}/` : ""}${e.note !== undefined ? `（${e.note}）` : ""}`,
      });
    }
    if (e.kind === "forbid" && hit) {
      const f = run.frames.find((fr) => frameMatches(fr, e, reCache));
      failures.push({
        case: c,
        assertion: e.id,
        detail: `禁止帧出现：phase=${e.phase}${e.line !== undefined ? ` L${e.line}` : ""} —— 实例 step ${f?.step_index ?? -1}: ${f?.algorithm_step?.description ?? ""}${e.note !== undefined ? `（${e.note}）` : ""}`,
      });
    }
  }

  if (exp.root_cause !== undefined) {
    const traps = run.frames.filter((f) => f.root_cause_hint !== null);
    const okCat = traps.some((f) => f.root_cause_hint?.category === exp.root_cause?.category);
    if (!okCat) {
      failures.push({
        case: c,
        assertion: "root_cause",
        detail: `trap 根因失真：期望 category=${exp.root_cause?.category}，实际 [${traps.map((f) => `${f.root_cause_hint?.category}「${f.root_cause_hint?.one_liner.slice(0, 60)}」`).join("; ")}]`,
      });
    }
  }

  // 预算锚（P3-4 处置）：budget 耗尽程序未跑完 = 覆盖不全，判定不可信即红
  if (run.finished !== true && exp.budget_check !== false) {
    failures.push({
      case: c,
      assertion: "step_budget_exhausted",
      detail: `预算耗尽语料未跑完（step_budget=${exp.step_budget ?? 2000}，末响应 finished=false）——加大 step_budget 否则覆盖不全判定不可信`,
    });
  }

  return aggregateFailures(failures);
}

// ── 用例加载 ─────────────────────────────────────────────────────────

export interface LoadedCase {
  exp: Expectation;
  srcLines: string[];
}

export function loadCases(root: string, only: string[]): LoadedCase[] {
  const dir = path.join(root, "scripts", "teaching_truth", "cases");
  const names: string[] = [];
  for (const name of fs.readdirSync(dir).sort()) {
    if (!fs.statSync(path.join(dir, name)).isDirectory()) continue;
    // 缺 expect.json = 规则错误 fail loud（P2-1 处置：不再静默跳过——防
    // J9 锚随目录残缺而静默缩水）
    if (!fs.existsSync(path.join(dir, name, "expect.json"))) {
      throw new Error(`case 目录缺 expect.json: ${name}（规则错误——补齐或删目录，勿静默跳过）`);
    }
    if (only.length > 0 && !only.includes(name)) continue;
    names.push(name);
  }
  if (names.length === 0) throw new Error("cases 目录为空（或 --only 全部落空）");
  const out: LoadedCase[] = [];
  for (const name of names) {
    const expPath = path.join(dir, name, "expect.json");
    let exp: Expectation;
    try {
      exp = JSON.parse(fs.readFileSync(expPath, "utf8")) as Expectation;
    } catch (e) {
      throw new Error(`${expPath} 坏 JSON: ${e instanceof Error ? e.message : String(e)}`);
    }
    if (exp.case !== name) throw new Error(`${expPath} case 字段 "${exp.case}" 与目录名 "${name}" 不符`);
    const srcPath = exp.source.startsWith("templates/")
      ? path.join(root, exp.source)
      : path.join(dir, name, exp.source);
    if (!fs.existsSync(srcPath)) throw new Error(`语料缺失: ${exp.source} → ${srcPath}`);
    // desc 正则预校验（P3-4 处置：非法正则 fail loud，不等到帧匹配才炸）
    for (const e of exp.frames ?? []) {
      if (e.desc !== undefined) {
        try {
          new RegExp(e.desc);
        } catch (err) {
          throw new Error(`${expPath} frames[].desc 非法正则 "${e.desc}": ${err instanceof Error ? err.message : String(err)}`);
        }
      }
      if (e.kind === "forbid" && e.line === undefined) {
        throw new Error(`${expPath} frames[] forbid "${e.id}" 缺 line（forbid 须带行可达性锚）`);
      }
    }
    const srcLines = fs.readFileSync(srcPath, "utf8").split("\n");
    out.push({ exp, srcLines });
  }
  return out;
}

export function loadDivergences(root: string): DivergenceRules {
  const p = path.join(root, "scripts", "teaching_truth", "known_divergences.json");
  let d: DivergenceRules;
  try {
    d = JSON.parse(fs.readFileSync(p, "utf8")) as DivergenceRules;
  } catch (e) {
    throw new Error(`known_divergences.json 读失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (!Array.isArray(d.entries)) throw new Error("known_divergences.json 缺 entries 数组");
  // P3-2 fail loud：as_of/fix_batch 必填（fix_batch=null 表翻面完成态——
  // entries 须为空，有豁免却无批次号 = 半改状态）
  if (typeof d.as_of !== "string" || d.as_of === "") throw new Error("known_divergences.json 缺 as_of");
  if (d.fix_batch === undefined) throw new Error("known_divergences.json 缺 fix_batch（string=在册豁免批次 / null=翻面完成）");
  if (d.fix_batch === null && d.entries.length > 0) {
    throw new Error("known_divergences.json fix_batch=null 但 entries 非空——翻面完成态不应有在册豁免");
  }
  if (typeof d.fix_batch === "string" && d.fix_batch !== "" && d.entries.length === 0) {
    throw new Error("known_divergences.json fix_batch 在册但 entries 空——豁免全翻面后应置 null");
  }
  const ids = new Set<string>();
  for (const e of d.entries) {
    if (!e.id || !e.case || !e.assertion || !e.source) {
      throw new Error(`豁免条目字段缺失: ${JSON.stringify(e).slice(0, 200)}`);
    }
    const key = `${e.case}\u0000${e.assertion}`;
    if (ids.has(key)) {
      throw new Error(`豁免条目重复: ${e.case} / ${e.assertion}（${e.id}）——同键多形态并入同条 shapes`);
    }
    ids.add(key);
    if (e.shapes !== undefined) {
      if (!Array.isArray(e.shapes) || e.shapes.length === 0) {
        throw new Error(`豁免条目 ${e.id} shapes 须非空数组（无形态拆分需求则删字段）`);
      }
      if (new Set(e.shapes).size !== e.shapes.length) {
        throw new Error(`豁免条目 ${e.id} shapes 有重复`);
      }
    } else if (INVARIANT_ASSERTIONS.includes(e.assertion)) {
      throw new Error(`豁免条目 ${e.id}（${e.case} / ${e.assertion}）是 invariant 类原语——必须带 shapes（同键新形态静默放行 = P1-1 病）`);
    }
  }
  return d;
}

// ── main ─────────────────────────────────────────────────────────────

export interface ParsedArgs {
  only: string;
  json: boolean;
  noExempt: boolean;
  selftest: boolean;
  list: boolean;
  emitShapes: boolean;
  /** wasm 臂（PR #463 审阅 P3-5）：被测物切统一入口壳 vitro_wasm.js 的
   *  serve 子命令（与 teaching_annotation_diff --backend-wasm 同款形态），
   *  真值锚不再单压 native 臂。 */
  backendWasm: boolean;
}

export function parseArgs(argv: string[]): ParsedArgs | { usage: string } {
  const a: ParsedArgs = { only: "", json: false, noExempt: false, selftest: false, list: false, emitShapes: false, backendWasm: false };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i] ?? "";
    if (t === "--only") {
      const v = argv[++i];
      if (v === undefined) return { usage: "--only 需参数（逗号分隔 case 名）" };
      a.only = v;
    } else if (t === "--json") a.json = true;
    else if (t === "--no-exempt") a.noExempt = true;
    else if (t === "--selftest") a.selftest = true;
    else if (t === "--list") a.list = true;
    else if (t === "--emit-shapes") a.emitShapes = true;
    else if (t === "-backend-wasm" || t === "--backend-wasm") a.backendWasm = true;
    else return { usage: `未知参数: ${t}` };
  }
  return a;
}

export interface ZombieReport {
  entry: DivergenceEntry;
  /** 未命中的形态（shapes 级；无 shapes 条目为 null = 整条未命中） */
  missedShapes: string[] | null;
}

export interface JudgeOutput {
  total: number;
  expectedRed: number;
  reds: { failure: Failure; entry?: DivergenceEntry }[];
  zombies: ZombieReport[];
}

/** 豁免对账（三级键 = case + assertion + shape；P1-1/P2-2 处置）。
 *  ranCases：本次实际跑到的 case 集（--only 局部跑时僵尸判定限定其中，
 *  其余条目不参与——否则局部验证被全量僵尸堵死）。 */
export function reconcile(
  failures: Failure[],
  divs: DivergenceRules,
  noExempt: boolean,
  ranCases?: Set<string>,
): JudgeOutput {
  const byKey = new Map<string, DivergenceEntry>(divs.entries.map((e) => [e.case + "\u0000" + e.assertion, e] as const));
  const hitShapes = new Map<string, Set<string>>();
  const reds: { failure: Failure; entry?: DivergenceEntry }[] = [];
  let expectedRed = 0;
  for (const f of failures) {
    const key = `${f.case}\u0000${f.assertion}`;
    const entry = byKey.get(key);
    if (entry !== undefined && !noExempt) {
      let s = hitShapes.get(key);
      if (s === undefined) {
        s = new Set<string>();
        hitShapes.set(key, s);
      }
      if (entry.shapes === undefined || entry.shapes.includes(f.shape)) {
        s.add(f.shape);
        expectedRed++;
        continue;
      }
      // 同键**新形态**：shape 级未登记——豁免键粗于失真粒度的静默放行被禁
      reds.push({ failure: f, entry });
      continue;
    }
    reds.push({ failure: f, entry });
  }
  const zombies: ZombieReport[] = [];
  if (!noExempt) {
    for (const e of divs.entries) {
      if (ranCases !== undefined && !ranCases.has(e.case)) continue; // P2-2：--only 局部跑不判全量僵尸
      const key = `${e.case}\u0000${e.assertion}`;
      const hits = hitShapes.get(key);
      if (hits === undefined) {
        zombies.push({ entry: e, missedShapes: null });
        continue;
      }
      if (e.shapes !== undefined) {
        const missed = e.shapes.filter((s) => !hits.has(s));
        if (missed.length > 0) {
          zombies.push({ entry: e, missedShapes: missed });
        }
      }
    }
  }
  return { total: failures.length, expectedRed, reds, zombies };
}

// ── selftest：原语有牙自检（P2-3 处置——不依赖语料碰巧触发，合成
//    fixture 逐原语证红；var_claims 当前语料零失真 = 正例不变量，接线
//    由此背书） ────────────────────────────────────────────────────────

function selfcheckFrame(over: Partial<StepFrame>): StepFrame {
  return {
    step_index: 1,
    code_line: 3,
    func_name: "f",
    semantic_label: "",
    algorithm_step: null,
    local_vars: [],
    root_cause_hint: null,
    ...over,
  };
}

export function runPrimitiveSelfcheck(): string[] {
  const problems: string[] = [];
  const cases: { prim: string; exp: Expectation; srcLines: string[]; run: CaseRun }[] = [
    {
      prim: "mod_arithmetic",
      exp: { case: "sc", source: "./s.c" },
      srcLines: ["int main() {", "  int t = a % b;", "}"],
      run: { matches: [], frames: [selfcheckFrame({ algorithm_step: { algorithm_name: "gcd", display_name: "", phase: "mod", description: "计算 4 % 3 = 3" } })], finished: true },
    },
    {
      prim: "index_claims_grounded",
      exp: { case: "sc", source: "./s.c" },
      srcLines: ["int main() {", "  int x = 0, j = 2;", "  arr[i] = arr[j];", "}"],
      run: {
        matches: [],
        frames: [selfcheckFrame({ code_line: 3, local_vars: [{ name: "i", value: "0" }, { name: "j", value: "2" }], algorithm_step: { algorithm_name: "b", display_name: "", phase: "swap", description: "交换 arr[5]↔arr[6]" } })],
        finished: true,
      },
    },
    {
      prim: "index_bound",
      exp: { case: "sc", source: "./s.c", array_len: 5 },
      srcLines: ["int arr[5];"],
      run: { matches: [], frames: [selfcheckFrame({ algorithm_step: { algorithm_name: "q", display_name: "", phase: "partition_init", description: "落位下标 pivot=9" } })], finished: true },
    },
    {
      prim: "no_sentinel_minus_one",
      exp: { case: "sc", source: "./s.c" },
      srcLines: ["int main() {", "  arr[j + 1] = key;", "}"],
      run: { matches: [], frames: [selfcheckFrame({ code_line: 2, algorithm_step: { algorithm_name: "i", display_name: "", phase: "swap", description: "交换 arr[-1]↔arr[0]" } })], finished: true },
    },
    {
      prim: "var_claims",
      exp: { case: "sc", source: "./s.c" },
      srcLines: ["int main() {"],
      run: { matches: [], frames: [selfcheckFrame({ local_vars: [{ name: "b", value: "18" }], algorithm_step: { algorithm_name: "g", display_name: "", phase: "loop", description: "辗转相除：b=7" } })], finished: true },
    },
    {
      prim: "expect_frame",
      exp: { case: "sc", source: "./s.c", frames: [{ id: "sc_e", kind: "expect", phase: "compare", vars: { i: 1, j: 3 } }] },
      srcLines: ["int main() {"],
      run: { matches: [], frames: [selfcheckFrame({ algorithm_step: { algorithm_name: "b", display_name: "", phase: "compare", description: "比较 arr[0] 与 arr[1]" } })], finished: true },
    },
    {
      prim: "detect_set",
      exp: { case: "sc", source: "./s.c", detect: ["is_prime"] },
      srcLines: ["int main() {"],
      run: { matches: [{ name: "prim_mst", func_name: "isPrime", confidence: 85, evidence: "name" }], frames: [], finished: true },
    },
    {
      prim: "root_cause",
      exp: { case: "sc", source: "./s.c", root_cause: { category: "OffByOne" } },
      srcLines: ["int main() {"],
      run: { matches: [], frames: [selfcheckFrame({ root_cause_hint: { category: "WrongInit", one_liner: "x" } })], finished: true },
    },
    {
      prim: "forbid_frame",
      exp: { case: "sc", source: "./s.c", frames: [{ id: "sc_f", kind: "forbid", phase: "swap", line: 2 }] },
      srcLines: ["int main() {", "  arr[j] = temp;", "}"],
      run: { matches: [], frames: [selfcheckFrame({ code_line: 2, algorithm_step: { algorithm_name: "b", display_name: "", phase: "swap", description: "交换 arr[0]↔arr[1]" } })], finished: true },
    },
  ];
  for (const c of cases) {
    const failures = judgeCase(c.exp, c.srcLines, c.run);
    if (!failures.some((f) => f.assertion === c.prim || f.assertion === "sc_e" || f.assertion === "sc_f")) {
      problems.push(`原语 ${c.prim} 自检未红（合成失真 fixture 未被抓住——接线断链）`);
    }
  }
  return problems;
}

function main(argv: string[]): number {
  const parsed = parseArgs(argv);
  if ("usage" in parsed) {
    process.stdout.write(`teaching_truth: ${parsed.usage}\n用法: node scripts/teaching_truth/main.mts [--only a,b] [--json] [--no-exempt] [--selftest] [--list] [--emit-shapes]\n`);
    return 2;
  }
  const root = projectRoot();
  let cases: LoadedCase[];
  let divs: DivergenceRules;
  try {
    cases = loadCases(root, parsed.only === "" ? [] : parsed.only.split(",").map((s) => s.trim()));
    // --emit-shapes 是豁免回填通道（shapes 尚未写进表时使用）——不加载豁免表
    divs = parsed.emitShapes
      ? { as_of: "", fix_batch: "", entries: [] }
      : loadDivergences(root);
  } catch (e) {
    process.stdout.write(`错误: ${e instanceof Error ? e.message : String(e)}\n`);
    return 2;
  }
  if (parsed.list) {
    for (const c of cases) process.stdout.write(`${c.exp.case} — ${c.exp.note ?? ""}（源 ${c.exp.source}）\n`);
    const fb = divs.fix_batch === null ? "翻面完成，无在册豁免" : divs.fix_batch;
    process.stdout.write(`豁免登记 ${divs.entries.length} 条（${fb}）\n`);
    return 0;
  }

  // wasm 臂（PR #463 审阅 P3-5）：被测物切统一入口壳——与
  // teaching_annotation_diff --backend-wasm 同款（ensureFresh 双产物）。
  let exe = serveExe(root);
  let nodeShell = false;
  if (parsed.backendWasm) {
    const shell = path.join(root, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_wasm", "vitro_wasm.js");
    const wasmMod = path.join(root, "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm");
    if (!fs.existsSync(shell)) {
      process.stdout.write(`错误: wasm 臂产物缺失 ${shell}（统一入口壳）\n前置: cd moonbit && MOON_CC=clang moon build --release --target js cmd/vitro_wasm\n`);
      return 2;
    }
    ensureFresh("teaching_truth_wasm", wasmMod, ["build", "--release", "--target", "wasm-gc", "gateway/wasm"]);
    ensureFresh("teaching_truth_glue", shell, ["build", "--release", "--target", "js", "cmd/vitro_wasm"]);
    exe = shell;
    nodeShell = true;
  } else {
    if (!fs.existsSync(exe)) {
      process.stdout.write(`错误: serve exe 不存在: ${exe}\n前置: cd moonbit && MOON_CC=clang moon build --target native cmd/serve\n`);
      return 2;
    }
    ensureFresh("teaching_truth", exe, ["build", "--target", "native", "cmd/serve"]);
  }

  const allFailures: Failure[] = [];
  const runInfo: { c: string; frames: number; annotated: number; bound: string }[] = [];
  const reCache = new Map<string, RegExp>();
  for (const { exp, srcLines } of cases) {
    const src = srcLines.join("\n");
    let run: CaseRun;
    try {
      run = runServeCase(exe, src, exp.step_budget ?? 2000, nodeShell);
    } catch (e) {
      process.stdout.write(`错误: case ${exp.case} serve 跑失败: ${e instanceof Error ? e.message : String(e)}\n`);
      return 2;
    }
    const fs_ = judgeCase(exp, srcLines, run, reCache);
    allFailures.push(...fs_);
    const len = exp.array_len ?? parseArrayLen(srcLines);
    runInfo.push({
      c: exp.case,
      frames: run.frames.length,
      annotated: run.frames.filter((f) => f.algorithm_step !== null).length,
      bound: `index_bound=${len > 0 ? String(len) : "off(无数组界)"}`,
    });
  }

  // --emit-shapes：输出全部失败形态键（豁免回填用），不跑对账
  if (parsed.emitShapes) {
    for (const f of allFailures) {
      process.stdout.write(`${f.case}\t${f.assertion}\t${f.shape}\t×${f.count}\n`);
    }
    return 0;
  }

  const ranCases = new Set(cases.map((c) => c.exp.case));
  const out = reconcile(allFailures, divs, parsed.noExempt, ranCases);
  const lines: string[] = [];
  const fbMain = divs.fix_batch === null ? "翻面完成，无在册豁免" : `修复批 ${divs.fix_batch}`;
  lines.push(`teaching_truth: ${cases.length} case × 豁免 ${divs.entries.length} 条（${fbMain}）`);
  for (const r of runInfo) lines.push(`  ${r.c}: ${r.frames} 帧 / ${r.annotated} 标注帧 / ${r.bound}`);

  if (parsed.selftest) {
    // J9 自证四步（P2-1/P2-3 处置后形态）：
    // ① 锚外置对账：J9_ANCHORS 常量 ↔ 豁免表 j9 标记双向一致；CASE_NAMES ↔ cases 目录双向一致
    // ② 原语有牙自检：合成 fixture 逐原语证红（接线不由语料碰巧性背书）
    // ③ 无豁免跑：J9 锚 (case, assertion) 必须全部出现在失败集
    // ④ 有豁免跑：零红零僵尸
    const anchorProblems: string[] = [];
    const j9InRules = divs.entries.filter((e) => e.j9 === true).map((e) => `${e.case}\u0000${e.assertion}`);
    for (const a of J9_ANCHORS) {
      if (!j9InRules.includes(`${a.case}\u0000${a.assertion}`)) anchorProblems.push(`J9_ANCHORS 常量条目不在豁免表（j9=true）: ${a.case} / ${a.assertion}`);
    }
    for (const k of j9InRules) {
      if (!J9_ANCHORS.some((a) => `${a.case}\u0000${a.assertion}` === k)) anchorProblems.push(`豁免表 j9=true 条目不在 J9_ANCHORS 常量: ${k.replace("\u0000", " / ")}`);
    }
    for (const n of cases.map((c) => c.exp.case)) {
      if (!CASE_NAMES.includes(n)) anchorProblems.push(`cases 目录 "${n}" 不在 CASE_NAMES 常量（新增 case 须三处连坐：目录 + 常量 + 豁免表按需）`);
    }
    for (const n of CASE_NAMES) {
      if (!ranCases.has(n) && parsed.only === "") anchorProblems.push(`CASE_NAMES 常量条目 "${n}" 不在 cases 目录`);
    }
    anchorProblems.push(...runPrimitiveSelfcheck());
    if (anchorProblems.length > 0) {
      process.stdout.write(`SELFTEST FAIL（锚外置对账/原语自检 ${anchorProblems.length} 条）:\n`);
      for (const p of anchorProblems) process.stdout.write(`  ${p}\n`);
      return 1;
    }
    const missing = divs.entries.filter((e) => e.j9 === true && !allFailures.some((f) => f.case === e.case && f.assertion === e.assertion));
    if (missing.length > 0) {
      process.stdout.write(`SELFTEST FAIL（J9 红例未命中 ${missing.length} 条）:\n`);
      for (const e of missing) process.stdout.write(`  ${e.id}: ${e.case} / ${e.assertion}\n`);
      return 1;
    }
    if (out.reds.length > 0 || out.zombies.length > 0) {
      process.stdout.write("SELFTEST FAIL（有豁免跑存在未登记红/僵尸豁免——见上）\n");
      return 1;
    }
    // PR #463 审阅 P2-2：J9 锚清零后不再称「全部命中红例」（空集恒真——
    // D21 同族：通过条件与打印路数不一致）；如实报告语料级红例数与
    // 原语自检数（牙证的实际承担者）。
    if (J9_ANCHORS.length > 0) {
      lines.push(`SELFTEST PASS：J9 锚 ${J9_ANCHORS.length} 条（外置常量对账一致）全部命中红例；原语自检 9 项全红；豁免跑零红零僵尸`);
    } else {
      lines.push(`SELFTEST PASS：语料级红例 0 条（39 条失真已全数翻面，J9 锚随翻面清零——外置常量对账一致）；闸的牙证由原语自检 9 项全红承担；豁免跑零红零僵尸`);
    }
  }

  for (const { failure } of out.reds) lines.push(`RED  [${failure.case}] ${failure.assertion} ×${failure.count} shape「${failure.shape}」: ${failure.detail}`);
  for (const z of out.zombies) {
    if (z.missedShapes === null) {
      lines.push(`ZOMBIE 豁免未命中: ${z.entry.id}（${z.entry.case} / ${z.entry.assertion}）——失真已消失？翻面删条目`);
    } else {
      lines.push(`ZOMBIE 形态已消失（${z.entry.shapes?.length ?? 0} 中 ${z.missedShapes.length} 个）: ${z.entry.id}——翻面收窄 shapes 或删条目：${z.missedShapes.map((s) => `「${s}」`).join(" ")}`);
    }
  }
  if (parsed.noExempt) {
    for (const f of allFailures) {
      const e = divs.entries.find((d) => d.case === f.case && d.assertion === f.assertion);
      if (e !== undefined) lines.push(`EXPECTED_RED [${f.case}] ${f.assertion}（${e.id}）×${f.count} shape「${f.shape}」: ${f.detail}`);
    }
  } else {
    lines.push(`期望红（已豁免待翻面）${out.expectedRed} / 未登记红 ${out.reds.length} / 僵尸 ${out.zombies.length}`);
  }

  if (parsed.json) {
    process.stdout.write(
      JSON.stringify(
        {
          cases: cases.length,
          failures: allFailures.length,
          expected_red: out.expectedRed,
          reds: out.reds.map((r) => r.failure),
          zombies: out.zombies,
        },
        null,
        2,
      ) + "\n",
    );
  } else {
    process.stdout.write(lines.join("\n") + "\n");
  }
  return out.reds.length > 0 || out.zombies.length > 0 ? 1 : 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
