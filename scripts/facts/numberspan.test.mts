// numberspan.test.mts —— numberSpans 候选掩码的证红锚测试（J9：PR #312 审阅
// 小尾巴批——护栏上线前先证明它会红）。夹具取自真实假漂移样本：
//   - CLI使用手册.md:24  「防线插座（#49 批二起…）」——issue 号 49 被当
//     replay/serve_smoke 断言数候选（replay 真值 61、serve_smoke 69）；
//   - 脚本总清单.md:40   「（纪律 14「三臂强制」…）」——纪律条号 14 同族。
// 修复面 = numberSpans 掩码链（issue 引用 `#\d+` 与「纪律 N」编号不进候选），
// 全仓通用形态治本；若这些样本重新进候选或普通计数被误掩，说明规则腐坏。
import assert from "node:assert/strict";
import { test } from "node:test";
import { numberSpans } from "./audit.mts";

test("numberSpans：issue 引用「#49」不进候选（防线插座行实测样本）", () => {
  const line =
    "防线插座（#49 批二起，三后端批续扩）：`vm_diff` / `clang_direct` 支持 `--backend native|wasm`（缺省 native）；replay / serve_smoke / protocol_frames 的 wasm 臂同款插座（#49 批三评论在案）。";
  const spans = numberSpans(line);
  assert.ok(
    !spans.some((s) => s.value === 49),
    "issue 号 49 不应进候选：实际 " + JSON.stringify(spans.map((s) => s.value)),
  );
});

test("numberSpans：「纪律 14」条号不进候选（脚本总清单实测样本）", () => {
  const line =
    "serve_smoke / protocol_frames / teaching 的 wasm 臂（纪律 14「三臂强制」的 CI 载体）。";
  const spans = numberSpans(line);
  assert.ok(
    !spans.some((s) => s.value === 14),
    "纪律条号 14 不应进候选：实际 " + JSON.stringify(spans.map((s) => s.value)),
  );
});

test("numberSpans：普通计数不受掩码影响（回归守卫）", () => {
  const spans = numberSpans("e2e 786 用例〔baseline 546 / knr 81 / leetcode 138 / gap 21〕+ moon test 897 用例");
  assert.deepEqual(
    spans.map((s) => s.value),
    [786, 546, 81, 138, 21, 897],
  );
});

test("numberSpans：日期与阶段序号掩码既有行为不变（连带回归锚）", () => {
  const spans = numberSpans("2026-10-25 对齐（第 3 批）共 923 语料");
  assert.deepEqual(
    spans.map((s) => s.value),
    [923],
  );
});
