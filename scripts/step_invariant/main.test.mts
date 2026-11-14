// step_invariant.test.mts —— 检查核心证红/证绿（J9 义务：篡改帧逐不变量必红）。
//
// 覆盖三层：
//   1. 绿基线：手工构造合法帧流（对齐 cli_step/serve_step 真实形状）全绿；
//      compile-error 单行形态正确 skip；
//   2. 证红：每条不变量（INV1a/1b/1c、INV2a/2b/2c、INV3a、INV4 三态、
//      ST1/3/4/5/6/7）构造一例篡改帧，断言恰好命中该不变量 id；
//   3. 常量镜像：引擎侧布局常量值锚（bytecode/memory.mbt 漂移连坐此处）。
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  checkStepStream,
  MEM_SIZE,
  NULL_TRAP_SIZE,
  GLOBAL_START,
  GLOBAL_REGION_LIMIT,
  HEAP_START,
  CALL_DEPTH_LIMIT,
} from "./main.mts";

// ── 帧构造器（对齐 step_payload_json 真实字段面）──

interface FrameOverrides {
  step_index?: number;
  depth?: number;
  bottomName?: string;
  vars?: Array<{ name: string; addr: number; is_local: boolean }>;
  ptrs?: Array<{ name: string; addr: number; target_addr: number; status: string }>;
}

function mkFrame(o: FrameOverrides = {}): Record<string, unknown> {
  const depth = o.depth ?? 1;
  const bottom = o.bottomName ?? "main";
  const callStack = Array.from({ length: depth }, (_, i) =>
    i === 0 ? { func_name: bottom, return_line: 0 } : { func_name: `f${i}`, return_line: 10 + i },
  );
  return {
    step_index: o.step_index ?? 0,
    code_line: 1,
    code_file: "t.c",
    func_name: depth > 0 ? "main" : "",
    semantic_label: "",
    semantic_label_id: "",
    algorithm_step: null,
    local_vars: o.vars ?? [{ name: "x", addr: 0xfff00, is_local: true, ty_name: "int", value: "3" }],
    call_stack: callStack,
    vis_events: [],
    heatmap_line: 0,
    heatmap_count: 0,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots: o.ptrs ?? [],
    root_cause_hint: null,
  };
}

function stepRow(id: number, payloads?: Array<Record<string, unknown>>, terminal: Record<string, unknown> = {}): string {
  return JSON.stringify({
    id,
    ok: true,
    result: {
      payloads: payloads ?? [],
      finished: false,
      trapped: false,
      waiting_input: false,
      paused: false,
      current_line: 1,
      trap_message: null,
      cache_start_step: 0,
      ...terminal,
    },
  });
}

/** 绿基线流：空首行 + 5 帧（栈深 1→2→1→0→0，含指针三态）+ 终态 + stdout + summary。 */
function greenStream(): string[] {
  return [
    stepRow(6), // 首行 payloads=[]（滞后一帧缓冲）
    stepRow(7, [mkFrame({ step_index: 0, depth: 1 })]),
    stepRow(8, [mkFrame({ step_index: 1, depth: 2 })]),
    stepRow(9, [mkFrame({ step_index: 2, depth: 1, ptrs: [{ name: "p", addr: 0xfff00, target_addr: 0x5000, status: "Valid" }] })]),
    stepRow(10, [mkFrame({ step_index: 3, depth: 0, ptrs: [{ name: "p", addr: 0xfff00, target_addr: 0x99999999, status: "Dangling" }] })]),
    stepRow(11, [mkFrame({ step_index: 4, depth: 0, ptrs: [{ name: "p", addr: 0xfff00, target_addr: 0, status: "Null" }] })], { finished: true }),
    JSON.stringify({ type: "stdout", frame: { id: 12, ok: true, result: { delta: "ok", cursor: 2, total: 2, stream: "stdout", truncated_bytes: 0 } } }),
    JSON.stringify({ type: "summary", frames: 5, finished: true, trapped: false }),
  ];
}

function invariantsOf(lines: string[], source = "t.c"): string[] {
  return checkStepStream(lines, source).violations.map((v) => v.invariant);
}

test("绿基线：手工合法帧流全绿（帧数/终态对）", () => {
  const r = checkStepStream(greenStream(), "t.c");
  assert.deepEqual(r.violations, []);
  assert.equal(r.frames, 5);
  assert.equal(r.terminal, "finished");
});

test("compile-error 单行形态：skip 不变量面", () => {
  const lines = [JSON.stringify({ id: 3, ok: true, result: { ok: false, diagnostics: [{ code: "E2003" }] } })];
  const r = checkStepStream(lines, "bad.c");
  assert.deepEqual(r.violations, []);
  assert.equal(r.terminal, "compile-error");
});

