// main.test.mts —— CLI 壳契约锚（Go main_test.go 逐条移植）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { run } from "./main.mts";

const canonicalJSON = '{\n  "a": 2\n}\n';

function invoke(args: string[], stdin: string): { code: number; out: string; err: string } {
  return run(args, Buffer.from(stdin, "utf8"));
}

test("归一路径：规范形写 stdout、exit 0、stderr 静默", () => {
  const r = invoke([], `{"a":2}`);
  assert.equal(r.code, 0);
  assert.equal(r.out, canonicalJSON);
  assert.equal(r.err, "");
});

test("--check 规范形 → exit 0 且不写 stdout", () => {
  const r = invoke(["--check"], canonicalJSON);
  assert.equal(r.code, 0);
  assert.equal(r.out, "");
});

test("--check 首尾空白容忍", () => {
  for (const input of ["{\n  \"a\": 2\n}", "\n{\n  \"a\": 2\n}\n", "  {\n  \"a\": 2\n}  "]) {
    assert.equal(invoke(["--check"], input).code, 0, input);
  }
});

test("--check 乱序键 / 缩进不符 / 紧凑单行 → exit 1", () => {
  assert.equal(invoke(["--check"], `{"b":1,"a":2}`).code, 1);
  assert.equal(invoke(["--check"], '{\n    "a": 2\n}\n').code, 1);
  assert.equal(invoke(["--check"], `{"a":2}`).code, 1);
});

test("--check 非法 JSON / 双值 → exit 1 且零 stdout", () => {
  for (const bad of [`{"a":}`, "not json", `{"a":1}{"b":2}`]) {
    const r = invoke(["--check"], bad);
    assert.equal(r.code, 1, bad);
    assert.equal(r.out, "", bad);
    assert.notEqual(r.err, "", bad);
  }
});

test("归一路径非法 JSON → exit 1 零 stdout", () => {
  const r = invoke([], `{"a":}`);
  assert.equal(r.code, 1);
  assert.equal(r.out, "");
});

test("未知参数 → exit 2；-h/--help → exit 0", () => {
  assert.equal(invoke(["--no-such-flag"], canonicalJSON).code, 2);
  assert.equal(invoke(["-h"], "").code, 0);
  assert.equal(invoke(["--help"], "").code, 0);
});
