// gen_icon_preview.test.mts —— 图鉴排版契约（#273 次批：%g 口径 + 布局确定性）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildSvg, fmtG } from "./main.mts";
import type { IconRow } from "./main.mts";

test("fmtG 对齐 Python %g（6 位有效数字、去尾零）", () => {
  assert.equal(fmtG(0), "0");
  assert.equal(fmtG(40), "40");
  assert.equal(fmtG(140.8), "140.8");
  assert.equal(fmtG(241.59999999999997), "241.6");
  assert.equal(fmtG(544.0000000000001), "544");
  assert.equal(fmtG(370.00000000000006), "370");
  assert.equal(fmtG(67.6), "67.6");
});

test("buildSvg：分组/卡片坐标/页高/页脚 + 确定性", () => {
  const rows: IconRow[] = [
    { id: "string", category: "词法" },
    { id: "comment", category: "词法" },
    { id: "unknown", category: "未登记组" },
  ];
  const bodyOf = new Map<string, string>([
    ["string", '<path d="M0 0"/>'],
    ["comment", ""],
  ]);
  const svg = buildSvg(rows, bodyOf);
  assert.match(svg, /viewBox="0 0 680 258"/);
  assert.match(svg, /Vitro 语义图标图鉴 · 3 个/);
  assert.match(svg, /词法 · 2/);
  assert.doesNotMatch(svg, /未登记组/);
  assert.match(svg, /<rect x="40" y="84" width="96" height="96" rx="10"/);
  assert.match(svg, /<rect x="140\.8" y="84" width="96" height="96" rx="10"/);
  assert.match(svg, /translate\(67\.6,94\) scale\(1\.7\)/);
  assert.match(svg, /y="158"[^>]*>string<\/text>/);
  assert.match(svg, /y="173"[^>]*>字符串<\/text>/);
  assert.ok(svg.endsWith("</svg>\n"));
  assert.equal(buildSvg(rows, bodyOf), svg);
});
