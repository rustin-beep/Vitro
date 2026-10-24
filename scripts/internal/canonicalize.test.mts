// canonicalize.test.mts —— 归一性质 + J9 锚（Go 版 7 例 + 字节序/重复键/转义面）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { JsonRaw, canonicalizeText, compactGoJson, emitSortedObject, embedText, parseRawJson } from "./canonicalize.mts";
import type { JsonValue } from "./canonicalize.mts";

test("键排序：嵌套对象逐层按键字节序", () => {
  assert.equal(
    canonicalizeText(`{"b":1,"a":2,"c":{"z":true,"y":false}}`),
    '{\n  "a": 2,\n  "b": 1,\n  "c": {\n    "y": false,\n    "z": true\n  }\n}\n'
  );
});

test("数字形态保形：1 / 1.0 / 1e2 / -0 / 大整数", () => {
  const got = canonicalizeText(`{"a":1,"b":1.0,"c":1e2,"d":-0,"big":9007199254740993}`);
  for (const want of [`"a": 1,`, `"b": 1.0,`, `"c": 1e2,`, `"d": -0\n`, `"big": 9007199254740993,`]) {
    assert.ok(got.includes(want), `缺 ${want}\n得 ${got}`);
  }
});

test("转义归一：\\u0041→A；HTML 字符不转义；U+2028/2029 恒转义", () => {
  const got = canonicalizeText(`{"s":"\\u0041","h":"<a&b>","l":"a\\u2028b\\u2029c"}`);
  assert.ok(got.includes(`"s": "A"`));
  assert.ok(got.includes(`"h": "<a&b>"`));
  assert.ok(got.includes(`"l": "a\\u2028b\\u2029c"`));
});

test("幂等：规范形再归一不变", () => {
  const once = canonicalizeText(`{"z":[3,1,{"k":null}],"a":"中","n":1.50}`);
  assert.equal(canonicalizeText(once), once);
});

test("非法 JSON 拒绝", () => {
  for (const bad of ["{", `{"a":}`, "not json", "", "[1,2,"]) {
    assert.throws(() => canonicalizeText(bad), /非法 JSON|尾随/);
  }
});

test("多 JSON 值拒绝", () => {
  assert.throws(() => canonicalizeText(`{"a":1}{"b":2}`), /多个 JSON 值/);
});

test("数组顺序保持", () => {
  assert.equal(canonicalizeText("[3,1,2]"), "[\n  3,\n  1,\n  2\n]\n");
});

test("空容器与标量形态", () => {
  assert.equal(canonicalizeText("{}"), "{}\n");
  assert.equal(canonicalizeText("[]"), "[]\n");
  assert.equal(canonicalizeText("null"), "null\n");
  assert.equal(canonicalizeText(" 1.0 "), "1.0\n");
});

test("键排序走 UTF-8 字节序（非 UTF-16 code unit）", () => {
  // UTF-8: U+FFFF = EF BF BF < 😀 = F0 9F 98 80；UTF-16 排序则相反
  const got = canonicalizeText(`{"😀":1,"\uFFFF":2}`);
  assert.equal(got, '{\n  "\uFFFF": 2,\n  "😀": 1\n}\n');
});

test("重复键后者覆盖（Go map 解码口径）", () => {
  assert.equal(canonicalizeText(`{"a":1,"a":2}`), '{\n  "a": 2\n}\n');
});

// ── #292 批：RawMessage 语义面（libc_boot_diff 的 proj_sha 保真前提）──────

test("parseRawJson：每个值带原始切片（空白/转义不改写）", () => {
  const doc = parseRawJson('{"a" : [ 1 ,"x\\u0041"] , "b":{"k":1}}');
  assert.ok(doc instanceof JsonRaw);
  const root = (doc as JsonRaw).value as Map<string, JsonValue>;
  const a = root.get("a") as JsonRaw;
  assert.equal(a.raw, '[ 1 ,"x\\u0041"]', "原始切片逐字保留（含内部空白与 \\u 转义）");
  const b = root.get("b") as JsonRaw;
  assert.equal(b.raw, '{"k":1}');
});

test("compactGoJson：去字符串外空白 + HTML 字符转义 + 既有转义保留", () => {
  assert.equal(compactGoJson('{ "a" : [ 1 , 2 ] }'), '{"a":[1,2]}');
  assert.equal(compactGoJson('{"s":"a<b>&c"}'), '{"s":"a\\u003cb\\u003e\\u0026c"}');
  assert.equal(compactGoJson('{"s":"x\\u0041y"}'), '{"s":"x\\u0041y"}', "既有转义原样保留（compact 不重写）");
  assert.equal(compactGoJson('{"s":"\\""}'), '{"s":"\\""}', "转义引号不误判字符串结束");
});

test("embedText / emitSortedObject：内嵌形态取 RawMessage 原文，仅该层键排序", () => {
  const doc = parseRawJson('{"z":{"line":0,"column":1},"a":1}') as JsonRaw;
  const m = doc.value as Map<string, JsonValue>;
  const entries = new Map<string, string>();
  for (const [k, v] of m) entries.set(k, embedText(v));
  assert.equal(
    emitSortedObject(entries),
    '{"a":1,"z":{"line":0,"column":1}}',
    "顶层键排序，但 z 的内层键**保持原序**（全层重排会破 proj_sha）",
  );
});
