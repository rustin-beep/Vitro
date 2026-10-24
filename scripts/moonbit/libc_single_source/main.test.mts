// libc_single_source.test.mts —— 锚点切片 / 四判据红路（内存注入）+ 真实仓库三模式
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { intersectOf, loadRules, mustTable, sliceByAnchors, unionOf, verdict } from "./main.mts";
import type { RulesDoc, Table } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

function tbl(name: string, names: string[]): Table {
  return { name, names, set: new Set(names), dupes: [], srcPath: "(fixture)" };
}

test("sliceByAnchors：anchor_end 命中 / 缺 anchor_start / 缺 anchor_end 三路", () => {
  const spec = { file: "f", anchor_start: "BEGIN", anchor_end: "END", kind: "string_list" };
  assert.deepEqual(sliceByAnchors("xx BEGIN aaaa END yy", spec), { body: " aaaa " });
  assert.match(sliceByAnchors("no anchor", spec).error ?? "", /anchor_start 未命中/);
  assert.match(sliceByAnchors("BEGIN only", spec).error ?? "", /anchor_end 未命中/);
});

test("sliceByAnchors：无 anchor_end 时用「下一个顶层 fn」收尾", () => {
  const spec = { file: "f", anchor_start: "BEGIN", anchor_end: "", kind: "match_arms" };
  const text = "BEGIN\n  \"a\" => Some(X),\nfn next() {\n  \"b\" => Some(Y),\n";
  assert.equal(sliceByAnchors(text, spec).body, "\n  \"a\" => Some(X),\n");
});

test("真实规则：四表提取非空且与交集/并集自洽", () => {
  const rd = loadRules();
  const b = mustTable(rd, "builtin_all");
  const h = mustTable(rd, "host_names");
  const bc = mustTable(rd, "bytecode_names");
  const p = mustTable(rd, "pure_names");
  for (const t of [b, h, bc, p]) {
    assert.ok(t.names.length > 0, t.name);
    assert.deepEqual(t.dupes, [], t.name);
  }
  assert.equal(verdict(b, h, bc, p, rd), true, "真实四表应满足四判据");
  assert.equal(intersectOf(h, bc).length, rd.expect.host_intersect_bytecode);
  assert.ok(unionOf(h, bc).length >= b.names.length);
});

test("J9 红①：builtin_all 抽掉并集首名 → [等式] 缺失", () => {
  const rd = loadRules();
  const b = mustTable(rd, "builtin_all");
  const h = mustTable(rd, "host_names");
  const bc = mustTable(rd, "bytecode_names");
  const p = mustTable(rd, "pure_names");
  const victim = unionOf(h, bc)[0]!;
  const reduced = tbl(b.name, b.names.filter((n) => n !== victim));
  assert.equal(verdict(reduced, h, bc, p, rd), false);
});

test("J9 红②：空集不得绿 / 重复名必红", () => {
  const rd = loadRules();
  const b = mustTable(rd, "builtin_all");
  const h = mustTable(rd, "host_names");
  const bc = mustTable(rd, "bytecode_names");
  const p = mustTable(rd, "pure_names");
  assert.equal(verdict(tbl("builtin_all", []), h, bc, p, rd), false, "空集必须红");
  const dup = tbl(b.name, [...b.names, b.names[0]!]);
  dup.dupes = [`${b.names[0]}×2`];
  assert.equal(verdict(dup, h, bc, p, rd), false, "重复名必须红");
});

test("J9 红③：交集计数被改 → 判红", () => {
  const rd = loadRules();
  const b = mustTable(rd, "builtin_all");
  const h = mustTable(rd, "host_names");
  const bc = mustTable(rd, "bytecode_names");
  const p = mustTable(rd, "pure_names");
  const wrong: RulesDoc = { ...rd, expect: { host_intersect_bytecode: rd.expect.host_intersect_bytecode + 1 } };
  assert.equal(verdict(b, h, bc, p, wrong), false);
});

test("真实仓库端到端：默认 / -check / --selftest 全绿；未知参数 exit 2", () => {
  const root = projectRoot();
  for (const args of [[], ["-check"], ["--selftest"]]) {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
    assert.equal(r.status, 0, `${args.join(" ") || "(默认)"}: ${r.stdout}${r.stderr}`);
  }
  const bad = spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" });
  assert.equal(bad.status, 2);
});
