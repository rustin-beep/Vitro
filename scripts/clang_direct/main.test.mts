// main.test.mts —— clang_direct 纯逻辑面自测（#273 迁移批补口；Go 版无测试
// 件。本件锁：标记行剥除 / 行级归一〔含 \r\r 多重尾——A1-l 入库锚〕两面；
// 缓存键与 digest 集兼容、语料采样确定性由 CI 全量运行与 --check-known 承载）。
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
  // A1-l 入库锚（#307 审阅 P2-3：本批修复曾无锚——突变 /\r+$/→/\r$/ 时
  // 旧样本 5/5 绿）。\r\r 形态 = printf("\r\n") 经 Windows 文本模式成
  // \r\r\n——剥全部尾 \r，剥一个残一个会把工程语料 MF-HTTP 误判 DIFF。
  assert.equal(normalizeLines(["a\r\r"]), "a", "单行多重 \\r 尾须全剥");
  assert.equal(normalizeLines(["a\r\r", "b", "c\r\r\r"]), "a\nb\nc", "多行多重 \\r 尾须全剥");
  assert.equal(normalizeLines(["HTTP/1.1 200\r\r", "body\r"]), "HTTP/1.1 200\nbody");
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