test("SWEEP1 #444：compile 失败帧 type:diag 包装归位 compile-error（旧裸帧语义同源）", () => {
  // step --json 的 compile 失败/run 协议错帧自 SWEEP1 #444 起为
  // {"type":"diag","frame":{id,ok,result}} 包装——识别面不更新则 ST2（缺 id/ok）
  // + ST7（缺 summary——terminal 停留 none）双红（CI 首轮 16 RED 实锤，全落
  // llm_multifile compile-error 语料）；识别后 terminal=compile-error，summary
  // 检查走豁免（与旧裸帧等价）
  const lines = [
    JSON.stringify({ type: "diag", frame: { id: 3, ok: true, result: { ok: false, diagnostics: [{ code: "E2003" }] } } }),
  ];
  const r = checkStepStream(lines, "bad.c");
  assert.deepEqual(r.violations, []);
  assert.equal(r.terminal, "compile-error");
});

// ── J9 证红：逐不变量篡改一例 ──

test("INV1a 证红：变量 addr 落 NULL 陷阱区", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, vars: [{ name: "x", addr: 0x500, is_local: true }] })]);
  assert.deepEqual(invariantsOf(s), ["INV1a"]);
});

test("INV1a 证红：指针 addr 域外", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, ptrs: [{ name: "p", addr: 0x100000, target_addr: 0x5000, status: "Valid" }] })]);
  assert.deepEqual(invariantsOf(s), ["INV1a"]);
});

test("INV1b 证红：全局变量 addr 越 GLOBAL_REGION_LIMIT", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, vars: [{ name: "g", addr: 0x20000, is_local: false }] })]);
  assert.deepEqual(invariantsOf(s), ["INV1b"]);
});

test("INV1c 证红：Freed 指针 target < HEAP_START（域内但非堆）", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, ptrs: [{ name: "p", addr: 0xfff00, target_addr: 0x4000, status: "Freed" }] })]);
  assert.deepEqual(invariantsOf(s), ["INV1c"]);
});

test("INV2a 证红：栈深超 call_depth_limit", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, depth: CALL_DEPTH_LIMIT + 1 })]);
  const inv = invariantsOf(s);
  assert.ok(inv.includes("INV2a"), `应含 INV2a，得 ${JSON.stringify(inv)}`);
  assert.ok(inv.includes("INV2b"), "10001 帧同时破 ±1（前帧深 1）——连带红属预期");
});

test("INV2b 证红：相邻帧栈深跳 +2", () => {
  const s = greenStream();
  s[2] = stepRow(8, [mkFrame({ step_index: 1, depth: 3 })]);
  const inv = invariantsOf(s);
  assert.ok(inv.includes("INV2b"), `应含 INV2b，得 ${JSON.stringify(inv)}`);
  // 后继帧（深 1）相对篡改帧也 -2——恰两例 INV2b，无其他不变量红
  assert.deepEqual(inv.filter((x) => x !== "INV2b"), []);
});

test("INV2c 证红：底帧非 main", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, bottomName: "notmain" })]);
  assert.deepEqual(invariantsOf(s), ["INV2c"]);
});

test("INV3a 证红：step_index 跳号", () => {
  const s = greenStream();
  s[2] = stepRow(8, [mkFrame({ step_index: 3, depth: 2 })]);
  const inv = invariantsOf(s);
  assert.ok(inv.includes("INV3a"), `应含 INV3a，得 ${JSON.stringify(inv)}`);
});

test("INV3a 证红：step_index 回退（cursor 非单调）", () => {
  const s = greenStream();
  s[2] = stepRow(8, [mkFrame({ step_index: 0, depth: 2 })]);
  assert.ok(invariantsOf(s).includes("INV3a"));
});

test("INV4 证红：Null 状态 target 非 0", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, ptrs: [{ name: "p", addr: 0xfff00, target_addr: 0x5000, status: "Null" }] })]);
  assert.deepEqual(invariantsOf(s), ["INV4"]);
});

test("INV4 证红：Dangling 状态 target 域内（判定与域不自洽）", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, ptrs: [{ name: "p", addr: 0xfff00, target_addr: 0x5000, status: "Dangling" }] })]);
  assert.deepEqual(invariantsOf(s), ["INV4"]);
});

test("INV4 证红：Valid 状态 target 越区", () => {
  const s = greenStream();
  s[1] = stepRow(7, [mkFrame({ step_index: 0, ptrs: [{ name: "p", addr: 0xfff00, target_addr: 0x1000000, status: "Valid" }] })]);
  assert.deepEqual(invariantsOf(s), ["INV4"]);
});

