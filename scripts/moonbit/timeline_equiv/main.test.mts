// timeline_equiv 纯件测试（四件套之 node:test）：旧规则冻结副本的判据面 +
// compareCase 的 J9 突变证红（改归属/改字幕/丢步/改 DOM 任一必红）。
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  compareCase,
  displayedNames,
  escHtml,
  expectedOld,
  oldCaption,
  oldSwapPair,
} from "./main.mts";
import type { FrameProbe } from "../mcp_smoke/main.mts";

const fr = (over: Record<string, unknown>) => ({
  r: { a: ["5", "3"] },
  e: [[2, 2, 0, 1, -1, "a[j]:a[j + 1]"]],
  s: "交换 arr[0]↔arr[1]",
  ...over,
});

test("oldSwapPair：合法归属 + 越界/退化/无 context 丢弃", () => {
  assert.deepEqual(oldSwapPair(fr({}), "a"), { i: 0, j: 1 });
  assert.deepEqual(oldSwapPair(fr({ e: [[2, 2, 1, 0, -1, "a[j]:a[j + 1]"]] }), "a"), { i: 0, j: 1 }, "反序输入升序输出");
  assert.equal(oldSwapPair(fr({ e: [[2, 2, 1, 2, -1, "a[j]:a[j + 1]"]] }), "a"), null, "a[1]↔a[2] 越界（len=2）");
  assert.equal(oldSwapPair(fr({ e: [[2, 2, 1, 1, -1, "a[j]:a[j + 1]"]] }), "a"), null, "i==j");
  assert.equal(oldSwapPair(fr({ e: [[2, 2, -1, 0, -1, "a[j]:a[j + 1]"]] }), "a"), null, "-1 哨兵");
  assert.equal(oldSwapPair(fr({ e: [[2, 2, 0, 1, -1, "b[j]:b[j + 1]"]] }), "a"), null, "context 不点名");
  assert.deepEqual(oldSwapPair(fr({ r: { a: ["1", "2"], b: ["3", "4"] }, e: [[2, 2, 0, 1, -1, "b[j]:b[j + 1]"]] }), "b"), { i: 0, j: 1 }, "多数组按 context");
});

test("oldCaption：字幕三段拼接与 HTML 转义", () => {
  assert.equal(escHtml('a&b<c>"'), 'a&amp;b&lt;c&gt;"', "旧壳层 esc 只转 & < >");
  assert.equal(oldCaption({ s: "交换" }), "交换");
  assert.equal(
    oldCaption({ s: "比较", a: { p: "compare", d: "a<b" } }),
    '比较 <span class="as">\u2014 a&lt;b</span>',
  );
  assert.equal(
    oldCaption({ s: "错", h: { o: "越界" } }),
    '错 <span class="as" style="color:var(--err)">\u26a0 越界</span>',
  );
});

test("displayedNames：focus 真值优先，缺省回帧键", () => {
  assert.deepEqual(displayedNames({ focus: ["a"] }, {}), ["a"]);
  assert.deepEqual(displayedNames({}, { r: { x: [], y: [] } }), ["x", "y"]);
});

/** 合规合成案例（帧 0 交换 / 帧 1 普通 changed）。 */
function synthetic(): {
  data: Parameters<typeof compareCase>[0];
  probes: FrameProbe[];
} {
  const data = {
    frames: [
      { r: { a: ["5", "3"] }, e: [[2, 2, 0, 1, -1, "a[j]:a[j + 1]"]], s: "交换 arr[0]↔arr[1]" },
      { r: { a: ["3", "5"] }, e: [] as Array<Array<number | string>>, s: "第 2 行", a: { p: "compare", d: "desc" } },
    ],
    focus: ["a"],
    doc: {
      timeline: {
        pv: 1,
        steps: [
          { sw: { name: "a", i: 0, j: 1 }, cap: { t: "交换 arr[0]↔arr[1]", w: 2, dur: 1 } },
          { cap: { t: "第 2 行", w: 1, dur: 0 } },
        ],
      },
    },
  };
  const probes: FrameProbe[] = [
    { swap: 2, changed: 0, cap: '交换 arr[0]↔arr[1]' },
    { swap: 0, changed: 2, cap: '第 2 行 <span class="as">\u2014 desc</span>' },
  ];
  return { data, probes };
}

test("expectedOld：逐帧 swap/changed/归属", () => {
  const { data } = synthetic();
  const e0 = expectedOld(data.frames ?? [], 0, data.focus);
  assert.deepEqual(e0, { swapCells: 2, changedCells: 0, pairs: [{ name: "a", i: 0, j: 1 }] });
  const e1 = expectedOld(data.frames ?? [], 1, data.focus);
  assert.deepEqual(e1, { swapCells: 0, changedCells: 2, pairs: [] });
});

test("compareCase：合规合成案例绿 + 计数", () => {
  const { data, probes } = synthetic();
  const r = compareCase(data, probes, "a");
  assert.deepEqual(r.mismatches, []);
  assert.equal(r.stats.domSwapFrames, 1);
  assert.equal(r.stats.oldSwapCells, 2);
  assert.equal(r.stats.changedCells, 2);
});

test("compareCase：J9 突变必红（DOM/归属/字幕/丢步）", () => {
  {
    const { data, probes } = synthetic();
    probes[0]!.swap = 0;
    assert.ok(compareCase(data, probes, "a").mismatches.some((m) => m.includes("swap cells 旧规则=2 DOM=0")));
  }
  {
    const { data, probes } = synthetic();
    data.doc!.timeline!.steps![0]!.sw!.j = 2;
    const ms = compareCase(data, probes, "a").mismatches;
    assert.ok(ms.some((m) => m.includes("交换归属")));
  }
  {
    const { data, probes } = synthetic();
    probes[1]!.cap = "被篡改";
    assert.ok(compareCase(data, probes, "a").mismatches.some((m) => m.includes("字幕 HTML")));
  }
  {
    const { data, probes } = synthetic();
    data.doc!.timeline!.steps!.pop();
    assert.ok(compareCase(data, probes, "a").mismatches.some((m) => m.includes("步骤错位")));
  }
});
