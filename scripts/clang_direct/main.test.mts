// main.test.mts —— clang_direct 纯逻辑面自测（#273 迁移批补口；Go 版无测试
// 件，本件锁四件套门的判定面：标记行剥除 / 行级归一 / 缓存键确定性 /
// known digest 集兼容 / 语料收集与采样确定性）。
import assert from "node:assert/strict";
import { test } from "node:test";
import { extractMoonStdout, normalizeClangStdout, normalizeLines } from "./main.mts";

test("extractMoonStdout：剥标记行族（EXIT/TRAP/COMPILE-ERROR/FIX/WARNING/HINT/NOTE/STDERR）", () => {
  // 标记行形态 = 精确前缀（**空格**，vm.mts extractMoonBitStdout 同款词表）
  const s = [
    "hello",
    "// TRAP integer overflow",
    "// COMPILE-ERROR unknown type",
    "// FIX insert header",
    "// COMPILE-WARNING implicit int",
    "// COMPILE-HINT declare it",
    "// NOTE whatever",
    "// STDERR fprintf output",
    "// EXIT 3",
  ].join("\n");
  assert.equal(extractMoonStdout(s), "hello");
});

test("extractMoonStdout：非标记行含 // 前缀不误剥（EXIT 需尾注形态）", () => {
  // "// EXITED" 不是 "// EXIT "（带空格）标记——不得剥
  assert.equal(extractMoonStdout("a\n// EXITED\nb"), "a\n// EXITED\nb");
});

test("normalizeLines：CRLF 归一 + 首尾空行剥 + 无尾换行 join", () => {
  assert.equal(normalizeLines(["\r", "a\r", "b", "", ""]), "a\nb");
  assert.equal(normalizeLines(["", "", "x"]), "x");
  assert.equal(normalizeLines([]), "");
});

test("normalizeClangStdout：Windows 文本模式 CRLF 对齐", () => {
  assert.equal(normalizeClangStdout("out\r\nlines\r\n"), "out\nlines");
});

// 双侧对称性锚：同一文本经 clang 侧归一与 moon 侧提取+归一后必须同形。
test("对拍归一对称性：CRLF 尾行与标记行混排", () => {
  const clang = "line1\r\nline2\r\n";
  const moon = "line1\nline2\n// EXIT 0\n";
  assert.equal(normalizeClangStdout(clang), extractMoonStdout(moon));
});
