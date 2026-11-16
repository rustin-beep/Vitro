// timeline_wasm_anchor 判定器自证（node:test）：合法 plan 过；pv/错位/ch/bar/cam/
// enter 六类篡改必红——判定器先证会红再采信（J9 义务，等价闸形态）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { checkPlanContent, locateWasm } from "./main.mts";

type Json = any;

function payload(over: Json = {}): Json {
  return {
    array_snapshots: [{ name: "a", element_ty: "int", elements: ["1", "2"] }],
    call_stack: [{ func_name: "main" }],
    ...over,
  };
}

function plan(steps: Json[]): Json {
  return { pv: 2, steps };
}

const CAM0 = { fit: "calltree", func: "main", depth: 1 };

test("timeline_wasm_anchor：合法 v0.2 plan 过（ch 差分 / bar 比例 / cam 首帧）", () => {
  const payloads = [
    payload(),
    payload({ array_snapshots: [{ name: "a", element_ty: "int", elements: ["1", "1"] }] }),
  ];
  const steps = [
    { bar: { a: [0.5, 1] }, cam: CAM0 },
    { ch: { a: [1] }, bar: { a: [1, 1] }, enter: "func:main" },
  ];
  const { errors, counts } = checkPlanContent(plan(steps), payloads);
  assert.deepEqual(errors, []);
  assert.equal(counts.frames, 2);
  assert.equal(counts.chFrames, 1);
  assert.equal(counts.barFrames, 2);
  assert.equal(counts.camFrames, 1);
  assert.equal(counts.enterFrames, 1);
});

test("timeline_wasm_anchor：pv 非 2 / steps 错位必红", () => {
  const p0 = payload();
  assert.match(checkPlanContent({ pv: 1, steps: [{ cam: CAM0 }] }, [p0]).errors.join("|"), /pv 非 2/);
  assert.match(checkPlanContent(plan([]), [p0]).errors.join("|"), /错位/);
  assert.match(checkPlanContent({ pv: 2 }, [p0]).errors.join("|"), /steps 缺失/);
});

test("timeline_wasm_anchor：ch 篡改（漏/多/错下标）必红", () => {
  const payloads = [payload(), payload({ array_snapshots: [{ name: "a", element_ty: "int", elements: ["1", "1"] }] })];
  // 漏 ch
  const missing = checkPlanContent(plan([{ cam: CAM0 }, { bar: { a: [1, 1] } }]), payloads);
  assert.match(missing.errors.join("|"), /ch\[a\] 期望 \[1\] 实得 \[\]/);
  // 错下标
  const wrong = checkPlanContent(plan([{ cam: CAM0 }, { ch: { a: [0] }, bar: { a: [1, 1] } }]), payloads);
  assert.match(wrong.errors.join("|"), /ch\[a\] 期望 \[1\]/);
});

test("timeline_wasm_anchor：bar 越界/长度/char 产条必红", () => {
  const p0 = payload();
  const over = checkPlanContent(plan([{ cam: CAM0, bar: { a: [0.5, 1.5] } }]), [p0]);
  assert.match(over.errors.join("|"), /bar\[a\]\[1\]/);
  const short = checkPlanContent(plan([{ cam: CAM0, bar: { a: [0.5] } }]), [p0]);
  assert.match(short.errors.join("|"), /长度 1 ≠ 2/);
  const chP = payload({ array_snapshots: [{ name: "c", element_ty: "char", elements: ["a", "b"] }] });
  const charBar = checkPlanContent(plan([{ cam: CAM0, bar: { c: [1, 1] } }]), [chP]);
  assert.match(charBar.errors.join("|"), /char 数组 c 仍产 bar/);
});

test("timeline_wasm_anchor：cam 缺失于栈变帧 / 不变帧多产 / enter 值域必红", () => {
  const p0 = payload();
  const p1 = payload({ call_stack: [{ func_name: "main" }, { func_name: "bubble" }] });
  const missingCam = checkPlanContent(plan([{ cam: CAM0 }, { bar: { a: [0.5, 1] } }]), [p0, p1]);
  assert.match(missingCam.errors.join("|"), /首帧\/栈变帧缺 cam/);
  const extraCam = checkPlanContent(plan([{ cam: CAM0 }, { cam: CAM0, bar: { a: [0.5, 1] } }]), [p0, p0]);
  assert.match(extraCam.errors.join("|"), /栈不变仍产 cam/);
  const badEnter = checkPlanContent(plan([{ cam: CAM0, enter: "boom" }]), [p0]);
  assert.match(badEnter.errors.join("|"), /enter 值域非法/);
});

test("timeline_wasm_anchor：wasm 定位（--wasm 优先，否则 release/debug 形态）", () => {
  const root = "D:/x";
  assert.equal(locateWasm(["--wasm", "C:/w.wasm"], root), "C:/w.wasm");
  const fallback = locateWasm([], root);
  assert.match(fallback.replace(/\\/g, "/"), /moonbit\/_build\/wasm-gc\/(release|debug)\/build\/gateway\/wasm\/wasm\.wasm$/);
});
