// img_line.test.mts —— HTML 嵌入标签行豁免（2026-09-21 图览批）的证红锚测试
// （J9：判定面变更上线前先证红）。直译自 img_line_test.go。
//
// 背景：README「项目图览」以 logo 式内联挂图（<img ... width="900">）后，
// img 行的 alt="影子验证门禁流水线" 提供 shadow_c_cases 规则语境（影子|shadow）、
// width="900" 落在其 [400,900] 区间——布局参数被判成"C 影子用例总数 900≠680
// 漂移"（实测红：README.md:44 / 影子验证框架.md:13 两处，width=880 同撞）。
// 修复：RE_HTML_TAG_LINE（<img / width="）行整体跳过数字对账——嵌入图内的真
// 快照数字由 SVG data-fact 通道（tspan 锚）承担，标签行数字只是布局参数。
//
//   - img 行带区间内数字 → 豁免，不判漂移
//   - 豁免不外溢：同文件真文本行数字漂移仍红
//
// 若这两条判定翻转（img 行复活误报 / 文本行被顺带豁免），先修豁免边界再动文档。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { auditDocs, findAudit } from "./audit.mts";
import type { Fact, FactsDoc } from "./facts.mts";

function writeImgFixture(...lines: string[]) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-img-"));
  fs.writeFileSync(path.join(root, "README.md"), lines.join("\n") + "\n");
  const doc: FactsDoc = {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: {
      shadow_c_cases: {
        value: 676, unit: "", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "",
      } as Fact,
    },
  };
  return auditDocs(root, doc);
}

// img 行 width=900（恰在 [400,900] 区间）：修复前判漂移，修复后豁免。
test("img 布局行豁免不判漂移不计命中", () => {
  const res = writeImgFixture(
    `<img src="docs/current/04-标准库与防线/clang-direct-gate-flow.svg" alt="Clang 直拍门禁流水线" width="900">`,
  );
  const a = findAudit(res, "shadow_c_cases");
  assert.ok(a !== undefined, "shadow_c_cases audit 缺失");
  assert.equal(a!.drift.length, 0, `img 布局行不应判漂移，实判 ${a!.drift.length} 处（豁免失效）`);
  assert.equal(a!.matched, 0, `img 布局行应整体跳过而非计一致命中，matched=${a!.matched}`);
});

// 豁免边界：同文件普通文本行的漂移数字必须仍红（豁免不得外溢到正文）。
test("img 行同文件真文本行漂移仍红", () => {
  const res = writeImgFixture(
    `<img src="clang-direct-gate-flow.svg" alt="Clang 直拍门禁流水线" width="900">`,
    ``,
    `当前规模：C 侧 **700 个用例**（Clang 影子对照真值 676，此行必须红）`,
  );
  const a = findAudit(res, "shadow_c_cases");
  assert.ok(a !== undefined, "shadow_c_cases audit 缺失");
  assert.equal(a!.drift.length, 1, `真文本行漂移必须仍红，实判 drift=${a!.drift.length}`);
});
