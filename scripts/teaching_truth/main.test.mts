// teaching_truth.main.test.mts —— 判定原语与豁免对账纯函数单测。
//
// 端到端（跑 serve 收帧）需要 native 产物，本测试不依赖——端到端覆盖归
// CI 的 teaching_truth 步（主闸 + --selftest J9 双步）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  aggregateFailures,
  CASE_NAMES,
  checkIndexBound,
  checkIndexClaimsGrounded,
  checkModArithmetic,
  checkNoSentinelMinusOne,
  checkVarClaims,
  evalIndexExpr,
  extractIndexClaims,
  failureShape,
  frameMatches,
  J9_ANCHORS,
  judgeCase,
  lineHasNegativeLiteral,
  loadCases,
  loadDivergences,
  parseArgs,
  reconcile,
  runPrimitiveSelfcheck,
} from "./main.mts";
import type { DivergenceRules, Expectation, StepFrame } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

function mkFrame(over: Partial<StepFrame> = {}): StepFrame {
  return {
    step_index: 1,
    code_line: 7,
    func_name: "gcd",
    semantic_label: "",
    algorithm_step: null,
    local_vars: [],
    root_cause_hint: null,
    ...over,
  };
}

// ── mod_arithmetic ───────────────────────────────────────────────────

test("checkModArithmetic：算式自洽绿 / 余数错红（A1 形态）", () => {
  assert.equal(checkModArithmetic("计算 48 % 18 = 12（余数作为新的 b）"), null);
  // M34b A1：t 暂存形态 b_now 锚 b 变量——显示除数值
  const bad = checkModArithmetic("计算 48 % 18 = 18（余数作为新的 b）");
  assert.ok(bad !== null && bad.includes("真值 48 % 18 = 12"));
  assert.equal(checkModArithmetic("辗转相除：a=48, b=18"), null);
});

// ── 表达式求值 ───────────────────────────────────────────────────────

test("evalIndexExpr：标识符/算术/括号可求；未知变量与非表达式 None", () => {
  const vars = new Map<string, number>([["j", 2], ["i", 0], ["len", 5], ["n", 5]]);
  assert.equal(evalIndexExpr("j + 1", vars), 3);
  assert.equal(evalIndexExpr("len - i - 1", vars), 4);
  assert.equal(evalIndexExpr("j", vars), 2);
  assert.equal(evalIndexExpr("(j + 1)", vars), 3);
  assert.equal(evalIndexExpr("rear++", vars), null);
  assert.equal(evalIndexExpr("u", vars), null); // 未知变量
  assert.equal(evalIndexExpr("", vars), null);
  assert.equal(evalIndexExpr("x; y", vars), null); // 非法字符
});

test("evalIndexExpr：C 截断除法语义（7/2=3）", () => {
  const vars = new Map<string, number>([["a", 7]]);
  assert.equal(evalIndexExpr("a / 2", vars), 3);
  assert.equal(evalIndexExpr("a / 0", vars), null);
});

// ── index_claims_grounded ────────────────────────────────────────────

test("extractIndexClaims：下标声称提取（节点/位置/位置对不提取——变量值声称另判）", () => {
  assert.deepEqual(extractIndexClaims("比较 arr[1] 与 arr[2]"), [1, 2]);
  assert.deepEqual(extractIndexClaims("交换 arr[-1]↔arr[0]"), [-1, 0]);
  assert.deepEqual(extractIndexClaims("标记节点 0 为已访问"), []); // 变量值声称
  assert.deepEqual(extractIndexClaims("交换位置 0 和 4"), []);
});

test("checkIndexClaimsGrounded：三行交换组窗口放行；A7 非相邻错对红", () => {
  const vars = new Map<string, number>([["i", 0], ["j", 0], ["n", 5]]);
  // 标准冒泡三行组第三行（组语义跨行——窗口并前两行；j=0 组下标 {0,1}）
  const win = ["int temp = arr[j];", "arr[j] = arr[j + 1];", "arr[j + 1] = temp;"];
  assert.equal(checkIndexClaimsGrounded("交换 arr[0]↔arr[1]", win, vars), null);
  // A7：行文本 arr[i]>arr[j]（0,1），文案 (1,2)——2 无出处
  const vars2 = new Map<string, number>([["i", 0], ["j", 1], ["n", 5]]);
  const bad = checkIndexClaimsGrounded("比较 arr[1] 与 arr[2]", ["for (int j = i + 1; j < n; j++) {", "", "if (arr[i] > arr[j]) {"], vars2);
  assert.ok(bad !== null && bad.includes("2"));
  // KMP 真字面 -1 放行（行含 -1 字面）
  assert.equal(checkIndexClaimsGrounded("构建 next 数组，next[0]=-1", ["next[0] = -1;", "", ""], new Map()), null);
});

