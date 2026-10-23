// gen_protocol_ts.test.mts —— 类型映射 / 花括号配对 / 文档表格解析 / 双向对账 J9 /
// 生成形态 / 真实仓库 -check 与 -selftest。
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  blockBody,
  fieldSetMismatch,
  genMeta,
  genTS,
  parseDocFields,
  parseMoonbitTypes,
  tsTypeMB,
  type ProtoType,
  type RulesDoc,
  type TypeSpec,
} from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

function rd(types: TypeSpec[]): RulesDoc {
  return {
    schema: 1,
    schema_version: "0.1",
    frozen_anchor: "abc1234",
    schema_doc: "docs/spec/X.md",
    type_sources: ["mbt"],
    types,
    out_ts: "out.d.ts",
    out_meta: "out.mjs",
  };
}

test("tsTypeMB：标量折叠 / Array 泛型括号 / 可空后缀", () => {
  assert.equal(tsTypeMB("Int"), "number");
  assert.equal(tsTypeMB("Int32"), "number");
  assert.equal(tsTypeMB("UInt64"), "number");
  assert.equal(tsTypeMB("Double"), "number");
  assert.equal(tsTypeMB("String"), "string");
  assert.equal(tsTypeMB("Bool"), "boolean");
  assert.equal(tsTypeMB("Array[Int]"), "number[]");
  // 联合类型进数组必须加括号（否则 TS 解析歧义）
  assert.equal(tsTypeMB("Array[String?]"), "(string | null)[]");
  assert.equal(tsTypeMB("Int?"), "number | null");
  assert.equal(tsTypeMB("Array[Array[Bool]]"), "boolean[][]");
  // 未知类型原样透传（协议层自定义类型由同名 interface 承接）
  assert.equal(tsTypeMB("PointerSnapshot"), "PointerSnapshot");
});

test("blockBody：花括号配对（嵌套 / 不配对）", () => {
  const src = "pub(all) struct A { x : Int }";
  const head = src.indexOf("{");
  assert.deepEqual(blockBody(src, head), { body: " x : Int ", ok: true });
  assert.deepEqual(blockBody("pub(all) struct A { x : Int ", head), { body: "", ok: false });
  const nested = "pub(all) struct A { a : Array[Int] }";
  assert.deepEqual(blockBody(nested, nested.indexOf("{")), {
    body: " a : Array[Int] ",
    ok: true,
  });
});

test("parseMoonbitTypes：字段/变体提取 + 元组 fail loud + 空集 fail loud", () => {
  const src = [
    "pub(all) struct Foo {",
    "  a : Int",
    "  mut b : String",
    "}",
    "",
    "pub(all) enum Bar {",
    "  Ok // 注释",
    "  // 纯注释行",
    "  Failed",
    "}",
  ].join("\n");
  const want = new Map<string, TypeSpec>([
    ["Foo", { name: "Foo", kind: "struct" }],
    ["Bar", { name: "Bar", kind: "enum" }],
  ]);
  const got = parseMoonbitTypes(["src.mbt"], want, () => src);
  assert.deepEqual(
    got.get("Foo")?.fields.map((f) => [f.name, f.ty]),
    [
      ["a", "Int"],
      ["b", "String"],
    ],
  );
  assert.deepEqual(got.get("Bar")?.variants, ["Ok", "Failed"]);

  assert.throws(
    () =>
      parseMoonbitTypes(["src.mbt"], new Map([["T", { name: "T", kind: "struct" }]]), () =>
        "pub(all) struct T {\n  x : (Int, Int)\n}",
      ),
    /元组形态/,
  );
  assert.throws(
    () =>
      parseMoonbitTypes(["src.mbt"], new Map([["T", { name: "T", kind: "struct" }]]), () =>
        "pub(all) struct T {\n}",
      ),
    /0 字段/,
  );
  assert.throws(
    () =>
      parseMoonbitTypes(["src.mbt"], new Map([["T", { name: "T", kind: "struct" }]]), () =>
        "pub(all) struct Other {\n  x : Int\n}",
      ),
    /找不到 pub\(all\) 定义/,
  );
});

test("parseDocFields：标题绑定已知类型 + 首个表格截止", () => {
  const doc = [
    "## 1. `Foo`",
    "",
    "| 字段 | 类型 |",
    "| --- | --- |",
    "| `a` | Int |",
    "| `b` | Int |",
    "",
    "| 第二张表 | 不该混入 |",
    "| --- | --- |",
    "| `ghost` | x |",
    "## 2. 与已知类型无关的标题",
    "| `zombie` | x |",
  ].join("\n");
  const got = parseDocFields(doc, new Set(["Foo"]));
  assert.deepEqual([...(got.get("Foo") ?? [])].sort(), ["a", "b"]);
  assert.equal(got.size, 1);
});

test("字段集双向对账：实现多字段 / 文档多字段 / 文档缺表 三路皆红", () => {
  const types = new Map<string, ProtoType>([
    ["Foo", { name: "Foo", kind: "struct", fields: [{ name: "a", ty: "Int" }, { name: "b", ty: "Int" }], variants: [], source: "s" }],
  ]);
  const r = rd([{ name: "Foo", kind: "struct" }]);
  assert.deepEqual(fieldSetMismatch(r, types, new Map([["Foo", new Set(["a", "b"])]])), []);
  assert.match(fieldSetMismatch(r, types, new Map([["Foo", new Set(["a"])]]))[0] ?? "", /实现有字段 b|Rust 有字段 b/);
  assert.match(fieldSetMismatch(r, types, new Map([["Foo", new Set(["a", "b", "c"])]]))[0] ?? "", /文档列了 c/);
  assert.match(fieldSetMismatch(r, types, new Map())[0] ?? "", /找不到该类型的字段表/);
});

test("genTS：枚举字典序在前、struct 按 rules 声明序；genMeta 字段集形态", () => {
  const r = rd([
    { name: "ZStruct", kind: "struct" },
    { name: "AEnum", kind: "enum" },
  ]);
  const types = new Map<string, ProtoType>([
    ["ZStruct", { name: "ZStruct", kind: "struct", fields: [{ name: "z", ty: "Bool" }], variants: [], source: "s.mbt" }],
    ["AEnum", { name: "AEnum", kind: "enum", fields: [], variants: ["X", "Y"], source: "s.mbt" }],
  ]);
  const ts = genTS(r, types);
  assert.match(ts, /export const SCHEMA_VERSION = "0.1";/);
  assert.match(ts, /export interface ZStruct \{\n  z: boolean;\n\}/);
  assert.match(ts, /export const AEnum = \{\n  X: "X",\n  Y: "Y",\n\} as const;/);
  assert.match(ts, /export type AEnum = \(typeof AEnum\)\[keyof typeof AEnum\];/);
  // enum 段在 struct 段之后（消费顺序友好）
  assert.ok(ts.indexOf("export interface ZStruct") < ts.indexOf("export const AEnum"));

  const meta = genMeta(r, types);
  assert.match(meta, /export const ENUMS = \{\n  AEnum: \["X", "Y"\],\n\};/);
  assert.match(meta, /export const FIELDS = \{\n  ZStruct: \["z"\],\n\};/);
});

test("真实仓库：-check 通过（产物新鲜 + 双向对账）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /PASS——产物新鲜/);
});

test("真实仓库：-selftest 三路注入全红", () => {
  const r = spawnSync(
    process.execPath,
    [path.join(import.meta.dirname, "main.mts"), "-selftest"],
    { cwd: projectRoot(), encoding: "utf8" },
  );
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /selftest PASS——3 路注入全部判红/);
});
