// main.test.mts —— clang_direct 纯逻辑面自测（#273 迁移批补口；Go 版无测试
// 件。本件锁：标记行剥除 / 行级归一〔含 \r\r 多重尾——A1-l 入库锚〕两面；
// 缓存键与 digest 集兼容、语料采样确定性由 CI 全量运行与 --check-known 承载）。
// 审阅 v2 S03 批（2026-11）补锚：EXIT 解析（A1）/ quoteBody 接受域（A2）/
// 工程源读取编码（A3）——报告 C4 点名「三处实测分歧恰都落在无锚面」。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { extractMoonStdout, goQuote, normalizeClangStdout, normalizeLines, parseExitLine, quoteBody, readProjectSources } from "./main.mts";

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

// ── 审阅 v2 S03-A1（2026-11）：`// EXIT` 负值解析 ─────────────────────────
// 引擎 return -1 原样输出负数（cmd/run 实测）；Go fmt.Sscanf("%d") 认负号，
// 原正则 (\d+) 吞负数保持 0——负 return 族 known digest 跨轨分歧
// （探针：go「!= -1」vs mts「!= 0」）。vm.mts:252 同款解析早已 (-?\d+)。
test("parseExitLine：负值/正值/非法三态（S03-A1）", () => {
  assert.equal(parseExitLine("// EXIT -1"), -1, "负值不得被吞成 0");
  assert.equal(parseExitLine("// EXIT 300"), 300);
  assert.equal(parseExitLine("// EXITED"), null, "非 EXIT 标记形态不解析");
  assert.equal(parseExitLine("// EXIT abc"), null, "无数字不解析");
});

// ── 审阅 v2 S03-A2（2026-11）：quoteBody 的 Go utf8 接受域 ────────────────
// Go %q 对解码失败的序列逐字节 \xNN。原实现只查长度与连续性，代理区
// （ED A0-BF——Node 解码成 U+FFFD×3 与 Go \xed\xa0\x80 分歧）等四类
// 边界序列漏拒。测试输入 = latin1 字节域字符串（summarize 同款域）。
test("quoteBody：代理区/过短/超 MaxRune 拒绝 + 合法多字节原样（S03-A2）", () => {
  // 代理区 ED A0 80（U+D800）——Go DecodeRune 拒 → 逐字节
  assert.equal(quoteBody(String.fromCharCode(0xed, 0xa0, 0x80)), "\\xed\\xa0\\x80", "代理区序列必须逐字节 \\xNN（不得解码 U+FFFD）");
  // E0 80 过短（overlong）——次字节 80 < A0 拒
  assert.equal(quoteBody(String.fromCharCode(0xe0, 0x80, 0x80)), "\\xe0\\x80\\x80");
  // F0 80 过短——次字节 80 < 90 拒
  assert.equal(quoteBody(String.fromCharCode(0xf0, 0x80, 0x80, 0x80)), "\\xf0\\x80\\x80\\x80");
  // F4 90 超 U+10FFFF——次字节 90 > 8F 拒
  assert.equal(quoteBody(String.fromCharCode(0xf4, 0x90, 0x80, 0x80)), "\\xf4\\x90\\x80\\x80");
  // 合法序列原样（防误伤）：中文「中」E4 B8 AD
  assert.equal(quoteBody(String.fromCharCode(0xe4, 0xb8, 0xad)), "中");
  // ED 80 合法（U+D000 < U+D800 非代理区——上限 9F 不误伤）
  assert.equal(quoteBody(String.fromCharCode(0xed, 0x80, 0x80)), "퀀");
});

test("quoteBody：单字节转义面回归（引号/控制字符）", () => {
  assert.equal(goQuote(String.fromCharCode(0x22)), '"\\""');
  assert.equal(goQuote("a\nb"), '"a\\nb"');
  assert.equal(goQuote(String.fromCharCode(0x01)), '"\\x01"');
});

// ── 审阅 v2 S03-A3（2026-11）：工程源读取编码 ─────────────────────────────
// Go json.Marshal(string(b))：合法 UTF-8 原样、无效孤字节 U+FFFD。原实现
// readFileSync(latin1) + 后续 utf8 编码 = 每个 ≥0x80 字节膨胀 2 字节，非
// ASCII 工程语料即与 Go 侧 digest 分歧（现役语料全 ASCII 零触发）。锚 =
// 读取路径的字节语义（孤字节 0xC8 → U+FFFD、合法中文原样）。
test("readProjectSources：Go json.Marshal 字节语义（孤字节 U+FFFD、合法 UTF-8 原样）", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "clang-direct-a3-"));
  const f = path.join(dir, "main.c");
  fs.writeFileSync(f, Buffer.concat([Buffer.from([0xc8]), Buffer.from("中\n", "utf8")]));
  const r = readProjectSources([f]);
  assert.ok(r.ok, "读临时文件不得失败");
  if (!r.ok) return;
  assert.equal(r.ents[0]!.filename, "main.c");
  assert.equal(r.ents[0]!.source, "\uFFFD中\n", "孤字节 0xC8 须 U+FFFD（Go json.Marshal 同款），合法中文原样");
});
