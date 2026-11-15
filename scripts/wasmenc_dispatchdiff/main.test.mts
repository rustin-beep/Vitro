// wasmenc_dispatchdiff 判定核锚（node:test——不依赖 exe 构建；纯函数
// 注入形态锁 judgeCase/parseWasmtimeLine 分支矩阵）。
import test from "node:test";
import assert from "node:assert/strict";
import { judgeCase, parseWasmtimeLine, type RuntimeArmResult, type EngineArmResult } from "./main.mts";

function arm(kind: "ok" | "trap" | "host", rc?: number, steps = 9): RuntimeArmResult {
  return { kind, rc, steps };
}

function eng(status: string, rv: number | undefined, steps: number, trapCode = ""): EngineArmResult {
  return { status, returnValue: rv, trapCode, steps, stdout: Buffer.alloc(0) };
}

test("judgeCase：三方全同绿 / rc·steps 分叉红", () => {
  assert.equal(judgeCase("a.c", arm("ok", 7), arm("ok", 7), eng("finished", 7, 9)), null);
  assert.match(judgeCase("a.c", arm("ok", 7), arm("ok", 8), eng("finished", 7, 9))!, /rc 分叉/);
  assert.match(judgeCase("a.c", arm("ok", 7), arm("ok", 7), eng("finished", 7, 10))!, /steps 分叉/);
});

test("judgeCase：trap 三方同类别绿（steps 豁免——块批量计步 overshoot ≤1 块）", () => {
  assert.equal(judgeCase("a.c", arm("trap", undefined, 28), arm("trap", undefined, 28), eng("trap", 0, 17, "E3086")), null);
});

test("judgeCase：终态类别分叉红（引擎 trap vs V8 finished）", () => {
  assert.match(
    judgeCase("a.c", arm("ok", 0), arm("ok", 0), eng("trap", 0, 17, "E3086"))!,
    /终态类别分叉/,
  );
});

test("judgeCase：预算例（V8 -1 ↔ 引擎 E3091）归一绿 + 单侧预算红", () => {
  // 三方同预算形态：V8/wasmtime ok -1、引擎 trap E3091
  assert.equal(judgeCase("a.c", arm("ok", -1), arm("ok", -1), eng("trap", 0, 10000001, "E3091")), null);
  // V8 预算但 wasmtime 正常跑完 = 类别分叉
  assert.match(
    judgeCase("a.c", arm("ok", -1), arm("ok", 0), eng("trap", 0, 10000001, "E3091"))!,
    /终态类别分叉/,
  );
});

test("judgeCase：host 桩被调必红（零 host 子集运行期违约）", () => {
  assert.match(judgeCase("a.c", arm("host", undefined, 3), arm("ok", 7), eng("finished", 7, 9))!, /host 桩被调/);
});

test("judgeCase：stdout 非空红（零 host 例两侧恒空断言）", () => {
  const e = eng("finished", 7, 9);
  e.stdout = Buffer.from("x");
  assert.match(judgeCase("a.c", arm("ok", 7), arm("ok", 7), e)!, /stdout 非空/);
});

test("parseWasmtimeLine：ok/trap/host 三形态 + 非法行 null", () => {
  assert.deepEqual(parseWasmtimeLine("ok 8 9"), { kind: "ok", rc: 8, steps: 9 });
  assert.deepEqual(parseWasmtimeLine("ok -1 10000000"), { kind: "ok", rc: -1, steps: 10000000 });
  assert.deepEqual(parseWasmtimeLine("trap 28 RuntimeError: unreachable"), { kind: "trap", steps: 28 });
  assert.deepEqual(parseWasmtimeLine("host 3"), { kind: "host", steps: 3 });
  assert.equal(parseWasmtimeLine("garbage"), null);
  assert.equal(parseWasmtimeLine(""), null);
  // bad 行（PR #526 审阅 P2-4——逐例 catch 形态，steps=-1 哨兵 + badCompile）
  const bad = parseWasmtimeLine("bad Invalid input WebAssembly code at offset 561");
  assert.ok(bad !== null);
  assert.equal(bad.kind, "trap");
  assert.equal(bad.steps, -1);
  assert.match(bad.badCompile ?? "", /offset 561/);
});

test("judgeCase：合法返回 -1 走 finished 对拍不误报（P2-1——预算归一与 E3091 绑定）", () => {
  // 引擎 finished rv=-1 + 双 runtime ok -1 = 合法返回值，非预算态
  assert.equal(judgeCase("ret_minus1.c", arm("ok", -1), arm("ok", -1), eng("finished", -1, 9)), null);
  // 引擎预算 E3091 + 双 runtime ok -1 = 预算归一态（绿）
  assert.equal(judgeCase("b.c", arm("ok", -1), arm("ok", -1), eng("trap", 0, 10000001, "E3091")), null);
  // 引擎预算但 V8 正常返回 0 = 真终态分叉（红——保留检出力）
  assert.match(
    judgeCase("c.c", arm("ok", 0), arm("ok", 0), eng("trap", 0, 10000001, "E3091"))!,
    /终态类别分叉/,
  );
});
