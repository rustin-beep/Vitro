// offsets.test.mts —— 回归测试：同一行被多条规则命中时，逐条 applyHit 的
// 偏移必须仍然正确。直译自 offsets_test.go。
//
// 背景：applyHit 按 audit 阶段算出的偏移定位并替换数字。若同一行先替换了
// 长度不同的数字（如 100→97 少 1 字节），则该行后续数字的偏移整体前移——
// 修复 = applyHit 内部基于当前文件内容**重新计算**候选区间，不复用旧偏移。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { applyHit } from "./audit.mts";
import type { Hit, NumSpan } from "./audit.mts";

const span = (start: number, end: number, value: number): NumSpan => ({ start, end, value });

// TestApplyHitSameLineOffset 验证同行两处替换后，行内容仍完全正确。
//
// 夹具选取真实可发生的同行双命中：该行同时含 "Shadow"（命中 shadow_c_cases）
// 与 "serve 冒烟"（命中 serve_smoke_assertions）。636→671 为 +1 字节，
// 正是会让后续偏移失真的情形。
test("applyHit：同行双条目替换偏移正确", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-offsets-"));
  const file = "t.md";
  const line = "- 测试防线：C Shadow 636 用例、serve 冒烟 40 项断言，clippy 零警告";
  fs.writeFileSync(path.join(root, file), line + "\n");

  const i636 = line.indexOf("636");
  const i40 = line.indexOf("40 项");
  assert.ok(i636 >= 0 && i40 >= 0, "测试夹具构造失败");

  const h1: Hit = { key: "shadow_c_cases", file, lineNo: 1, spans: [span(i636, i636 + 3, 636)], text: line, cooccur: [], warn: "" };
  const h2: Hit = { key: "serve_smoke_assertions", file, lineNo: 1, spans: [span(i40, i40 + 2, 40)], text: line, cooccur: [], warn: "" };

  applyHit(root, h1, 671);
  applyHit(root, h2, 51);

  const got = fs.readFileSync(path.join(root, file), "utf8");
  const want = "- 测试防线：C Shadow 671 用例、serve 冒烟 51 项断言，clippy 零警告";
  assert.equal(got.trim(), want, "同行二次替换结果错误（偏移失效）");
});

// 安全网：前序条目若把行改得不再匹配本规则，必须报错拒改，而不是按陈旧
// 偏移乱切。
test("applyHit：行不再匹配规则时报错拒改", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-offsets2-"));
  const file = "t3.md";
  // 该行不含 "C++"，却被伪造一条 cpp_e2e_cases 的 Hit —— 应当被拒。
  const line = "- 某行已被前序条目改写，不再含目标关键词";
  fs.writeFileSync(path.join(root, file), line + "\n");
  const h: Hit = { key: "cpp_e2e_cases", file, lineNo: 1, spans: [span(0, 1, 7)], text: line, cooccur: [], warn: "" };
  assert.throws(() => applyHit(root, h, 81), "行不再匹配规则时应当报错，却静默通过了");
});

// 验证单条 Hit 内部多个 span 的替换不受长度变化影响
// （applyHit 内部倒序替换，这一点应当成立）。
test("applyHit：单条多 span 倒序替换长度安全", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-offsets3-"));
  const file = "t2.md";
  const line = "C Shadow 636 用例 / 636 通过";
  fs.writeFileSync(path.join(root, file), line + "\n");
  const a = line.indexOf("636");
  const b = line.lastIndexOf("636");
  const h: Hit = { key: "shadow_c_cases", file, lineNo: 1, spans: [span(a, a + 3, 636), span(b, b + 3, 636)], text: line, cooccur: [], warn: "" };
  applyHit(root, h, 671);
  const got = fs.readFileSync(path.join(root, file), "utf8");
  assert.equal(got.trim(), "C Shadow 671 用例 / 671 通过", "单条多 span 替换错误");
});
