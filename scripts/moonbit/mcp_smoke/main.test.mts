// mcp_smoke 纯件测试（四件套之 node:test）：行缓冲/工具体提取/断言账本/
// script 提段与 PLAYER 驱动器（#468 语法门 / #469 swap 对拍的纯件面）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { makeLineAcc, toolTextOf, CheckRun, extractScript, driveScript } from "./main.mts";

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

test("extractScript：取段与无段 fail loud", () => {
  assert.equal(extractScript("<html><script>var a=1;</script></html>"), "var a=1;");
  assert.equal(extractScript("<b>x</b><script>\nvar b=2;\n</script>"), "\nvar b=2;\n");
  assert.throws(() => extractScript("<html></html>"), /无 <script>/);
});

test("driveScript：语法门 throw（#468 形态——模板转义丢失的裸换行）", () => {
  // vm context 的 SyntaxError 与主 realm 原型不同——按 name 断言（语法门语义）。
  assert.throws(() => driveScript('var x="裸换行\n在字符串里";'), { name: "SyntaxError" });
});

test("driveScript：逐帧驱动 + swap 类名计数（mini PLAYER）", () => {
  // 只复刻驱动器契约面：__VITRO__ 数据、renderFrame 写 stage、slider.oninput
  // = stepTo、max = 帧数-1。帧 0 带 ty=2 事件（context 点名 a）应产 swap 类名。
  const script = [
    "var D=window.__VITRO__={frames:[",
    '{r:{a:["1","2"]},e:[[2,2,0,1,-1,"a[j]:a[j + 1]"]]},',
    '{r:{a:["2","1"]},e:[]}],focus:["a"]};',
    "var S={cur:0,frames:D.frames};",
    "function $(id){return document.getElementById(id)}",
    'function ctxMentions(ctx,nm){return ctx.indexOf(nm+"[")>=0}',
    "function swapPair(fr,nm,len){for(var k=0;k<fr.e.length;k++){var ev=fr.e[k];",
    "if(ev[0]!==2||!ctxMentions(ev[5],nm))continue;return{i:ev[2],j:ev[3]}}return null}",
    "function renderFrame(){var fr=S.frames[S.cur];var sp=swapPair(fr,\"a\",2);var h=\"\";",
    'for(var i2=0;i2<2;i2++){h+=\'<div class="cell\'+(sp&&(i2===sp.i||i2===sp.j)?" swap":"")+\'">\';}',
    '$("stage").innerHTML=h;$("slider").max=S.frames.length-1}',
    "renderFrame();",
    '$("slider").oninput=function(){S.cur=+this.value;renderFrame()};',
  ].join("\n");
  const r = driveScript(script);
  assert.equal(r.total, 2);
  assert.equal(r.swapFrames, 1);
});