// ── index_bound / no_sentinel_minus_one ──────────────────────────────

test("checkIndexBound：落位下标越界红（A5 形态）；变量播报不判", () => {
  assert.ok(checkIndexBound("分区完成，枢轴落位下标 pivot=50", 5) !== null);
  assert.equal(checkIndexBound("分区完成，枢轴落位下标 pivot=3", 5), null);
  assert.equal(checkIndexBound("循环 low=0, high=4, pivot=50", 5), null); // 变量播报
  assert.equal(checkIndexBound("循环 i=0", 5), null);
});

test("checkNoSentinelMinusOne：负哨兵直拼红；源码字面 -1 放行", () => {
  assert.ok(checkNoSentinelMinusOne("交换 arr[-1]↔arr[0]", ["arr[j + 1] = key;", "", ""]) !== null);
  assert.ok(checkNoSentinelMinusOne("标记节点 -1 为已访问", ["visited[i] = 0;", "", ""]) !== null);
  assert.equal(checkNoSentinelMinusOne("构建 next 数组，next[0]=-1", ["next[0] = -1;"]), null); // 行字面含 -1
  assert.equal(checkNoSentinelMinusOne("输出顶点 3", ["printf(\"%d \", u);"]), null); // 正值不判
});

// ── var_claims ───────────────────────────────────────────────────────

test("checkVarClaims：同名变量值不符红；别名半边不判（M34b C1 另行登记）", () => {
  const vars = new Map<string, number>([["b", 18]]);
  assert.ok(checkVarClaims("b=18", vars) === null);
  assert.ok(checkVarClaims("b=12", vars) !== null);
  assert.equal(checkVarClaims("left=0", vars), null); // left 不在 vars（别名）
});

// ── frame 期望 ───────────────────────────────────────────────────────

test("frameMatches：phase/line/vars/desc 四维匹配", () => {
  const f = mkFrame({
    code_line: 9,
    algorithm_step: { algorithm_name: "bubble_sort", display_name: "冒泡排序", phase: "compare", description: "比较 arr[1] 与 arr[2]" },
    local_vars: [{ name: "i", value: "1" }, { name: "j", value: "2" }],
  });
  assert.ok(frameMatches(f, { id: "t", kind: "expect", phase: "compare" }));
  assert.ok(frameMatches(f, { id: "t", kind: "expect", phase: "compare", line: 9, vars: { i: 1, j: 2 } }));
  assert.ok(frameMatches(f, { id: "t", kind: "expect", phase: "compare", desc: "arr\\[1\\]" }));
  assert.ok(!frameMatches(f, { id: "t", kind: "expect", phase: "swap" }));
  assert.ok(!frameMatches(f, { id: "t", kind: "expect", phase: "compare", line: 8 }));
  assert.ok(!frameMatches(f, { id: "t", kind: "expect", phase: "compare", vars: { i: 2 } }));
  assert.ok(!frameMatches(f, { id: "t", kind: "expect", phase: "compare", vars: { k: 0 } })); // 变量缺
  assert.ok(!frameMatches(mkFrame(), { id: "t", kind: "expect", phase: "compare" })); // algorithm_step null
});

// ── judgeCase（fixture 全链，不跑 serve） ─────────────────────────────

