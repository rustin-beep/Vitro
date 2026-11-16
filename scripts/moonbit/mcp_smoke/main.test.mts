// mcp_smoke 纯件测试（四件套之 node:test）：行缓冲/工具体提取/断言账本/
// script 提段与 PLAYER 驱动器（#468 语法门 / #469 swap 对拍的纯件面）。
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  makeLineAcc,
  toolTextOf,
  CheckRun,
  extractScript,
  driveScript,
  checkTimelinePlan,
  frameHasValidSwap,
  contextMentionsArray,
} from "./main.mts";

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

test("contextMentionsArray：标识符/成员边界（旧规则同款）", () => {
  assert.equal(contextMentionsArray("a[j]:a[j + 1]", "a"), true);
  assert.equal(contextMentionsArray("a [j]", "a"), true);
  assert.equal(contextMentionsArray("obj.arr[j]", "arr"), false, "成员访问不算");
  assert.equal(contextMentionsArray("barr[j]", "arr"), false, "标识符内含不算");
  assert.equal(contextMentionsArray("ab[j]", "a"), false, "前缀同形不算（后接 b 非 [）");
});

test("frameHasValidSwap：越界/歧义/缺失不点亮", () => {
  const len5 = ["1", "2", "3", "4", "5"];
  assert.equal(frameHasValidSwap({ r: { a: len5 }, e: [[2, 2, 0, 1, -1, "a[j]:a[j + 1]"]] }), true);
  assert.equal(frameHasValidSwap({ r: { a: len5 }, e: [[2, 2, 4, 5, -1, "a[j]:a[j + 1]"]] }), false, "a[4]↔a[5] 越界（bubble_sort 实锤）");
  assert.equal(frameHasValidSwap({ r: { a: len5 }, e: [[2, 2, 2, 2, -1, "a[j]:a[j + 1]"]] }), false, "i==j 丢");
  assert.equal(frameHasValidSwap({ r: { a: len5 }, e: [[2, 2, 0, 1, -1, ""]] }), false, "无 context 不猜");
  assert.equal(frameHasValidSwap({ r: { a: len5, b: len5 }, e: [[2, 2, 0, 1, -1, "a[j]:b[j + 1]"]] }), false, "歧义不猜");
});

test("checkTimelinePlan：合规产物绿 + 计数（v0.2 六字段）", () => {
  const data = {
    frames: [
      { r: { a: ["2", "1"] }, rt: { a: "int" }, c: ["prog", "main"], e: [[2, 2, 0, 1, -1, "a[j]:a[j + 1]"]], s: "交换 arr[0]↔arr[1]" },
      { r: { a: ["2", "1"] }, rt: { a: "int" }, c: ["prog", "main"], e: [], s: "" },
    ],
    doc: {
      timeline: {
        pv: 2,
        steps: [
          {
            sw: { name: "a", i: 0, j: 1 },
            cap: { t: "交换 arr[0]↔arr[1]", w: 2, dur: 1 },
            bar: { a: [1, 0.5] },
            cam: { fit: "calltree", func: "main", depth: 2 },
          },
          { bar: { a: [1, 0.5] } },
        ],
      },
    },
  };
  const r = checkTimelinePlan(data, "a");
  assert.deepEqual(r.errors, []);
  assert.equal(r.steps, 2);
  assert.equal(r.swFrames, 1);
});

test("checkTimelinePlan：J9 突变必红（对齐/归属/空串/漏点亮/pv/ch/bar/cam）", () => {
  const mk = () => ({
    frames: [
      { r: { a: ["2", "1"] }, rt: { a: "int" }, c: ["prog", "main"], e: [[2, 2, 0, 1, -1, "a[j]:a[j + 1]"]], s: "交换 arr[0]↔arr[1]" },
      { r: { a: ["2", "1"] }, rt: { a: "int" }, c: ["prog", "main"], e: [], s: "" },
    ],
    doc: {
      timeline: {
        pv: 2,
        steps: [
          {
            sw: { name: "a", i: 0, j: 1 },
            cap: { t: "交换 arr[0]↔arr[1]", w: 2, dur: 1 },
            bar: { a: [1, 0.5] },
            cam: { fit: "calltree", func: "main", depth: 2 },
          },
          { bar: { a: [1, 0.5] } },
        ],
      },
    },
  });
  const wrongName = mk();
  wrongName.doc.timeline.steps[0]!.sw!.name = "arr";
  assert.ok(checkTimelinePlan(wrongName, "a").errors.some((e) => e.includes("归属真名")));
  const misaligned = mk();
  misaligned.doc.timeline.steps.pop();
  assert.ok(checkTimelinePlan(misaligned, "a").errors.some((e) => e.includes("步骤错位")));
  const missingSw = mk();
  delete missingSw.doc.timeline.steps[0]!.sw;
  assert.ok(checkTimelinePlan(missingSw, "a").errors.some((e) => e.includes("未点亮")));
  const emptyCap = mk();
  emptyCap.doc.timeline.steps[1]!.cap = { t: "", w: 1, dur: 0 };
  assert.ok(checkTimelinePlan(emptyCap, "a").errors.some((e) => e.includes("空标签仍产 cap")));
  // v0.2 突变：pv 旧值 / ch 漏 / bar 越界 / cam 丢弃 —— 四路必红
  const oldPv = mk();
  (oldPv.doc.timeline as { pv: number }).pv = 1;
  assert.ok(checkTimelinePlan(oldPv, "a").errors.some((e) => e.includes("pv 非 2")));
  const chAng = mk();
  chAng.frames[1]!.r!.a = ["9", "1"];
  assert.ok(checkTimelinePlan(chAng, "a").errors.some((e) => e.includes("ch[a]")));
  const barOver = mk();
  barOver.doc.timeline.steps[0]!.bar!.a = [1.5, 0.5];
  assert.ok(checkTimelinePlan(barOver, "a").errors.some((e) => e.includes("bar[a][0]")));
  const camGone = mk();
  delete camGone.doc.timeline.steps[0]!.cam;
  assert.ok(checkTimelinePlan(camGone, "a").errors.some((e) => e.includes("缺 cam")));
});
