// backend_triage 单测（node:test）——比对判定 compareTriad 的三态锚：
// 一致绿 / rc 差红 / 输出差红（长度差 + 内容差两形态）。
// J9：红态锚即「突变注入即红」的机判形态（驱动主流程的比对芯不可静默）。
import test from "node:test";
import assert from "node:assert/strict";
import { compareTriad, normalizeLineEndings, type ArmResult } from "./main.mts";

const ok = (label: string, out: string): ArmResult => ({ label, out, rc: 0 });

test("三臂一致即绿", () => {
  const v = compareTriad([ok("native", "a\nb\n"), ok("js", "a\nb\n"), ok("wasm-gc", "a\nb\n")]);
  assert.equal(v.ok, true);
  assert.match(v.msg, /逐字节一致/);
});

test("Windows native CRT 行尾归一后一致即绿（#315 同族登记形态）", () => {
  const v = compareTriad([ok("native", "a\r\nb\r\n"), ok("js", "a\nb\n"), ok("wasm-gc", "a\nb\n")]);
  assert.equal(v.ok, true);
});

test("行尾归一只剥 CRLF 不动其它字节", () => {
  assert.equal(normalizeLineEndings("a\r\nb\r\n"), "a\nb\n");
  assert.equal(normalizeLineEndings("a\nb\n"), "a\nb\n");
  // 孤立 \r（非 CRLF 成员）不归一——保持逐字节严格性
  assert.equal(normalizeLineEndings("a\rb\n"), "a\rb\n");
});

test("任一臂 rc 非 0 即红（归因到臂）", () => {
  const v = compareTriad([ok("native", "x"), ok("js", "x"), { label: "wasm-gc", out: "", rc: 1 }]);
  assert.equal(v.ok, false);
  assert.match(v.msg, /wasm-gc 臂 rc=1/);
});

test("输出内容差即红（同长首差定位）", () => {
  const v = compareTriad([ok("native", "ping\nok\n0.2\n0.9.0\n"), ok("js", "ping\nok\n0.3\n0.9.0\n"), ok("wasm-gc", "ping\nok\n0.2\n0.9.0\n")]);
  assert.equal(v.ok, false);
  assert.match(v.msg, /native vs js: 首差 offset=\d+/);
});

test("输出长度差即红（单侧尾部增删）", () => {
  const v = compareTriad([ok("native", "a\n"), ok("js", "a\nb\n"), ok("wasm-gc", "a\n")]);
  assert.equal(v.ok, false);
  assert.match(v.msg, /长度差 2B vs 4B/);
});

test("臂数破损即红（防驱动装配回归）", () => {
  const v = compareTriad([ok("native", "a"), ok("js", "a")]);
  assert.equal(v.ok, false);
  assert.match(v.msg, /臂数=2/);
});
