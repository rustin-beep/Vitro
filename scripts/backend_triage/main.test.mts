// backend_triage 单测（node:test）——比对芯的红态锚（J9：突变注入即红）：
// 形状门量（空输出/缺行/缺帧）+ 比对（rc 差/内容差/长度差/臂数）+
// CRLF 归一边界（native 介入、js 不介入）+ 字节口径。
import test from "node:test";
import assert from "node:assert/strict";
import { compareTriad, normalizeCrlf, validateShape, EXPECTED_LINES, type ArmResult } from "./main.mts";

/** 合法 10 行输出（形状门量全过）——测试基线。 */
function goodOut(): Buffer {
  const lines = [
    '{"id":1,"ok":true,"result":{"pong":true}}',
    '{"id":null,"ok":false,"error":{"kind":"protocol","message":"x"}}',
    "v0.2",
    "0.9.0",
    "123456789",
    "0.3333333333333333",
    "-0.0",
    "4",
    '{"id":9,"ok":true,"result":{"ok":true,"diagnostics":[]}}',
    '{"id":10,"ok":true,"result":{"status":"finished","return_value":7}}',
  ];
  return Buffer.from(lines.join("\n") + "\n", "utf8");
}

const ok = (label: string, out: Buffer): ArmResult => ({ label, out, rc: 0 });

test("三臂一致即绿（零归一介入）", () => {
  const v = compareTriad([ok("native", goodOut()), ok("js", goodOut()), ok("wasm-gc", goodOut())]);
  assert.equal(v.ok, true);
  assert.match(v.msg, /逐字节一致/);
  assert.doesNotMatch(v.msg, /归一介入/);
});

test("形状门量：空输出即红（P2-1 静默突变）", () => {
  assert.match(validateShape(Buffer.alloc(0)) ?? "", /行数 0/);
});

test("形状门量：缺行即红（ignore 化单行）", () => {
  const lines = goodOut().toString("utf8").split("\n").filter((l) => l.length > 0);
  lines.splice(4, 1);
  assert.match(validateShape(Buffer.from(lines.join("\n") + "\n", "utf8")) ?? "", new RegExp(`行数 ${EXPECTED_LINES - 1}`));
});

test("形状门量：ping/版本/compile+run 帧缺位各自红", () => {
  const bad1 = goodOut().toString("utf8").replace('"pong":true', '"pong":false');
  assert.match(validateShape(Buffer.from(bad1, "utf8")) ?? "", /缺 ping 帧断言/);
  const bad2 = goodOut().toString("utf8").replace('"return_value":7', '"return_value":8');
  assert.match(validateShape(Buffer.from(bad2, "utf8")) ?? "", /return_value:7/);
});

test("compareTriad：空输出臂在形状门量即红", () => {
  const v = compareTriad([ok("native", goodOut()), ok("js", Buffer.alloc(0)), ok("wasm-gc", goodOut())]);
  assert.equal(v.ok, false);
  assert.match(v.msg, /js 臂形状门量：行数 0/);
});

test("rc 差即红（归因到臂）", () => {
  const v = compareTriad([ok("native", goodOut()), ok("js", goodOut()), { label: "wasm-gc", out: goodOut(), rc: 1 }]);
  assert.equal(v.ok, false);
  assert.match(v.msg, /wasm-gc 臂 rc=1/);
});

test("内容差即红（字节 offset 定位）", () => {
  // 突变点选第 5 行（i64 数字行——形状门量不查其内容，专测比对芯）
  const badJs = goodOut();
  const at = badJs.indexOf(Buffer.from("123456789", "utf8"));
  assert.ok(at > 0);
  badJs[at] = (badJs[at] ?? 0) ^ 0x01;
  const v = compareTriad([ok("native", goodOut()), ok("js", badJs), ok("wasm-gc", goodOut())]);
  assert.equal(v.ok, false);
  assert.match(v.msg, /首差 offset=\d+（0x/);
});

test("长度差即红（单侧尾部增删，字节计）", () => {
  const longer = Buffer.concat([goodOut(), Buffer.from("extra\n", "utf8")]);
  const v = compareTriad([ok("native", goodOut()), ok("js", longer), ok("wasm-gc", goodOut())]);
  assert.equal(v.ok, false);
  // 形状门量先拦（11 行 ≠ 10）——本锚同时证门量与长度语义
  assert.match(v.msg, /行数 11|长度差/);
});

test("CRLF 归一：native 臂介入且标注，js/wasm 零归一", () => {
  const lf = goodOut();
  const crlf = Buffer.from(lf.toString("utf8").split("\n").join("\r\n"), "utf8");
  // native 臂 CRLF → 归一后一致即绿（显式标注介入）
  const vNative = compareTriad([ok("native", crlf), ok("js", lf), ok("wasm-gc", lf)]);
  assert.equal(vNative.ok, true);
  assert.match(vNative.msg, /归一介入/);
  // js 臂 CRLF = 真红（不经归一——CRLF 出现在非 native 臂是通道层回归）
  const vJs = compareTriad([ok("native", lf), ok("js", crlf), ok("wasm-gc", lf)]);
  assert.equal(vJs.ok, false);
});

test("normalizeCrlf 只剥 0d0a 对中的 0d（孤立 0d 不动——字节严格性）", () => {
  const b = Buffer.from([0x61, 0x0d, 0x0a, 0x62, 0x0d, 0x63]);
  const n = normalizeCrlf(b);
  assert.deepEqual([...n], [0x61, 0x0a, 0x62, 0x0d, 0x63]);
});

test("臂数破损即红（防驱动装配回归）", () => {
  const v = compareTriad([ok("native", goodOut()), ok("js", goodOut())]);
  assert.equal(v.ok, false);
  assert.match(v.msg, /臂数=2/);
});
