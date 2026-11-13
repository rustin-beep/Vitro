// wasmenc_emitgate 单测（#273 四件套 node:test 面）——不依赖 wabt/exe
//（真跑路径上的重面），此处锁纯函数件：uleb / 证人壳拼装形态 / 判定函数
// 三分支（红→绿锚：emit 失败行必红、deferred 豁免、编译失败不判红）。
import assert from "node:assert/strict";
import test from "node:test";
import { buildWitnessModule, judgeLines, uleb } from "./main.mts";

test("uleb：单字节/多字节/边界", () => {
  assert.deepEqual(uleb(0), [0x00]);
  assert.deepEqual(uleb(6), [0x06]);
  assert.deepEqual(uleb(127), [0x7f]);
  assert.deepEqual(uleb(128), [0x80, 0x01]);
  assert.deepEqual(uleb(624485), [0xe5, 0x8e, 0x26]);
});

test("buildWitnessModule：magic+version 与段形态锚", () => {
  const m = buildWitnessModule([0x01]); // nop
  assert.deepEqual(m.slice(0, 8), [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]);
  // 固定形态字节锚（段序 type(1)→function(3)→memory(5)→global(6)→
  // export(7)→code(10) 由连续 includes 间接锁定）：
  const hex = Buffer.from(m).toString("hex");
  assert.ok(hex.includes("0104" + "016000" + "00"), "type 段 ()->()");
  assert.ok(hex.includes("0302" + "0100"), "function 段单函数 type 0");
  assert.ok(hex.includes("0504" + "01011010"), "memory 段 {16,16}（flag 0x01 双界）");
  assert.ok(hex.includes("061f" + "06"), "global 段 6 条（载荷 0x1f=31 字节：5×i32+1×i64）");
  assert.ok(hex.includes("0708" + "01046d61696e" + "0000"), "export 段 main 函数 0");
  // code 段：函数体以尾 end（0x0b）收（指令区 [0x01] 之后）
  assert.ok(hex.endsWith("0b"), "code 段函数体尾 end");
});

test("judgeLines：ok 例走验证 / emit 失败必红 / deferred 豁免 / 编译失败不判红", () => {
  const validateOk = (_hex: string, _file: string): string | null => null;
  const validateBad = (_hex: string, file: string): string | null => `${file} bad magic`;
  const lines = [
    { file: "a.c", ok: true, hex: "010b" },
    { file: "b.c", ok: false, stage: "emit", gip: 3, op: "TryBegin", reason: "NotImplemented" },
    { file: "c.c", ok: false, stage: "lex", errors: ["1 个词法错误"] },
    { file: "d.c", ok: false, stage: "verify", kind: "GroupMismatch", detail: "组 0" },
  ];
  // 全绿验证器：emit/verify 两红
  const j1 = judgeLines(lines, "baseline", new Set<string>(), validateOk);
  assert.equal(j1.okN, 1);
  assert.equal(j1.compileFail, 1);
  assert.equal(j1.reds.length, 2);
  assert.ok(j1.reds[0]?.includes("b.c") && j1.reds[0]?.includes("TryBegin"), j1.reds[0] ?? "");
  assert.ok(j1.reds[1]?.includes("d.c") && j1.reds[1]?.includes("GroupMismatch"), j1.reds[1] ?? "");
  // deferred 豁免 b.c：只剩 verify 一红
  const j2 = judgeLines(lines, "baseline", new Set<string>(["baseline/b.c"]), validateOk);
  assert.equal(j2.reds.length, 1);
  // 验证器红：ok 例也变红（发射字节非合法 wasm 即红）
  const j3 = judgeLines(lines, "baseline", new Set<string>(["baseline/b.c", "baseline/d.c"]), validateBad);
  assert.equal(j3.reds.length, 1);
  assert.ok(j3.reds[0]?.includes("a.c") && j3.reds[0]?.includes("bad magic"), j3.reds[0] ?? "");
});
