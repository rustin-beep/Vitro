// gen_libc_data.test.mts —— Go %v 浮点口径 / opcode 窗口解析 / 产物形态 + 真实 -check。
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { goFormatFloat, parseOpNumbers, renderArtifact } from "./main.mts";
import type { Artifact } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

test("goFormatFloat 对齐 Go fmt %v（shortest eprec=6）", () => {
  const cases: Array<[number, string]> = [
    [0.1, "0.1"],
    [1.5, "1.5"],
    [1e-5, "1e-05"],
    [1e-4, "0.0001"],
    [1e20, "1e+20"],
    [1e21, "1e+21"],
    [123456789012345680000, "1.2345678901234568e+20"],
    [123456789.0, "1.23456789e+08"],
    [-2.5, "-2.5"],
    [0, "0"],
    [3.0, "3"],
    [5e-324, "5e-324"],
    [1.7976931348623157e308, "1.7976931348623157e+308"],
  ];
  for (const [v, want] of cases) assert.equal(goFormatFloat(v), want, String(v));
  assert.equal(goFormatFloat(-0), "-0");
});

function opFixture(count: number): string {
  const arms = Array.from({ length: count }, (_, i) => `    OpCode::Op${i} => ${i}`).join("\n");
  return `pub fn OpCode::code(self) -> Int {\n  match self {\n${arms}\n  }\n}\n`;
}

test("parseOpNumbers：窗口约束 ≥100 臂；重名 fail loud", () => {
  const ops = parseOpNumbers(opFixture(100));
  assert.equal(ops.size, 100);
  assert.equal(ops.get("OpCode::Op42"), 42);
  assert.throws(() => parseOpNumbers(opFixture(99)), /<100/);
  // 重名臂必须在 code() 窗口内（窗口外的同名臂不参与抽取——与 Go 一致）
  const dup = opFixture(100).replace("\n  }\n}\n", "\n    OpCode::Op0 => 5\n  }\n}\n");
  assert.throws(() => parseOpNumbers(dup), /重名臂/);
});

test("renderArtifact：指令/名字/索引/meta/浮点/长度形态", () => {
  const art: Artifact = {
    code: [{ op: "OpCode::Nop", operand: 0, loc: { line: 1, column: 1, file_id: 0 } }],
    code_len: 1,
    func_table: {
      f: { ip: 0, arg_count: 1, param_count: 2, local_count: 2, param_sizes: [8, 8], is_variadic: true },
    },
    func_index: { f: 3 },
    globals_init_32: [[1, 2]],
    globals_init_64: [],
    f64_constants: [123456789.0, 1e-5],
    i64_constants: [],
    string_data: [],
  };
  const out = renderArtifact(art, "abc123", new Map([["OpCode::Nop", 7]]));
  assert.match(out, /source_sha256=abc123/);
  assert.match(out, /\n  7, 0, 1, 1, 0,\n/);
  assert.match(out, /let libc_func_names : Array\[String\] = \[\n  "f",\n\]/);
  assert.match(out, /let libc_func_index : Array\[Int\] = \[\n  3,\n\]/);
  assert.match(out, /\n  0, 1, 2, 2, 1, 2, \/\/ f\n  8,\n  8,\n/);
  assert.match(out, /\n  \(1U, 2\),\n/);
  assert.match(out, /\n  1\.23456789e\+08,\n  1e-05,\n/);
  assert.match(out, /const LIBC_CODE_LEN : Int = 1\n$/);
});

test("真实仓库：-check 通过（与 CI 同门径）", () => {
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-check"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /gen_libc_data: check OK/);
});
