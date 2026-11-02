#!/usr/bin/env node
// teaching_truth —— B11 教学真值源对拍闸（issue #435；审阅 v2 批 B11，2026-11-02）。
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
// 判定原语（六种；两通道统一扫——algorithm_step.description 与 semantic_label）：
//   detect_set            compile.algorithm_matches 的算法名集 == 期望集
//   mod_arithmetic        「计算 X % Y = Z」的 Z == X%Y（算术事实）
//   index_claims_grounded 文案下标/节点/位置声称值 ∈ 源码行下标表达式用帧
//                         local_vars 求值集（∪ 行内字面整数）——数值必须能在
//                         「引擎实际行为」里找到出处，编造即红
//   index_bound           「下标/pivot=N」声称值 ∈ [0, 数组上界]
//   expect_frame / forbid_frame  逐帧稀疏锚（phase±line±vars±desc 正则）
//   root_cause            trap 帧 root_cause_hint.category == 期望
//
// 豁免对账（D19 僵尸审计同款）：失败命中 known → EXPECTED_RED 放行；
// 未登记失败 → RED；known 条目当轮未被命中 → ZOMBIE 红（豁免必须活着）。
//
// 用法（仓库根；前置 `cd moonbit && MOON_CC=clang moon build --target native
// cmd/serve`，exe 新鲜度由 internal/freshness 兜底）：
//   node scripts/teaching_truth/main.mts [--only a,b] [--json] [--no-exempt]
//                                        [--selftest] [--list]
// 退出码：0 全绿（含 EXPECTED_RED 均命中）/ 1 判定红 / 2 规则或前置错误。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";
import { ensureFresh } from "../internal/freshness.mts";

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

