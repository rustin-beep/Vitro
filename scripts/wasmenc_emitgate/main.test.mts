// wasmenc_emitgate 单测（#273 四件套 node:test 面）——不依赖 exe 构建
//（真跑路径上的重面），锁纯函数件 + **wabt 内容级验证器的 J9 锚**
// （批 2a：合法模块过 / 类型错·栈下溢模块必红——「readWasm 只解码、
// validate 才校验」的护栏自证；空 module 字段 = 产物形态破损必红）。
import assert from "node:assert/strict";
import test from "node:test";
import { judgeLines, loadWabtValidate, uleb } from "./main.mts";

test("uleb：单字节/多字节/边界", () => {
  assert.deepEqual(uleb(0), [0x00]);
  assert.deepEqual(uleb(6), [0x06]);
  assert.deepEqual(uleb(127), [0x7f]);
  assert.deepEqual(uleb(128), [0x80, 0x01]);
  assert.deepEqual(uleb(624485), [0xe5, 0x8e, 0x26]);
});

test("judgeLines：ok 例走验证 / emit 失败必红 / deferred 豁免 / 编译失败不判红", () => {
  const validateOk = (_hex: string, _file: string): string | null => null;
  const validateBad = (_hex: string, _file: string): string | null => "bad magic";
  const lines = [
    { file: "a.c", ok: true, module: "0061736d01000000" },
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
  // 验证器红：ok 例也变红（垫收模块非合法 wasm 即红）
  const j3 = judgeLines(lines, "baseline", new Set<string>(["baseline/b.c", "baseline/d.c"]), validateBad);
  assert.equal(j3.reds.length, 1);
  assert.ok(j3.reds[0]?.includes("a.c") && j3.reds[0]?.includes("bad magic"), j3.reds[0] ?? "");
});

/// 最小合法模块（magic+version + type ()->() + function + code〔空体〕
/// ——垫收空程序的同构缩小版）
const MINIMAL = "0061736d01000000010401600000030201000a040102000b";

/// 栈下溢模块（type ()->() + code = [i32.add]——批 1c 证人壳直塞片段的
/// 原型形态：readWasm 解码过、validate 必红——审阅 P1-2 探针的常驻锚）
function underflowModule(): string {
  const body = [0x00, 0x6a, 0x0b]; // locals 0 runs + i32.add + end
  const code = [0x01, 0x03, ...body];
  const header = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
  const typeSeg = [0x01, 0x04, 0x01, 0x60, 0x00, 0x00];
  const funcSeg = [0x03, 0x02, 0x01, 0x00];
  const codeSeg = [0x0a, code.length, ...code];
  return Buffer.from([...header, ...typeSeg, ...funcSeg, ...codeSeg]).toString("hex");
}

test("loadWabtValidate：合法过 / 栈下溢必红 / 空字段必红（J9）", async () => {
  const validate = await loadWabtValidate();
  // 合法最小模块过
  assert.equal(validate(MINIMAL, "t.c"), null);
  // 栈下溢：validate 红（解码级过、内容级红——本闸升级的核心自证）
  const err = validate(underflowModule(), "t.c");
  assert.notEqual(err, null, "栈下溢模块必须 validate 红");
  // 空 module 字段（产物形态破损）必红
  assert.notEqual(validate("", "t.c"), null);
  // 合法模块翻转一字节 → 必红（J9：验证器有牙）
  const flipped = Buffer.from(MINIMAL, "hex");
  flipped.set([flipped[flipped.length - 1]! ^ 0x01], flipped.length - 1);
  assert.notEqual(validate(flipped.toString("hex"), "t.c"), null);
});
