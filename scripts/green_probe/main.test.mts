// green_probe 单测（node:test，纪律 8 四件套）
import test from "node:test";
import assert from "node:assert/strict";
import { armDivergence, errorCount, parseDiagLine, signatureOf, type ArmResult, type Diag } from "./main.mts";

const diag = (code: string, severity: string, line: number, col: number, msg: string): Diag => ({
  code,
  severity,
  line,
  column: col,
  message: msg,
});

test("parseDiagLine 提取 diag 帧", () => {
  const out = 'noise\n{"type":"diag","frame":{"id":3,"ok":true,"result":{"ok":true,"diagnostics":[],"file_ranges":[]}}}\n';
  const r = parseDiagLine(out);
  assert.notEqual(r, null);
  assert.equal(r?.ok, true);
  assert.equal(r?.diagnostics.length, 0);
});

test("parseDiagLine 拒垃圾与缺帧", () => {
  assert.equal(parseDiagLine("hello"), null);
  assert.equal(parseDiagLine('{"type":"other"}'), null);
  assert.equal(parseDiagLine('{"type":"diag","broken"'), null);
});

test("errorCount 只数 error", () => {
  const ds = [diag("E1", "error", 1, 1, "a"), diag("W1", "warning", 2, 2, "b"), diag("E2", "error", 3, 3, "c")];
  assert.equal(errorCount(ds), 2);
});

test("signatureOf 顺序无关（排序投影）", () => {
  const a = [diag("E1", "error", 1, 1, "x"), diag("W1", "warning", 2, 2, "y")];
  const b = [diag("W1", "warning", 2, 2, "y"), diag("E1", "error", 1, 1, "x")];
  assert.equal(signatureOf(a), signatureOf(b));
  const c = [diag("E1", "error", 1, 1, "x")];
  assert.notEqual(signatureOf(a), signatureOf(c));
});

test("armDivergence 一致/分叉", () => {
  const mk = (sig: string): ArmResult => ({ ok: true, detail: "", signature: sig });
  const same = new Map<string, ArmResult>([
    ["js", mk("s1")],
    ["native", mk("s1")],
    ["wasm", mk("s1")],
  ]);
  assert.equal(armDivergence(same), null);
  const diff = new Map<string, ArmResult>([
    ["js", mk("s1")],
    ["native", mk("s2")],
    ["wasm", mk("s1")],
  ]);
  const d = armDivergence(diff);
  assert.notEqual(d, null);
  assert.match(d as string, /native/);
  assert.match(d as string, /js\+wasm/);
});
