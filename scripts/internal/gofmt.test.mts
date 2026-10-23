// gofmt.test.mts —— Go 文本口径复刻的自证：%q / %-Ns / 字节序。
//
// 期望值一律来自 `go run` 实测（2026-10-23 对拍留痕），不是照文档猜——
// 尤其 U+00A0 落 \u 而非 \x 这一步，是实测纠正了初版实现的错判。
import { test } from "node:test";
import assert from "node:assert/strict";
import { byteCompare, goQuote, padEndRunes, sortBytes } from "./gofmt.mts";

test("goQuote：可打印面原样（ASCII / 中文 / emoji / 反引号 / ${）", () => {
  assert.equal(goQuote("abc"), '"abc"');
  assert.equal(goQuote("排序"), '"排序"');
  assert.equal(goQuote("😀"), '"😀"');
  assert.equal(goQuote("a`b${c}"), '"a`b${c}"');
  assert.equal(goQuote(""), '""');
});

test("goQuote：引号与反斜杠恒转义", () => {
  assert.equal(goQuote('a"b'), '"a\\"b"');
  assert.equal(goQuote("a\\b"), '"a\\\\b"');
});

test("goQuote：控制字符走短转义表", () => {
  assert.equal(goQuote("a\nb"), '"a\\nb"');
  assert.equal(goQuote("a\tb"), '"a\\tb"');
  assert.equal(goQuote("\x07\x08\x0c\x0b\x0d"), '"\\a\\b\\f\\v\\r"');
});

test("goQuote：\\x 只给 <0x20 与 0x7f；非 ASCII 不可打印落 \\u/\\U", () => {
  assert.equal(goQuote("\x00\x01"), '"\\x00\\x01"');
  assert.equal(goQuote("\x7f"), '"\\x7f"');
  // U+00A0 NO-BREAK SPACE：Zs 类非可打印，但 >= 0x20 —— Go 出 \u00a0
  assert.equal(goQuote("\u00a0"), '"\\u00a0"');
  assert.equal(goQuote("\u2028\u2029"), '"\\u2028\\u2029"');
});

test("padEndRunes：宽度按 rune 计（非 UTF-16 code unit）", () => {
  assert.equal(padEndRunes("abc", 6), "abc   ");
  assert.equal(padEndRunes("abc", 3), "abc");
  assert.equal(padEndRunes("abcd", 3), "abcd");
  // 两个汉字 = 2 rune（JS length 也是 2，此例不区分）；emoji 才区分：
  // "😀" 的 JS length = 2 而 rune 数 = 1
  assert.equal(padEndRunes("😀", 3), "😀  ");
});

test("byteCompare / sortBytes：UTF-8 字节序（不是 UTF-16 code unit 序）", () => {
  // 反例锚：U+FFFD(EF BF BD) < U+1F600(F0 9F 98 80) 在字节序；而 UTF-16 下
  // 0xD83D < 0xFFFD 会给出相反结论
  const emoji = "\u{1F600}";
  const replacement = "\uFFFD";
  assert.equal(byteCompare(emoji, replacement), 1);
  assert.ok(emoji < replacement, "UTF-16 默认序应与字节序相反——本锚即两口径的分歧点");
  assert.equal(byteCompare("a", "a"), 0);
  assert.deepEqual(sortBytes(["b", "a", "c"]), ["a", "b", "c"]);
  assert.deepEqual(sortBytes(["aa", "a", "ab"]), ["a", "aa", "ab"]);
});
