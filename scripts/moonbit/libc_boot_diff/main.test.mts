// libc_boot_diff.test.mts —— export 口径过滤 + 投影字节保真 + CLI 端到端（.mts 重写批）。
//
// 重点锚（本批实锤过的坑）：Go `json.Unmarshal→map[string]RawMessage→json.Marshal`
// 只排序**被解码成 map 的那一层**，嵌套值以原始字节内嵌。全层重排会改写
// `{"loc":{"line":…,"column":…}}` 内层顺序 → proj_sha 立刻对不上（首版即此红）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { canonicalizeText, parseRawJson, emitSortedObject, embedText, JsonRaw } from "../../internal/canonicalize.mts";
import type { JsonValue } from "../../internal/canonicalize.mts";
import { projectRoot } from "../../internal/capi.mts";
import { fileSHA8, filterExport, injectOperand, listC, project, projectRaw } from "./main.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

const DUMP = `{"code":[{"op":"Jump","operand":2,"loc":{"line":0,"column":0,"file_id":0}},{"op":"Nop","operand":0},{"op":"StepEvent","operand":3,"loc":{"line":3,"column":20,"file_id":0}}],"func_table":{"main":{"a":1},"f":{"b":2}},"func_index":{"main":0,"f":1},"version":1,"big":9007199254740993}`;

const KEYS = ["version", "code", "func_table", "func_index", "big"];

test("filterExport：code[0] 为 Jump → 按 wrapper_ip 截断 + code[0] 置 Nop", () => {
  const { fields, wrapperIP, codeLen } = filterExport(parseRawJson(DUMP));
  assert.equal(wrapperIP, 2);
  assert.equal(codeLen, 2, "截断到 wrapper_ip=2");
  const code = fields.get("code") ?? "";
  assert.ok(code.startsWith('[{"loc":{"line":0,"column":0,"file_id":0},"op":"Nop","operand":0}'), `code 首条应为词排序后的 Nop：${code.slice(0, 80)}`);
  assert.ok(!code.includes("Jump"));
});

test("filterExport：嵌套对象内层键序保持原序（顶层才排序）——proj_sha 保真的核心", () => {
  const { fields } = filterExport(parseRawJson(DUMP));
  const code = fields.get("code") ?? "";
  // loc 原文序 line,column,file_id —— 若被全层排序会变 column,file_id,line
  assert.ok(code.includes('"loc":{"line":0,"column":0,"file_id":0}'), code.slice(0, 120));
  assert.ok(!code.includes('"loc":{"column":0,"file_id":0,"line":0}'), "禁止全层重排");
});

test("filterExport：func_table / func_index 删 main，其余键保留", () => {
  const { fields } = filterExport(parseRawJson(DUMP));
  assert.equal(fields.get("func_table"), '{"f":{"b":2}}');
  assert.equal(fields.get("func_index"), '{"f":1}');
});

test("filterExport：无 Jump 首指令 → 不截断，code 全量保留", () => {
  const dump = `{"code":[{"op":"Nop","operand":0},{"op":"StepEvent","operand":1}]}`;
  const r = filterExport(parseRawJson(dump));
  assert.equal(r.wrapperIP, -1);
  assert.equal(r.codeLen, 2);
});

test("project：空投影抛错（compare_fields 与产物键全不匹配 = fail loud）", () => {
  const { fields } = filterExport(parseRawJson(DUMP));
  assert.throws(() => project(fields, ["no_such_field"]), /投影后无字段/);
  assert.equal(project(fields, ["version"]).size, 1);
});

test("projectRaw：键排序 + 大整数 token 原样（不丢末位）", () => {
  const { fields } = filterExport(parseRawJson(DUMP));
  const bytes = projectRaw(fields, ["version", "big"]).toString("utf8");
  assert.equal(bytes, '{"big":9007199254740993,"version":1}', "9007199254740993 逐字保留（JSON.parse 会丢末位）");
});

