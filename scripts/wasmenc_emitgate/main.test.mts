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

/// 带唯一 import 的最小可执行模块（PR #512 审阅 P1-1 的实例化冒烟形态：
/// 本地 main 体返回 42；export main 的函数索引由 goodIndex 参数给定——
/// 正确值 = import 函数数(1) + 本地序号(0) = 1，错误值 0 = import 本身）
function moduleWithImport(goodIndex: number): number[] {
  const body = [0x00, 0x41, 0x2a, 0x0b]; // locals 0 + i32.const 42(sleb 单字节) + end
  const code = [0x01, body.length, ...body];
  const seg = (id: number, payload: ReadonlyArray<number>): number[] => [id, payload.length, ...payload];
  return [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    ...seg(0x01, [0x02, 0x60, 0x00, 0x00, 0x60, 0x00, 0x01, 0x7f]), // type: ()->() 与 ()->i32
    ...seg(0x02, [0x01, 0x03, ...[..."env"].map((c) => c.charCodeAt(0)), 0x0f, ...[..."vitro_host_call"].map((c) => c.charCodeAt(0)), 0x00, 0x00]), // import env.vitro_host_call ()->() @0
    ...seg(0x03, [0x01, 0x01]), // function: 本地 1 个, type idx 1 (()->i32)
    ...seg(0x07, [0x01, 0x04, ...[..."main"].map((c) => c.charCodeAt(0)), 0x00, goodIndex]),
    ...seg(0x0a, code),
  ];
}

test("实例化冒烟：导出 main 必须指向本地函数体而非 import（P1-1）", async () => {
  const wabtInit = (await import("wabt")).default;
  const wabt = await wabtInit();
  let hostCalls = 0;
  const instantiate = async (idx: number): Promise<{ ret: unknown; hostCalls: number }> => {
    const mod = moduleWithImport(idx);
    const m = wabt.readWasm(new Uint8Array(mod), {});
    try {
      m.validate();
    } finally {
      m.destroy();
    }
    hostCalls = 0;
    const inst = await WebAssembly.instantiate(new Uint8Array(mod), {
      // 桩签名与 import type idx 0（()->()）对齐——被调即计数（错误索引
      // 形态下 main() 返回 undefined，判定只看 hostCalls 与本地返回值）
      env: { vitro_host_call: (): void => { hostCalls += 1; } },
    });
    const main = (inst.instance.exports as { main: () => unknown }).main;
    return { ret: main(), hostCalls };
  };
  // 正确索引 1：本地体执行（i32.const 42），宿主零调用
  const good = await instantiate(1);
  assert.equal(good.ret, 42);
  assert.equal(good.hostCalls, 0);
  // 错误索引 0（修前形态）：validate 全绿但 main 落到 import——宿主被调
  // ——引擎行为锚：指向错实体验证器不拦，实例化冒烟才拦
  const bad = await instantiate(0);
  assert.equal(bad.hostCalls, 1);
});