test("ST1 证红：非法 JSON 行", () => {
  const s = greenStream();
  s[1] = "{oops";
  // 首行（空 payloads）仍是首 step 行——ST5 不红；丢 step0 帧连带 INV3a 红
  assert.deepEqual(invariantsOf(s), ["ST1", "INV3a", "ST7"]);
});

test("ST3 证红：行 id 回退", () => {
  const s = greenStream();
  s[2] = stepRow(7, [mkFrame({ step_index: 1, depth: 2 })]);
  assert.ok(invariantsOf(s).includes("ST3"), "id 7 -> 7 非严格递增");
});

test("ST4 证红：双终态行", () => {
  const s = greenStream();
  s[4] = stepRow(10, [mkFrame({ step_index: 3, depth: 0 })], { trapped: true });
  assert.ok(invariantsOf(s).includes("ST4"), "finished 前再见 trapped 行");
});

test("ST5 证红：首行 payloads 非空", () => {
  const s = greenStream();
  s[0] = stepRow(6, [mkFrame({ step_index: 0 })]);
  const inv = invariantsOf(s);
  assert.ok(inv.includes("ST5"));
  assert.ok(inv.includes("INV3a"), "帧序 0,0,1.. 连带破连续（同因红）");
});

test("ST6 退役形态锚：回调段多帧行（3 帧连续）不红（#477 案 a）", () => {
  const s = greenStream();
  // 宿主回调段一条 CallHost 指令多帧的发布形态：单行 3 帧（step 0/1/2
  // 连续、栈深 1→2→2 形态合法）——数量上限已退役，仅 INV3a/INV2b 锁序
  s[1] = stepRow(7, [mkFrame({ step_index: 0, depth: 1 }), mkFrame({ step_index: 1, depth: 2 }), mkFrame({ step_index: 2, depth: 1 })]);
  s.splice(2, 2); // 摘掉原 step1/step2 行保帧序与帧数对账
  s.splice(4, 1);
  s[4] = JSON.stringify({ type: "summary", frames: 5, finished: true, trapped: false });
  const r = checkStepStream(s, "t.c");
  assert.deepEqual(r.violations, [], `回调段多帧行不得因帧数红：${JSON.stringify(r.violations)}`);
  assert.equal(r.frames, 5);
});

test("ST7 证红：summary.frames 计数不符", () => {
  const s = greenStream();
  s[7] = JSON.stringify({ type: "summary", frames: 99, finished: true, trapped: false });
  assert.deepEqual(invariantsOf(s), ["ST7"]);
});

test("ST7 证红：缺 summary 收口行", () => {
  const s = greenStream();
  s.splice(7, 1);
  assert.deepEqual(invariantsOf(s), ["ST7"]);
});

// ── 常量镜像锚（引擎侧漂移连坐）──

test("布局常量镜像：与 bytecode/memory.mbt 单源对齐", () => {
  assert.equal(MEM_SIZE, 0x100000);
  assert.equal(NULL_TRAP_SIZE, 0x1000);
  assert.equal(GLOBAL_START, 0x1000);
  assert.equal(GLOBAL_REGION_LIMIT, 0x10000);
  assert.equal(HEAP_START, 0x5000);
  assert.equal(CALL_DEPTH_LIMIT, 10000);
});

// ── 白名单形态锚（三态判定已抽 classifyViolations 纯函数，锚见下方；
// 此处锁登记文件形态防僵尸化源头）──

test("known_violations.json：条目形态合法（case 正斜杠 + invariant 在册 + reason/issue/count 非空）", async () => {
  const { loadKnown } = await import("./main.mts");
  const { projectRoot } = await import("../internal/capi.mts");
  const known = loadKnown(projectRoot());
  // #477 修复闭环（2026-11-05）：INV3a 七条白名单（qsort/bsearch 回调跳号）
  // 已全数拆除——帧号连续无豁免形态，复发即 RED 无放行通道
  assert.ok(
    known.every((k) => k.invariant !== "INV3a"),
    "INV3a 白名单须为空（#477 案 a 修复后回调段帧连续）",
  );
  const invariants = new Set([
    "INV1a", "INV1b", "INV1c", "INV2a", "INV2b", "INV2c", "INV3a", "INV4",
    "ST1", "ST2", "ST3", "ST4", "ST5", "ST6", "ST7",
  ]);
  for (const k of known) {
    assert.ok(!k.case.includes("\\"), `case 须正斜杠形态：${k.case}`);
    assert.ok(invariants.has(k.invariant), `invariant 在册：${k.invariant}`);
    assert.ok(k.reason.length > 10, `reason 须实质（为什么放行）：${k.case}`);
    assert.ok(k.issue.length > 0, `issue 引用非空：${k.case}`);
    assert.ok(k.count !== undefined && k.count >= 1, `count 期望条数必填（P3-2 恶化检测）：${k.case}`);
  }
});