test("injectOperand：code[1].operand +1（J9 埋雷面）", () => {
  const { fields } = filterExport(parseRawJson(DUMP));
  const before = projectRaw(fields, KEYS).toString("utf8");
  const inj = injectOperand(fields);
  assert.equal(inj.ok, true);
  const after = projectRaw(inj.fields, KEYS).toString("utf8");
  assert.notEqual(after, before, "注入后投影必须变化（否则 selftest 无判别力）");
  assert.ok(after.includes('"operand":1'), "code[1].operand 0 → 1");
});

test("injectOperand：code 段不足 / operand 非数值 → ok=false（不静默放行）", () => {
  const f1 = filterExport(parseRawJson(`{"code":[{"op":"Nop","operand":0}]}`)).fields;
  assert.equal(injectOperand(f1).ok, false);
  const f2 = filterExport(parseRawJson(`{"code":[{"op":"Nop","operand":0},{"op":"X","operand":"nope"}]}`)).fields;
  assert.equal(injectOperand(f2).ok, false);
});

test("fileSHA8：CRLF 与 LF 同值（Go bytes.ReplaceAll 口径）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lb-sha-"));
  const lf = path.join(dir, "lf.c");
  const crlf = path.join(dir, "crlf.c");
  fs.writeFileSync(lf, "int a;\nint b;\n");
  fs.writeFileSync(crlf, "int a;\r\nint b;\r\n");
  assert.equal(fileSHA8(lf), fileSHA8(crlf));
  assert.equal(fileSHA8(lf).length, 8);
});

test("listC：只收 .c 且按字节序", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lb-list-"));
  for (const n of ["b.c", "a.c", "z.h", "C.c"]) fs.writeFileSync(path.join(dir, n), "");
  assert.deepEqual(
    listC(dir).map((p) => path.basename(p)),
    ["C.c", "a.c", "b.c"],
    "字节序（大写在前）+ 排除 .h",
  );
});

test("e2e：golden 基线模式全绿（缺 moon 工具链显式 skip）", (t) => {
  const moon = spawnSync("moon", ["version"], { encoding: "utf8" });
  if (moon.status !== 0) {
    t.diagnostic("skip：moon 不在 PATH");
    return;
  }
  const r = spawnSync(process.execPath, [MAIN], { cwd: projectRoot(), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /libc_boot_diff: 对拍 scripts\/moonbit\/libc_src\/src（3 个 C 源）/);
  assert.match(r.stdout, /libc_boot_diff\[golden\]: SAME=3 DIFF=0（3 源）/);
  assert.match(r.stdout, /libc_boot_diff\[golden\]: PASS/);
});

test("e2e：--freeze/--golden 互斥 exit 2（写盘通道不静默）", () => {
  const r = spawnSync(process.execPath, [MAIN, "--freeze", "--golden"], { encoding: "utf8" });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /互斥/);
});

test("e2e：未知参数 exit 2", () => {
  const r = spawnSync(process.execPath, [MAIN, "--nope"], { encoding: "utf8" });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /未知参数: --nope/);
});

// 保数字形态与 canonicalize 的协同面（投影 → 归一）
test("投影结果可直接喂归一器（比对面连通）", () => {
  const { fields } = filterExport(parseRawJson(DUMP));
  const canon = canonicalizeText(projectRaw(fields, ["version", "big"]).toString("utf8"));
  assert.ok(canon.includes('"big": 9007199254740993'));
  assert.ok(canon.startsWith("{\n  \"big\""));
});

// 直接验证「内嵌文本」不被二次改写（JsonRaw → embedText 的契约）
test("embedText：JsonRaw 取原文 compact——内层键序不参与排序", () => {
  const root = parseRawJson('{"z":{"line":0,"column":1}}') as JsonRaw;
  const inner = root.value as Map<string, JsonValue>;
  assert.equal(embedText(inner.get("z") as JsonValue), '{"line":0,"column":1}');
  assert.ok(emitSortedObject(new Map([["z", embedText(inner.get("z") as JsonValue)]])).includes('"line":0,"column":1'));
});
