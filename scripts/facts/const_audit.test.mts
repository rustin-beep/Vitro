// const_audit.test.mts —— 常量对账（abi_version）的证红锚测试（J9：护栏上线
// 前先证明它会红）。直译自 const_audit_test.go。
//
// 夹具全部取自真实漂移样本（2026-09-15 复核 §7A / M13 实证）：
//   - 项目路线图.md:15  "vitro_abi_version() = 1.2.0"        —— 现值句漂移
//   - 项目更名记录.md:21 "ABI 版本 1.3.0 → 2.0.0"            —— 迁移事件句，豁免
//   - 项目更名记录.md:35 "返回 \"2.0.0\"——以 major …"        —— 裸旧版本，漂移
//   - 项目更名记录.md:48 "历史注释追加 2.0.0 条目"            —— 历史标记，豁免
//   - CAPI评审回复        "返回 `1.2.0`（…；1.1.0 为 …）"     —— 多版本串同行
// 若这些样本不再被抓到/豁免，说明规则腐坏，先修规则再动文档。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { auditConst } from "./audit.mts";
import type { ConstAudit } from "./audit.mts";
import { collectAbiVersion } from "./facts.mts";
import type { Fact, FactsDoc } from "./facts.mts";

const ABI_TRUTH = "2.1.0";

// writeAbiFixture 在临时仓库根布下 docs/ 文档并跑 auditConst，返回该文件命中。
function writeAbiFixture(...lines: string[]): ConstAudit {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-const-"));
  const rel = path.join(root, "docs", "current", "01-定位与路线", "夹具.md");
  fs.mkdirSync(path.dirname(rel), { recursive: true });
  fs.writeFileSync(rel, lines.join("\n") + "\n");
  const doc: FactsDoc = {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: {
      abi_version: {
        value: null, svalue: ABI_TRUTH, unit: "", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "",
      },
    },
  };
  const audits = auditConst(root, doc);
  assert.equal(audits.length, 1, `期望 1 条常量规则，得到 ${audits.length}`);
  return audits[0]!;
}

test("常量对账：两条裸旧版本现值句判漂移", () => {
  const a = writeAbiFixture(
    "| 出口 1 · C ABI | ✅ 可用；第一批 13 个入口全部落地，`vitro_abi_version()` = 1.2.0 |",
    "`vitro_abi_version()` 返回 `\"2.0.0\"`——以 major 变更表达符号面 breaking；",
  );
  assert.equal(a.drift.length, 2,
    `两条裸旧版本现值句必须判漂移：得到 Drift=${a.drift.length} Frozen=${a.frozen.length} Matched=${a.matched}`);
});

test("常量对账：迁移箭头事件句豁免", () => {
  const a = writeAbiFixture(
    "| C ABI（41 入口） | `cide_abi_version()` 等 `cide_*` | `vitro_abi_version()` 等 `vitro_*`，**ABI 版本 1.3.0 → 2.0.0**（符号面 breaking） |",
  );
  assert.ok(a.drift.length === 0 && a.frozen.length === 1,
    `迁移箭头事件句必须豁免：得到 Drift=${a.drift.length} Frozen=${a.frozen.length}`);
});

test("常量对账：历史标记句豁免", () => {
  const a = writeAbiFixture(
    "- ABI 版本历史注释（`native/src/capi/first_batch.rs`）追加 2.0.0 条目；",
  );
  assert.ok(a.drift.length === 0 && a.frozen.length === 1,
    `历史标记句必须豁免：得到 Drift=${a.drift.length} Frozen=${a.frozen.length}`);
});

test("常量对账：现值等于真值记 match", () => {
  const a = writeAbiFixture(
    "> 已于 U2#13 随 buf 写入式 API（ABI 2.1.0）根治，vet 现为零输出并入 CI 门禁。",
    "项目更名：C ABI（2.1.0）/ CLI / DLL 全量 `vitro_*`。",
  );
  assert.ok(a.matched === 2 && a.drift.length === 0,
    `现值等于真值必须记 match：Matched=${a.matched} Drift=${a.drift.length}`);
});

test("常量对账：多版本串且全部非真值判漂移", () => {
  // 行内既有"现值 1.2.0"又有历史引用 1.1.0：全部版本串 ≠ 真值 → 漂移
  //（修复时人工改写，机器不猜哪段是现值哪段是历史）。
  const a = writeAbiFixture(
    "| `vitro_abi_version` | ✅ | 返回 `1.2.0`（**加函数 = minor**；1.1.0 为首轮引入） |",
  );
  assert.equal(a.drift.length, 1, `多版本串且全部非真值必须判漂移：Drift=${a.drift.length}`);
});

test("常量对账：缺真值不得判漂移/冻结", () => {
  // 真值不可得时不得妄判（unavailable 由台账自报，缺真值不红——与
  // 数字对账的 Pending 同语义）。
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-const2-"));
  const rel = path.join(root, "docs", "current", "01-定位与路线", "夹具2.md");
  fs.mkdirSync(path.dirname(rel), { recursive: true });
  fs.writeFileSync(rel, "`vitro_abi_version()` = 1.2.0\n");
  const audits = auditConst(root, {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false }, facts: {},
  });
  assert.equal(audits.length, 1);
  assert.equal(audits[0]!.hasTruth, false, "真值缺失时 hasTruth 必须为 false");
  assert.ok(audits[0]!.drift.length === 0 && audits[0]!.frozen.length === 0, "缺真值不得判漂移/冻结");
});

test("abi_version 采集器退役形态锁定", () => {
  // 工序④删区（2026-10-05）：ABI 真值源（Rust first_batch.rs）随区删除，
  // 采集器退役为固定 unavailable 形态——本测试锁退役契约本身。
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-const3-"));
  const facts: Record<string, Fact> = {};
  collectAbiVersion(root, facts);
  const f = facts["abi_version"];
  assert.ok(f !== undefined, "abi_version 键必须仍存在（退役形态）");
  assert.ok(f.status === "unavailable" && f.value === null && f.source === "native/（已删除）",
    `退役形态失约: ${JSON.stringify(f)}`);
  assert.ok(f.how_to_get !== "", "退役键必须带 how_to_get 指引（历史值取回路径）");
});
