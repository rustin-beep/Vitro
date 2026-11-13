// wasmenc_rundiff 单测（#273 四件套 node:test 面）——judgeCase 判定分支
// （红→绿锚：双绿一致 / stdout·rc·映像不一致红 / fallback 红 / 缺标记
// 非编译失败例红 / 编译失败两臂同形不红 / 超时红）。
import assert from "node:assert/strict";
import test from "node:test";
import { judgeCase } from "./main.mts";

const arm = (over: Partial<{ status: number | null; stdout: Buffer; stderr: string; mem: Buffer | null }>):
  { status: number | null; stdout: Buffer; stderr: string; mem: Buffer | null } => ({
  status: 0,
  stdout: Buffer.alloc(0),
  stderr: "",
  mem: Buffer.alloc(16),
  ...over,
});

test("judgeCase：双绿一致过", () => {
  const leg = arm({ stdout: Buffer.from("hi\n"), mem: Buffer.from([1, 2, 3]) });
  const reh = arm({ stdout: Buffer.from("hi\n"), stderr: "// WASM-REHOST ok groups=3\n", mem: Buffer.from([1, 2, 3]) });
  assert.equal(judgeCase("a.c", leg, reh), null);
});

test("judgeCase：rc/stdout/映像不一致必红", () => {
  const ok = { stderr: "// WASM-REHOST ok groups=3\n" };
  assert.notEqual(judgeCase("a.c", arm({ status: 0 }), arm({ status: 2, ...ok })), null, "rc 不一致红");
  assert.notEqual(judgeCase("a.c", arm({ stdout: Buffer.from("hi") }), arm({ stdout: Buffer.from("HI"), ...ok })), null, "stdout 不一致红");
  assert.notEqual(judgeCase("a.c", arm({ mem: Buffer.from([1]) }), arm({ mem: Buffer.from([2]), ...ok })), null, "映像不一致红");
});

test("judgeCase：fallback 必红（fail loud 面——静默回退会让闸失明）", () => {
  const reh = arm({ stderr: "// WASM-REHOST fallback verify-failed GroupGap gip=1 3→0\n" });
  const red = judgeCase("a.c", arm({}), reh);
  assert.notEqual(red, null);
  assert.ok(red?.includes("fallback"), red ?? "");
});

test("judgeCase：缺标记行——编译失败两臂同形不红 / 其余必红", () => {
  const compLeg = arm({ status: 1, stderr: "// COMPILE-ERROR E1001 1:1 x\n" });
  const compReh = arm({ status: 1, stderr: "// COMPILE-ERROR E1001 1:1 x\n" });
  assert.equal(judgeCase("a.c", compLeg, compReh), null, "编译失败两臂同形不红");
  const red = judgeCase("a.c", arm({ stderr: "out\n" }), arm({ stderr: "out\n" }));
  assert.notEqual(red, null, "非编译失败缺标记必红");
});

test("judgeCase：程序 stderr 分叉必红（剥标记行后比对——P3-6）", () => {
  // 仅标记行差异（合法面）：不红
  const a = arm({ stderr: "out\n" });
  const b = arm({ stderr: "// WASM-REHOST ok groups=3\nout\n" });
  assert.equal(judgeCase("a.c", a, b), null, "纯标记行差异不红");
  // 程序 STDERR 行分叉：必红
  const c = arm({ stderr: "// STDERR boom\n" });
  const d = arm({ stderr: "// WASM-REHOST ok groups=3\n// STDERR bam\n" });
  assert.notEqual(judgeCase("a.c", c, d), null, "程序 stderr 分叉红");
});

test("judgeCase：超时必红", () => {
  assert.notEqual(judgeCase("a.c", arm({ status: null }), arm({ status: null })), null);
});
