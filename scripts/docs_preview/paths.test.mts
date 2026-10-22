// paths.test.mts —— docs 站路径/排序/计数工具契约（#273 批二：字节口径锁）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { countWords, encodePath, encodeSegment, humanSize, naturalLess, pathRel, readingLabel } from "./paths.mts";

test("encodeSegment 走 UTF-8 字节百分号编码（非 UTF-16 code unit）", () => {
  assert.equal(encodeSegment("快速 入门.md"), "%E5%BF%AB%E9%80%9F%20%E5%85%A5%E9%97%A8.md");
  assert.equal(encodeSegment("a-b_c.d~e"), "a-b_c.d~e");
  assert.equal(encodePath("current/中文.md"), "current/%E4%B8%AD%E6%96%87.md");
});

test("pathRel 跨目录相对路径", () => {
  assert.equal(pathRel("", "a/b.html"), "a/b.html");
  assert.equal(pathRel("current/01-x", "current/01-x/p.html"), "p.html");
  assert.equal(pathRel("a/b", "a/c/d.html"), "../c/d.html");
});

test("naturalLess 数字前缀按数值排序，其余码点序", () => {
  assert.equal(naturalLess("01-a", "2-b"), true);
  assert.equal(naturalLess("2-b", "01-a"), false);
  assert.equal(naturalLess("a", "b"), true);
});

test("countWords：CJK 按字、ASCII 连续段按词", () => {
  assert.equal(countWords("中文 abc 12"), 4);
  assert.equal(countWords("a_b c-d"), 4);
});

test("readingLabel 400 字/分钟口径", () => {
  assert.equal(readingLabel(399), "小于 1 分钟");
  assert.equal(readingLabel(400), "1 分钟");
  assert.equal(readingLabel(801), "3 分钟");
});

test("humanSize 三档", () => {
  assert.equal(humanSize(1023), "1023 B");
  assert.equal(humanSize(1024), "1.0 KB");
  assert.equal(humanSize(1024 * 1024), "1.00 MB");
});