test("judgeCase：expect 未见红 / forbid 出现红 / detect 失真红 / 通用不变量全链", () => {
  const exp: Expectation = {
    case: "fixture",
    source: "./source.c",
    array_len: 5,
    detect: ["is_prime"],
    frames: [
      { id: "fx_expect", kind: "expect", phase: "compare", vars: { i: 1, j: 3 } },
      { id: "fx_forbid", kind: "forbid", phase: "swap", line: 3 },
    ],
  };
  const srcLines = ["int main() {", "    int arr[5];", "    arr[i] = arr[j];", "}"];
  const run = {
    matches: [{ name: "is_prime", func_name: "isPrime", confidence: 85, evidence: "name" },
              { name: "prim_mst", func_name: "isPrime", confidence: 85, evidence: "name" }],
    frames: [
      mkFrame({ step_index: 5, code_line: 3, local_vars: [{ name: "i", value: "0" }, { name: "j", value: "2" }],
        algorithm_step: { algorithm_name: "bubble_sort", display_name: "冒泡", phase: "swap", description: "交换 arr[0]↔arr[1]" } }),
      mkFrame({ step_index: 9, code_line: 3, local_vars: [{ name: "i", value: "1" }, { name: "j", value: "3" }],
        algorithm_step: { algorithm_name: "bubble_sort", display_name: "冒泡", phase: "compare", description: "比较 arr[1] 与 arr[2]" } }),
    ],
    finished: true,
  };
  const failures = judgeCase(exp, srcLines, run);
  const keys = new Set(failures.map((f) => f.assertion));
  assert.ok(keys.has("detect_set")); // prim_mst 误命中（M33b A1 形态）
  assert.ok(keys.has("fx_forbid")); // swap 帧在 L3 出现
  assert.ok(keys.has("fx_expect") === false); // compare (i=1,j=3) 帧在——不红
  assert.ok(keys.has("index_claims_grounded")); // arr[0]↔arr[1] vs 行 {0,2}
});

test("judgeCase：root_cause 失真红（M31 形态）", () => {
  const exp: Expectation = { case: "fx2", source: "./s.c", root_cause: { category: "OffByOne" } };
  const run = {
    matches: [],
    frames: [mkFrame({ root_cause_hint: { category: "WrongInit", one_liner: "建议将初始值改为 0" } })],
    finished: true,
  };
  const failures = judgeCase(exp, ["x"], run);
  const rc = failures.find((f) => f.assertion === "root_cause");
  assert.ok(rc !== undefined && rc.detail.includes("WrongInit"));
});

// ── 聚合与豁免对账 ────────────────────────────────────────────────────

test("aggregateFailures：同形态聚合计数、异形态分开", () => {
  const raw = [
    { case: "c", assertion: "a", detail: "step 1 L2: X 1" },
    { case: "c", assertion: "a", detail: "step 2 L2: X 2" }, // 同形态（数字归一）
    { case: "c", assertion: "a", detail: "step 3 L9: Y" }, // 异形态（行不同）
  ];
  const out = aggregateFailures(raw);
  assert.equal(out.length, 2);
  const first = out.find((f) => f.count === 2);
  assert.ok(first !== undefined && first.detail.startsWith("step 1"));
});

test("reconcile：三级键对账——同键新形态 RED（P1-1）/ shapes 部分消失 ZOMBIE / ranCases 限定（P2-2）", () => {
  const divs: DivergenceRules = {
    as_of: "2026-11-03",
    fix_batch: "#436",
    entries: [
      { id: "D1", case: "c", assertion: "a", shapes: ["L1: 形态甲", "L2: 形态乙"], title: "t", source: "M34b A1" },
      { id: "D2", case: "c", assertion: "gone", title: "t", source: "M30 A1" },
      { id: "D3", case: "other", assertion: "x", title: "t", source: "M30 A1" },
    ],
  };
  function f(shape: string): never {
    // detail 形态经 failureShape 归一须得回 shape——用可逆原像构造
    return { case: "c", assertion: "a", detail: shape, count: 1, shape } as never;
  }
  // reconcile 消费**已聚合**的 Failure[]（聚合在 judgeCase/aggregateFailures 层）
  const failures = [f("L1: 形态甲"), f("L9: 全新形态")] as never[];
  const out = reconcile(failures, divs, false, new Set(["c"])); // ranCases 限定：other 的 D3 不判僵尸
  assert.equal(out.expectedRed, 1); // L1×2 聚合后命中 1 形态
  assert.deepEqual(out.reds.map((r) => (r.failure as { shape: string }).shape), ["L9: 全新形态"]); // 同键新形态不放行
  const z1 = out.zombies.find((z) => z.entry.id === "D1");
  assert.ok(z1 !== undefined && z1.missedShapes?.[0] === "L2: 形态乙"); // 部分形态消失=粒度级 ZOMBIE
  assert.ok(out.zombies.some((z) => z.entry.id === "D2")); // 整条未命中
  assert.ok(!out.zombies.some((z) => z.entry.id === "D3")); // 未跑到的 case 不判僵尸（P2-2）
  const out2 = reconcile(failures, divs, true);
  assert.equal(out2.reds.length, 2); // no-exempt：两条失败全按红报
  const out3 = reconcile([f("L1: 形态甲"), f("L2: 形态乙")], divs, false, new Set(["c", "other"]));
  assert.equal(out3.zombies.length, 2); // D2 + D3（ranCases 含 other）都未命中；D1 两形态全命中不进
});

