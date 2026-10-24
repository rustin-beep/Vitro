// text.mts.test —— Go 字符串/字节口径复刻的判定面契约。
import { test } from "node:test";
import assert from "node:assert/strict";
import { byteCompare, byteSort, goFields, goJSONMarshalIndent, goTrimSpace } from "./text.mts";

test("byteCompare / byteSort：UTF-8 字节字典序（astral 面与 UTF-16 序不同）", () => {
  // U+FF5E = EF BD 9E；U+10000 = F0 90 80 80 —— 字节序 FF5E 先，
  // 而 JS 默认 `.sort()`（UTF-16 code unit）把 astral 的 D800 代理排在前面。
  assert.deepEqual(byteSort(["\u{10000}", "\uFF5E"]), ["\uFF5E", "\u{10000}"]);
  assert.deepEqual(["\u{10000}", "\uFF5E"].sort(), ["\u{10000}", "\uFF5E"], "对照组：原生序相反");
  assert.ok(byteCompare("a", "b") < 0);
  assert.equal(byteCompare("同", "同"), 0);
  assert.ok(byteCompare("b", "a") > 0);
});

test("byteSort 不改入参", () => {
  const xs = ["b", "a"];
  assert.deepEqual(byteSort(xs), ["a", "b"]);
  assert.deepEqual(xs, ["b", "a"]);
});

test("goTrimSpace：Go unicode.IsSpace 集（含 U+0085/U+2028/U+2029，不含 U+FEFF）", () => {
  assert.equal(goTrimSpace("  a\t\n"), "a");
  assert.equal(goTrimSpace("\u0085a\u00A0"), "a", "NEL 是 Go 空白");
  // #292 审阅 P3 实测：Go TrimSpace("\u2028x\u2029") == "x"（White_Space 含行/段分隔符）
  assert.equal(goTrimSpace("\u2028x\u2029"), "x", "U+2028/U+2029 属 Go 空白（本实现曾漏）");
  assert.equal(goTrimSpace("\uFEFFa"), "\uFEFFa", "U+FEFF（BOM）不是 Go 空白，两侧都不应剥");
  assert.equal(goTrimSpace(""), "");
});

test("goFields：连续空白不产空段，按 Go 空白集切分", () => {
  assert.deepEqual(goFields("  a\t\tb\n c  "), ["a", "b", "c"]);
  assert.deepEqual(goFields(""), []);
  assert.deepEqual(goFields("   "), []);
  assert.deepEqual(goFields("a\u0085b"), ["a", "b"]);
  assert.deepEqual(goFields("a\u2028b\u2029c"), ["a", "b", "c"], "U+2028/U+2029 是分隔符");
});

test("goJSONMarshalIndent：SetEscapeHTML 转义 < > & 与 U+2028/U+2029", () => {
  const out = goJSONMarshalIndent({ s: "<a>&</a>", u: "\u2028\u2029" });
  assert.ok(out.includes("\\u003ca\\u003e"));
  assert.ok(out.includes("\\u0026"));
  assert.ok(out.includes("\\u2028\\u2029"));
  assert.equal(goJSONMarshalIndent({ a: 1, b: 2 }), JSON.stringify({ a: 1, b: 2 }, null, 2), "无特殊字符时同形");
});
