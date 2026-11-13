// wasmenc watcheck 单测（#273 四件套的 node:test 面）——不依赖 wabt/moon
// （那些在 main() 真跑路径上），此处锁纯函数件：uleb 读取/函数体提取/
// 期望串构造/对拍差异定位（红→绿锚：构造错位输入必报差异）。

import assert from "node:assert/strict";
import test from "node:test";
import { buildExpected, compareCase, extractFirstBodyInstrs } from "./main.mts";

test("readUleb 经 extract 间接锁：单字节 size 段跳过正确", () => {
  // 手拼最小模块：magic + type 段 + code 段
  // code 段体(5) = count(1) + bodySize(3) + body[locals0, nop, end]
  const mod = [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00, // type 段：()->()
    0x0a, 0x05, 0x01, 0x03, 0x00, 0x01, 0x0b,
  ];
  const instrs = extractFirstBodyInstrs(mod);
  assert.deepEqual(instrs, [0x01, 0x0b]);
});

test("extract 跳过 locals 声明（两组 run）", () => {
  // code 段体(9) = count(1) + bodySize(7) + body[locals 2 组 5B, nop, end]
  const mod = [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
    0x0a, 0x09, 0x01, 0x07, 0x02, 0x03, 0x7f, 0x01, 0x7e, 0x01, 0x0b,
  ];
  const instrs = extractFirstBodyInstrs(mod);
  assert.deepEqual(instrs, [0x01, 0x0b]);
});

test("buildExpected：block+垫栈+模板+drop+end", () => {
  const got = buildExpected([{ pushes: "i", drops: 1, bytes: [0x6a] }]);
  assert.deepEqual(got, [0x02, 0x40, 0x41, 0x00, 0x6a, 0x1a, 0x0b, 0x0b]);
});

test("compareCase：一致返 null / 错位报差异（红→绿锚）", () => {
  const entry = [{ pushes: "", drops: 1, bytes: [0x41, 0x2a] }]; // i32.const 42 单组
  // mock 编译器产出完整模块（magic + code 段包裹指令区）
  const wrapModule = (instrs: number[]): number[] => {
    const body = [0x00, ...instrs]; // locals=0 + 指令区
    const codeBody = [0x01, body.length, ...body];
    return [
      0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
      0x0a, codeBody.length, ...codeBody,
    ];
  };
  const compileOk = (): number[] => wrapModule([0x02, 0x40, 0x41, 0x2a, 0x1a, 0x0b, 0x0b]);
  assert.equal(compareCase("(mock)", entry, compileOk), null);
  const compileBad = (): number[] => wrapModule([0x02, 0x40, 0x41, 0x2b, 0x1a, 0x0b, 0x0b]); // 43 冒充
  const diff = compareCase("(mock)", entry, compileBad, ["PushConst(42)"]);
  assert.ok(diff !== null && diff.includes("组 PushConst(42)（第 1/1 组）：组内偏移 3"), diff ?? "应有差异");
});

test("compareCase 逐组定位：多组文件第二组错不误报第一组", () => {
  // 两组：PushConst(42)（[i32.const 42, drop]）+ UAdd（垫 ii，i32.add，drop）
  const entries = [
    { pushes: "", drops: 1, bytes: [0x41, 0x2a] },
    { pushes: "ii", drops: 1, bytes: [0x6a] },
  ];
  const wrapModule = (instrs: number[]): number[] => {
    const body = [0x00, ...instrs];
    const codeBody = [0x01, body.length, ...body];
    return [
      0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
      0x0a, codeBody.length, ...codeBody,
    ];
  };
  // 第一组正确（02 40 41 2a 1a 0b = 6B）；第二组 i32.sub(0x6b) 冒充 i32.add
  const bad = wrapModule([0x02, 0x40, 0x41, 0x2a, 0x1a, 0x0b, 0x02, 0x40, 0x41, 0x00, 0x41, 0x00, 0x6b, 0x1a, 0x0b, 0x0b]);
  const diff = compareCase("(mock)", entries, (): number[] => bad, ["PushConst(42)", "UAdd(0)"]);
  assert.ok(diff !== null && diff.includes("组 UAdd(0)（第 2/2 组）：组内偏移 6"), diff ?? "应定位到第二组");
});

test("compareCase 尾部锚：缺函数级 end / end 后多字节", () => {
  const entry = [{ pushes: "", drops: 1, bytes: [0x41, 0x2a] }];
  const wrapModule = (instrs: number[]): number[] => {
    const body = [0x00, ...instrs];
    const codeBody = [0x01, body.length, ...body];
    return [
      0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
      0x0a, codeBody.length, ...codeBody,
    ];
  };
  const noEnd = compareCase("(mock)", entry, (): number[] => wrapModule([0x02, 0x40, 0x41, 0x2a, 0x1a, 0x0b]));
  assert.ok(noEnd !== null && noEnd.includes("尾部：函数级 end 失配"), noEnd ?? "应报尾部失配");
  const trailing = compareCase("(mock)", entry, (): number[] => wrapModule([0x02, 0x40, 0x41, 0x2a, 0x1a, 0x0b, 0x0b, 0x01]));
  assert.ok(trailing !== null && trailing.includes("尾部：end 后多 1 字节"), trailing ?? "应报尾部多余");
});
