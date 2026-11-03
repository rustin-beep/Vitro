// mcp_smoke 纯件测试（四件套之 node:test）：行缓冲/工具体提取/断言账本。
import { test } from "node:test";
import assert from "node:assert/strict";
import { makeLineAcc, toolTextOf, CheckRun } from "./main.mts";

test("makeLineAcc：跨 chunk 残行拼接 + 多帧一次到达", () => {
  const acc = makeLineAcc();
  assert.deepEqual(acc.feed('{"a":1}'), [], "半行不出帧");
  assert.deepEqual(acc.feed('\n{"b":2}\n'), ['{"a":1}', '{"b":2}'], "补齐换行出两帧");
  assert.deepEqual(acc.feed("\n\n"), [], "空行不产帧");
  assert.deepEqual(acc.feed('{"c":3'), [], "尾残行留存（未闭合）");
  assert.deepEqual(acc.feed("}\n"), ['{"c":3}'], "残行随后续补齐");
});

test("makeLineAcc：CRLF 帧尾 \r 被剪（宽容）", () => {
  const acc = makeLineAcc();
  assert.deepEqual(acc.feed('{"x":1}\r\n'), ['{"x":1}']);
});

test("toolTextOf：成功体与 isError 体", () => {
  const ok = toolTextOf({ result: { content: [{ type: "text", text: "{\"ok\":true}" }], isError: false } });
  assert.equal(ok.isError, false);
  assert.equal(ok.text, "{\"ok\":true}");
  const err = toolTextOf({ result: { content: [{ type: "text", text: "会话不存在" }], isError: true } });
  assert.equal(err.isError, true);
  assert.equal(err.text, "会话不存在");
});

test("toolTextOf：畸形结果 fail loud", () => {
  assert.throws(() => toolTextOf({ error: { code: -32602 } }), /畸形/);
  assert.throws(() => toolTextOf({ result: { content: [] } }), /畸形/);
  assert.throws(() => toolTextOf({ result: { content: [{ type: "text" }] } }), /畸形/);
});

test("CheckRun：计数与失败清单", () => {
  const chk = new CheckRun();
  chk.check("a", true);
  chk.check("b", false, "细节");
  chk.check("c", true);
  assert.equal(chk.total, 3);
  assert.equal(chk.failures.length, 1);
  assert.equal(chk.failures[0], "b — 细节");
});
