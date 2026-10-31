// replay_s1_s5.test.mts —— 判定 helper 口径 + J9 自检 + 端点端到端（.mts 重写批）。
//
// 重点：这些 helper 是断言的判据面（版本下限 / 深度相等 / 诊断过滤 /
// step_index 投影）——helper 口径一错，整套 61 条断言的绿就不可信。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { projectRoot } from "../internal/capi.mts";
import { Report, abiVersionAtLeast, deepEqual, diagErrors, head3, selfTest, stepIndexOf } from "./replay_s1_s5.mts";

const MAIN = path.join(import.meta.dirname, "replay_s1_s5.mts");
// #392 审阅 P2-1（2026-10-31）：native 产物统一带 .exe（跨平台）——平台三元
// Linux 指向不存在文件（#359 同 root cause）
const SERVE = path.join(
  projectRoot(),
  "moonbit",
  "_build",
  "native",
  "debug",
  "build",
  "cmd",
  "serve",
  "serve.exe",
);

test("abiVersionAtLeast：下限语义（更高 major 过 / 同 major 比 minor / 垃圾串拒）", () => {
  assert.equal(abiVersionAtLeast("1.1.0", 1, 1), true);
  assert.equal(abiVersionAtLeast("1.2.0", 1, 1), true);
  assert.equal(abiVersionAtLeast("1.0.9", 1, 1), false);
  assert.equal(abiVersionAtLeast("0.9.9", 1, 1), false);
  assert.equal(abiVersionAtLeast("2.0.0", 1, 1), true, "2.0.0 ≥ 1.1.0（旧实现 major 不同即拒的翻案锚）");
  assert.equal(abiVersionAtLeast("garbage", 1, 1), false);
  assert.equal(abiVersionAtLeast("1.1", 1, 1), false, "缺 patch 段即拒（Go Sscanf %d.%d.%d 同口径）");
});

test("deepEqual：数组下标对齐、对象键集合对齐、嵌套递归", () => {
  assert.equal(deepEqual([1, 2], [1, 2]), true);
  assert.equal(deepEqual([1, 2], [2, 1]), false, "数组有序");
  assert.equal(deepEqual({ a: 1, b: 2 }, { b: 2, a: 1 }), true, "对象无序");
  assert.equal(deepEqual({ a: 1 }, { a: 1, b: 2 }), false);
  assert.equal(deepEqual({ a: [1, { c: 2 }] }, { a: [1, { c: 2 }] }), true);
  assert.equal(deepEqual(null, null), true);
  assert.equal(deepEqual(1, "1"), false);
});

test("diagErrors：只留 severity=error", () => {
  const resp = {
    result: { diagnostics: [{ severity: "warning", code: "W1" }, { severity: "error", code: "E2005" }] },
  };
  const got = diagErrors(resp);
  assert.equal(got.length, 1);
  assert.equal(got[0]?.["code"], "E2005");
  assert.deepEqual(diagErrors({}), []);
});

test("head3：截前三条（S5 失败明细的格式化口径）", () => {
  assert.deepEqual(head3([]), []);
  assert.deepEqual(head3(["a", "b"]), ["a", "b"]);
  assert.deepEqual(head3(["a", "b", "c", "d"]), ["a", "b", "c"]);
});

test("stepIndexOf：payload 列表 → step_index 序列", () => {
  assert.deepEqual(stepIndexOf([{ step_index: 0 }, { step_index: 1 }]), [0, 1]);
  assert.deepEqual(stepIndexOf([{}, { step_index: 5 }]), [0, 5], "缺字段记 0（mnum 口径）");
});

test("Report：PASS 行尾部两空格 + 汇总计数（含 FAIL 明细行）", () => {
  const rep = new Report();
  rep.check("S1", "A1", true, "");
  rep.check("S1", "A2", false, "坏掉了");
  const code = rep.summarize();
  assert.equal(code, 1);
  assert.equal(rep.rows.length, 2);
  assert.equal(rep.rows[1]?.ok, false);
});

test("selfTest：J9 埋雷全通过（12 条注入断言）", () => {
  assert.doesNotThrow(() => selfTest());
});

test("e2e：--selftest 退出 0（不触发 serve 会话）", () => {
  const r = spawnSync(process.execPath, [MAIN, "--selftest"], { cwd: projectRoot(), encoding: "utf8" });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /selftest：判定口径 12 条注入断言全部通过/);
});

test("e2e：未选臂 → exit 2 并打印现役两枝（rust 臂已退役）", () => {
  const r = spawnSync(process.execPath, [MAIN], { cwd: projectRoot(), encoding: "utf8" });
  assert.equal(r.status, 2);
  assert.match(r.stdout, /错误: 未选被测物臂——rust 臂已退役/);
});

test("e2e：-moonbit 全绿（61 断言；缺 serve 产物显式 skip）", (t) => {
  if (!fs.existsSync(SERVE)) {
    t.diagnostic(`skip：serve 产物不存在（${SERVE}）——先 cd moonbit && MOON_CC=clang moon build --target native cmd/serve`);
    return;
  }
  const r = spawnSync(process.execPath, [MAIN, "-moonbit"], { cwd: projectRoot(), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, (r.stdout ?? "").slice(-3000) + r.stderr);
  assert.match(r.stdout, /^  \[PASS\] S1 A1 {2}$/m, "PASS 行尾部两空格（Go 版逐字同形）");
  assert.match(r.stdout, /断言总数: 61  PASS: 60  EXEMPT: 1  FAIL: 0/);
});