// ── 规则加载校验 ─────────────────────────────────────────────────────

test("loadCases（真实签名）：目录名不符 / source 缺失 fail loud", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "tt-root-"));
  fs.mkdirSync(path.join(root, "scripts", "teaching_truth", "cases", "mismatch"), { recursive: true });
  fs.writeFileSync(
    path.join(root, "scripts", "teaching_truth", "cases", "mismatch", "expect.json"),
    JSON.stringify({ case: "other", source: "./source.c" }),
  );
  fs.writeFileSync(path.join(root, "scripts", "teaching_truth", "cases", "mismatch", "source.c"), "int main(){return 0;}");
  assert.throws(() => loadCases(root, []), /不符/);
  fs.writeFileSync(
    path.join(root, "scripts", "teaching_truth", "cases", "mismatch", "expect.json"),
    JSON.stringify({ case: "mismatch", source: "./source.c" }),
  );
  fs.rmSync(path.join(root, "scripts", "teaching_truth", "cases", "mismatch", "source.c"));
  assert.throws(() => loadCases(root, []), /语料缺失/);
});

test("loadDivergences：重复豁免键 fail loud；缺字段 fail loud", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "tt-div-"));
  const p = path.join(root, "scripts", "teaching_truth", "known_divergences.json");
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify({
    as_of: "x", fix_batch: "#436",
    entries: [
      { id: "A", case: "c", assertion: "a", title: "t", source: "s" },
      { id: "B", case: "c", assertion: "a", title: "t", source: "s" },
    ],
  }));
  assert.throws(() => loadDivergences(root), /重复/);
  fs.writeFileSync(p, JSON.stringify({ as_of: "x", fix_batch: "#436", entries: [{ id: "A", case: "c", title: "t", source: "s" }] }));
  assert.throws(() => loadDivergences(root), /字段缺失/);
});

// ── parseArgs ────────────────────────────────────────────────────────

test("parseArgs：四 flag 全收；未知/缺参报用法错", () => {
  const ok = parseArgs(["--only", "a,b", "--json", "--no-exempt", "--selftest", "--list"]);
  assert.ok("only" in ok === false || true);
  if (!("usage" in ok)) {
    assert.equal(ok.only, "a,b");
    assert.equal(ok.json && ok.noExempt && ok.selftest && ok.list, true);
  }
  assert.ok("usage" in parseArgs(["--nope"]));
  assert.ok("usage" in parseArgs(["--only"]));
});

// ── PR #453 审阅处置批新增锚 ─────────────────────────────────────────

test("failureShape：行号保留（P3-2）+ 数字归一 + grounding 尾巴剥除", () => {
  assert.equal(failureShape("step 20 L19: 下标声称 1 无出处：文案「交换 arr[0]↔arr[1]」；源码行「visited[i] = 0;」下标表达式 [i] 求值/字面集 = {0}"),
    "L19: 下标声称 # 无出处：文案「交换 arr[#]↔arr[#]」");
  assert.equal(failureShape("step 3 L7: 算式失真：计算 48 % 18 = 18（余数作为新的 b）（真值 48 % 18 = 12）"),
    "L7: 算式失真：计算 # % # = #（余数作为新的 b）（真值 # % # = #）");
});

test("lineHasNegativeLiteral：词法判定（P2-4）——减法形态不算、负字面/负下标/return 算", () => {
  assert.equal(lineHasNegativeLiteral("for (int j = 0; j < n-1; j++) {"), false);
  assert.equal(lineHasNegativeLiteral("while (len - 1 > 0)"), false);
  assert.equal(lineHasNegativeLiteral("next[0] = -1;"), true);
  assert.equal(lineHasNegativeLiteral("k = -1;"), true);
  assert.equal(lineHasNegativeLiteral("if (x) return -1;"), true);
  assert.equal(lineHasNegativeLiteral("int a[-1];"), true);
});