// ── 审阅处置批锚（PR #478 P2-2/P2-3/P3-1/P3-2）──

test("ST2 证红：帧内数组字段退化 null（发射层形状防线——曾零判别力）", () => {
  const s = greenStream();
  const bad = mkFrame({ step_index: 0 });
  bad["local_vars"] = null;
  bad["call_stack"] = null;
  bad["pointer_snapshots"] = null;
  s[1] = stepRow(7, [bad]);
  const inv = invariantsOf(s);
  assert.ok(inv.includes("ST2"), `应含 ST2，得 ${JSON.stringify(inv)}`);
});

test("ST2 证红：payloads 整体 null（不再静默吞成空数组）", () => {
  const s = greenStream();
  s[1] = JSON.stringify({ id: 7, ok: true, result: { payloads: null, finished: false, trapped: false, waiting_input: false, paused: false, current_line: 1, trap_message: null, cache_start_step: 0 } });
  assert.ok(invariantsOf(s).includes("ST2"));
});

test("ST2 证红：local_vars 元素缺 is_local（类型形状）", () => {
  const s = greenStream();
  const bad = mkFrame({ step_index: 0 });
  bad["local_vars"] = [{ name: "x", addr: 0xfff00 }];
  s[1] = stepRow(7, [bad]);
  assert.ok(invariantsOf(s).includes("ST2"));
});

test("INV1a 边界锚：addr = MEM_SIZE-4 恰好绿；MEM_SIZE-3 必红（4 字节上界窗口）", () => {
  const atBound = greenStream();
  atBound[1] = stepRow(7, [mkFrame({ step_index: 0, vars: [{ name: "x", addr: MEM_SIZE - 4, is_local: true }] })]);
  assert.deepEqual(invariantsOf(atBound), [], "addr+4 == MEM_SIZE 恰在域内");
  const overBound = greenStream();
  overBound[1] = stepRow(7, [mkFrame({ step_index: 0, vars: [{ name: "x", addr: MEM_SIZE - 3, is_local: true }] })]);
  assert.deepEqual(invariantsOf(overBound), ["INV1a"], "addr+4 > MEM_SIZE 越界");
});

test("classifyViolations：count 内 expected 放行 / 超限恶化红 / 未登记红", async () => {
  const { classifyViolations } = await import("./main.mts");
  const mk = (n: number): Array<{ source: string; line: number; invariant: string; detail: string }> =>
    Array.from({ length: n }, () => ({ source: "corpus/a.c", line: 1, invariant: "INV3a", detail: "d" }));
  const known = [{ case: "corpus/a.c", invariant: "INV3a", reason: "r", issue: "#477", count: 1 }];
  const one = classifyViolations(mk(1), known);
  assert.equal(one.reds.length, 0);
  assert.equal(one.expected.length, 1);
  const two = classifyViolations(mk(2), known);
  assert.equal(two.reds.length, 1, "超出 count 的违例恶化红");
  assert.equal(two.expected.length, 1);
  assert.ok(two.hitKeys.has("corpus/a.c::INV3a"));
  const none = classifyViolations(mk(1), []);
  assert.equal(none.reds.length, 1);
});

// ── REHOST 批 3：--rehost 装载标记判定锚 ──────────────────────────────

test("批 3 rehostMarkerViolation：ok 标记放行 / 缺失与 fallback 红 / rc=1 不在断言面", async () => {
  const { rehostMarkerViolation } = await import("./main.mts");
  // ok 形态：终态 rc（0/2/3）+ ok 标记 → 放行
  for (const rc of [0, 2, 3]) {
    assert.equal(rehostMarkerViolation(rc, "// WASM-REHOST-STEP ok groups=12\n"), null, `rc=${rc} ok 放行`);
  }
  // fallback 形态（装载回退——标记行非 ok）→ 红
  assert.match(String(rehostMarkerViolation(0, "// WASM-REHOST-STEP fallback emit-failed gip=0 op=TryBegin\n")), /装载标记缺失\/回退/);
  // 标记缺失（旗标未生效/协议破损）→ 红
  assert.match(String(rehostMarkerViolation(2, "")), /装载标记缺失\/回退/);
  // rc=1（编译失败早退——未达 step.begin）与 rc=4（用法错）不在断言面
  assert.equal(rehostMarkerViolation(1, ""), null, "rc=1 编译失败不在断言面");
  assert.equal(rehostMarkerViolation(4, ""), null, "rc=4 用法错不在断言面");
});