/** 声称值提取：下标（arr[N]）/ 节点 N / 位置 N[ 和 M]。 */
export function extractIndexClaims(text: string): number[] {
  const claims: number[] = [];
  for (const m of text.matchAll(/[A-Za-z_][A-Za-z0-9_]*\[(-?\d+)\]/g)) claims.push(Number(m[1]));
  // 「位置 a 和 b」（string_reverse 族 swap 真文案 (i, len-i-1)）与「节点/
  // 顶点 N」（graph 族 u/v 变量值播报）都不是下标声称——不做单行 grounding
  // 判，交给 expect_frame 定点断言与 no_sentinel_minus_one
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
  // a[j+1]=temp 的组语义跨行——单行 grounding 会把组首下标误判无出处）
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

/** 哨兵 -1 直拼：文案出现负下标/负节点（arr[-1] / 节点 -1 / 位置 -1 等）而
 *  源码行字面不含 -1（KMP next[0] = -1 类真字面放行）即红——M34b A3/C2
 *  「变量取不到时 -1 直拼进文案」族 + collector arr[-1]↔arr[0] 形态。 */
export function checkNoSentinelMinusOne(text: string, windowLines: string[]): string | null {
  const neg = /\[-\d+\]|(?:节点|顶点|位置|下标) -\d+/.exec(text);
  if (neg === null) return null;
  if (windowLines.some((l) => l.includes("-1") || /\[-\d+\]/.test(l))) return null;
  return `负哨兵直拼：文案「${text}」（源码窗口无 -1 字面）`;
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
  array_len?: number;
  detect?: string[];
  invariants?: Partial<Record<"mod_arithmetic" | "index_claims_grounded" | "index_bound" | "var_claims" | "no_sentinel_minus_one", boolean>>;
  frames?: FrameExpectation[];
  root_cause?: { category: string; note?: string };
}

export interface DivergenceEntry {
  id: string;
  case: string;
  /** 断言锚：invariant 名或 frames[].id——失败对账键 */
  assertion: string;
  title: string;
  current?: string;
  truth?: string;
  root?: string;
  source: string;
  /** J9 证红锚（七处主红例 true）——selftest 断言其无豁免必红 */
  j9?: boolean;
  /** 失真通道：steps / collector / detect（登记信息，闸不消费） */
  channel?: string;
}

export interface DivergenceRules {
  as_of: string;
  fix_batch: string;
  _doc?: string[];
  entries: DivergenceEntry[];
}

// ── 帧期望匹配 ───────────────────────────────────────────────────────

export function frameMatches(f: StepFrame, e: FrameExpectation): boolean {
  if (f.algorithm_step === null) return false;
  if (f.algorithm_step.phase !== e.phase) return false;
  if (e.line !== undefined && f.code_line !== e.line) return false;
  if (e.vars !== undefined) {
    const m = new Map(f.local_vars.map((v) => [v.name, Number(v.value)] as const));
    for (const [name, want] of Object.entries(e.vars)) {
      if (m.get(name) !== want) return false;
    }
  }
  if (e.desc !== undefined && !new RegExp(e.desc).test(f.algorithm_step.description)) return false;
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
}

export function runServeCase(exe: string, source: string, budget: number): CaseRun {
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
  const r = spawnSync(exe, [], {
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
      | { ok?: boolean; algorithm_matches?: AlgorithmMatch[]; payloads?: StepFrame[] }
      | undefined;
    if (res === undefined) continue;
    if (res.algorithm_matches !== undefined) {
      matches.push(...res.algorithm_matches);
      sawCompile = true;
    }
    if (Array.isArray(res.payloads)) frames.push(...res.payloads);
  }
  if (!sawCompile) throw new Error("compile 响应缺失（algorithm_matches 字段未见）");
  return { matches, frames };
}

// ── 单 case 判定 ─────────────────────────────────────────────────────

export interface Failure {
  case: string;
  assertion: string;
  detail: string;
  /** 同形态（行 + 数字归一文案）聚合计数——逐帧红只报首例 */
  count: number;
}

/** 失败形态键：case + assertion + 行 + 数字归一后的 detail（去 step 号）。 */
export function failureShapeKey(f: { case: string; assertion: string; detail: string }): string {
  const shape = f.detail.replace(/^step \d+ /, "").replace(/\d+/g, "#");
  return `${f.case}\u0000${f.assertion}\u0000${shape}`;
}

export function aggregateFailures(raw: { case: string; assertion: string; detail: string }[]): Failure[] {
  const m = new Map<string, Failure>();
  for (const f of raw) {
    const k = failureShapeKey(f);
    const cur = m.get(k);
    if (cur === undefined) m.set(k, { ...f, count: 1 });
    else cur.count++;
  }
  return [...m.values()];
}

function parseArrayLen(srcLines: string[]): number {
  // 从 main 内数组声明推数组界：`int arr[N] = {...}` / `int arr[N];`
  for (const l of srcLines) {
    const m = /int\s+\w+\s*\[\s*(?:\/\*[^*]*\*\/\s*)?(\d+)\s*\]/.exec(l);
    if (m !== null) return Number(m[1]);
  }
  return -1;
}

export function judgeCase(exp: Expectation, srcLines: string[], run: CaseRun): Failure[] {
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
    const hit = run.frames.some((f) => frameMatches(f, e));
    if (e.kind === "expect" && !hit) {
      failures.push({
        case: c,
        assertion: e.id,
        detail: `期望帧未见：phase=${e.phase}${e.line !== undefined ? ` L${e.line}` : ""}${e.vars !== undefined ? ` vars=${JSON.stringify(e.vars)}` : ""}${e.desc !== undefined ? ` desc~/${e.desc}/` : ""}${e.note !== undefined ? `（${e.note}）` : ""}`,
      });
    }
    if (e.kind === "forbid" && hit) {
      const f = run.frames.find((fr) => frameMatches(fr, e));
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
    if (!fs.existsSync(path.join(dir, name, "expect.json"))) continue;
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
  const ids = new Set<string>();
  for (const e of d.entries) {
    if (!e.id || !e.case || !e.assertion || !e.source) {
      throw new Error(`豁免条目字段缺失: ${JSON.stringify(e).slice(0, 200)}`);
    }
    if (ids.has(`${e.case}\u0000${e.assertion}`)) {
      throw new Error(`豁免条目重复: ${e.case} / ${e.assertion}（${e.id}）——同键多形态须并入同条 detail`);
    }
    ids.add(`${e.case}\u0000${e.assertion}`);
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
}

export function parseArgs(argv: string[]): ParsedArgs | { usage: string } {
  const a: ParsedArgs = { only: "", json: false, noExempt: false, selftest: false, list: false };
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
    else return { usage: `未知参数: ${t}` };
  }
  return a;
}

interface JudgeOutput {
  total: number;
  expectedRed: number;
  reds: { failure: Failure; entry?: DivergenceEntry }[];
  zombies: DivergenceEntry[];
}

/** 全 case 跑判定（不跑 serve 的部分留给纯函数测试；本函数消费 CaseRun）。 */
export function reconcile(
  failures: Failure[],
  divs: DivergenceRules,
  noExempt: boolean,
): JudgeOutput {
  const byKey = new Map<string, DivergenceEntry>(divs.entries.map((e) => [e.case + "\u0000" + e.assertion, e] as const));
  const hitKeys = new Set<string>();
  const reds: { failure: Failure; entry?: DivergenceEntry }[] = [];
  let expectedRed = 0;
  for (const f of failures) {
    const key = `${f.case}\u0000${f.assertion}`;
    const entry = byKey.get(key);
    if (entry !== undefined && !noExempt) {
      hitKeys.add(key);
      expectedRed++;
      continue;
    }
    reds.push({ failure: f, entry });
  }
  const zombies = divs.entries.filter((e) => !hitKeys.has(`${e.case}\u0000${e.assertion}`) && !noExempt);
  return { total: failures.length, expectedRed, reds, zombies };
}

function main(argv: string[]): number {
  const parsed = parseArgs(argv);
  if ("usage" in parsed) {
    process.stdout.write(`teaching_truth: ${parsed.usage}\n用法: node scripts/teaching_truth/main.mts [--only a,b] [--json] [--no-exempt] [--selftest] [--list]\n`);
    return 2;
  }
  const root = projectRoot();
  let cases: LoadedCase[];
  let divs: DivergenceRules;
  try {
    cases = loadCases(root, parsed.only === "" ? [] : parsed.only.split(",").map((s) => s.trim()));
    divs = loadDivergences(root);
  } catch (e) {
    process.stdout.write(`错误: ${e instanceof Error ? e.message : String(e)}\n`);
    return 2;
  }
  if (parsed.list) {
    for (const c of cases) process.stdout.write(`${c.exp.case} — ${c.exp.note ?? ""}（源 ${c.exp.source}）\n`);
    process.stdout.write(`豁免登记 ${divs.entries.length} 条（修复批 ${divs.fix_batch}）\n`);
    return 0;
  }

  const exe = serveExe(root);
  if (!fs.existsSync(exe)) {
    process.stdout.write(`错误: serve exe 不存在: ${exe}\n前置: cd moonbit && MOON_CC=clang moon build --target native cmd/serve\n`);
    return 2;
  }
  ensureFresh("teaching_truth", exe, ["build", "--target", "native", "cmd/serve"]);

  const allFailures: Failure[] = [];
  const runInfo: { c: string; frames: number; annotated: number }[] = [];
  for (const { exp, srcLines } of cases) {
    const src = srcLines.join("\n");
    let run: CaseRun;
    try {
      run = runServeCase(exe, src, exp.step_budget ?? 2000);
    } catch (e) {
      process.stdout.write(`错误: case ${exp.case} serve 跑失败: ${e instanceof Error ? e.message : String(e)}\n`);
      return 2;
    }
    const fs_ = judgeCase(exp, srcLines, run);
    allFailures.push(...fs_);
    runInfo.push({ c: exp.case, frames: run.frames.length, annotated: run.frames.filter((f) => f.algorithm_step !== null).length });
  }

  const out = reconcile(allFailures, divs, parsed.noExempt);
  const lines: string[] = [];
  lines.push(`teaching_truth: ${cases.length} case × 豁免 ${divs.entries.length} 条（修复批 ${divs.fix_batch}）`);
  for (const r of runInfo) lines.push(`  ${r.c}: ${r.frames} 帧 / ${r.annotated} 标注帧`);

  if (parsed.selftest) {
    // J9 自证两步（红例必须全部命中）：
    // ① 无豁免跑：j9 锚定的豁免条目必须全部出现在失败集（豁免真的在挡红）
    // ② 有豁免跑：零红零僵尸（当前状态自洽）
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
    lines.push(`SELFTEST PASS：J9 锚 ${divs.entries.filter((e) => e.j9 === true).length} 条全部命中红例；豁免跑零红零僵尸`);
  }

  for (const { failure } of out.reds) lines.push(`RED  [${failure.case}] ${failure.assertion} ×${failure.count}: ${failure.detail}`);
  for (const z of out.zombies) lines.push(`ZOMBIE 豁免未命中: ${z.id}（${z.case} / ${z.assertion}）——失真已消失？翻面删条目`);
  if (parsed.noExempt) {
    for (const f of allFailures) {
      const e = divs.entries.find((d) => d.case === f.case && d.assertion === f.assertion);
      if (e !== undefined) lines.push(`EXPECTED_RED [${f.case}] ${f.assertion}（${e.id}）×${f.count}: ${f.detail}`);
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