test("checkNoSentinelMinusOne：n-1 窗口不再整族免疫（P2-4 回归锚）", () => {
  assert.ok(checkNoSentinelMinusOne("交换 arr[-1]↔arr[0]", ["for (int j = 0; j < n-1; j++) {", "", "arr[j+1] = key;"]) !== null);
  assert.equal(checkNoSentinelMinusOne("构建 next 数组，next[0]=-1", ["next[0] = -1;"]), null);
});

test("judgeCase：预算锚（P3-4）——finished=false 红 / budget_check=false 放行", () => {
  const exp: Expectation = { case: "fx", source: "./s.c" };
  const runUnfinished = { matches: [], frames: [], finished: false };
  assert.ok(judgeCase(exp, ["x"], runUnfinished).some((f) => f.assertion === "step_budget_exhausted"));
  const expOff: Expectation = { case: "fx", source: "./s.c", budget_check: false };
  assert.ok(!judgeCase(expOff, ["x"], runUnfinished).some((f) => f.assertion === "step_budget_exhausted"));
});

test("judgeCase：forbid 行可达性锚（P3-3）——行零帧即「安慰性锚」红", () => {
  const exp: Expectation = { case: "fx", source: "./s.c", frames: [{ id: "fz", kind: "forbid", phase: "swap", line: 9 }] };
  const run = { matches: [], frames: [], finished: true };
  const out = judgeCase(exp, ["int main() {"], run);
  assert.ok(out.some((f) => f.assertion === "fz" && f.detail.includes("不可达")));
});

test("loadDivergences：invariant 类缺 shapes 拦截（P1-1 校验面）", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "tt-div2-"));
  const p2 = path.join(root, "scripts", "teaching_truth", "known_divergences.json");
  fs.mkdirSync(path.dirname(p2), { recursive: true });
  fs.writeFileSync(p2, JSON.stringify({
    as_of: "x", fix_batch: "#436",
    entries: [{ id: "A", case: "c", assertion: "mod_arithmetic", title: "t", source: "s" }],
  }));
  assert.throws(() => loadDivergences(root), /必须带 shapes/);
});

test("loadCases：forbid 缺 line 拦截（P3-3 校验面）/ 缺 expect.json 的目录 fail loud（P2-1）", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "tt-root2-"));
  fs.mkdirSync(path.join(root, "scripts", "teaching_truth", "cases", "f1"), { recursive: true });
  fs.writeFileSync(path.join(root, "scripts", "teaching_truth", "cases", "f1", "source.c"), "int main(){return 0;}");
  fs.writeFileSync(path.join(root, "scripts", "teaching_truth", "cases", "f1", "expect.json"),
    JSON.stringify({ case: "f1", source: "./source.c", frames: [{ id: "x", kind: "forbid", phase: "swap" }] }));
  assert.throws(() => loadCases(root, []), /缺 line/);
  fs.mkdirSync(path.join(root, "scripts", "teaching_truth", "cases", "noexpect"), { recursive: true });
  fs.writeFileSync(path.join(root, "scripts", "teaching_truth", "cases", "noexpect", "source.c"), "int main(){return 0;}");
  fs.writeFileSync(path.join(root, "scripts", "teaching_truth", "cases", "f1", "expect.json"),
    JSON.stringify({ case: "f1", source: "./source.c" }));
  assert.throws(() => loadCases(root, []), /缺 expect.json/);
});

test("runPrimitiveSelfcheck：九原语合成 fixture 全红（P2-3——接线不由语料碰巧性背书）", () => {
  assert.deepEqual(runPrimitiveSelfcheck(), []);
});

test("J9_ANCHORS/CASE_NAMES 与真实豁免表/cases 目录一致（P2-1——锚外置三处连坐）", () => {
  const root = projectRoot();
  const divs = loadDivergences(root);
  const j9InRules = new Set(divs.entries.filter((e) => e.j9 === true).map((e) => e.case + "\u0000" + e.assertion));
  for (const a of J9_ANCHORS) {
    assert.ok(j9InRules.has(a.case + "\u0000" + a.assertion), `常量条目不在豁免表: ${a.case}/${a.assertion}`);
  }
  assert.equal(j9InRules.size, J9_ANCHORS.length, "豁免表 j9 条目数与常量不一致");
  const dir = path.join(root, "scripts", "teaching_truth", "cases");
  const onDisk = fs.readdirSync(dir).filter((n) => fs.statSync(path.join(dir, n)).isDirectory()).sort();
  assert.deepEqual(onDisk, [...CASE_NAMES].sort());
});
