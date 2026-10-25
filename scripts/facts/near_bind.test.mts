// near_bind.test.mts —— 就近绑定（2026-09-18 P1 批）的证红锚测试（J9）。
// 直译自 near_bind_test.go。
//
// 背景：auditDocs 此前行内所有落 Lo/Hi 区间的数字都归属每条命中规则，
// "replay 61 / serve_smoke 57"（两个真值键共行、数字互落对方区间：
// serve 的 [10,150] 含 61，replay 的 [20,200] 含 57）必然互斥判红——
// MoonBit迁移总计划.md:81 的既有误报（数字全对却判漂移）。改为就近绑定后：
//   - 跨键共行且各自正确 → 双绿（本文件 TestNearBindMultiKeySameLine）
//   - 近邻数字写错 → 仍红（TestNearBindNearbyDriftStillCaught）
//   - 数字在关键词左侧 → 不归属任何规则（TestNearBindLeadingNumberIgnored）
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { auditDocs, findAudit } from "./audit.mts";
import type { AuditResult } from "./audit.mts";
import type { Fact, FactsDoc } from "./facts.mts";

function writeAuditFixture(...lines: string[]): AuditResult {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-nearbind-"));
  const rel = path.join(root, "docs", "current", "01-定位与路线", "夹具.md");
  fs.mkdirSync(path.dirname(rel), { recursive: true });
  fs.writeFileSync(rel, lines.join("\n") + "\n");
  const fact = (v: number): Fact => ({
    value: v, unit: "", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "",
  });
  const doc: FactsDoc = {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: {
      replay_assertions: fact(61),
      serve_smoke_assertions: fact(57),
      shadow_c_cases: fact(676),
    },
  };
  return auditDocs(root, doc);
}

// 双真值键共行且各自正确：旧语义互斥双红，就近绑定后双绿。
test("nearBind：跨键共行各自正确判双绿", () => {
  const res = writeAuditFixture(
    "| **C 端到端** | Clang golden 733 全量 / replay 61 / serve_smoke 57 / JIT parity 八形状（若复活） | golden 缺失必红；`.out` 只作第二来源，live clang 为主真值 |",
  );
  for (const key of ["replay_assertions", "serve_smoke_assertions"]) {
    const a = findAudit(res, key);
    if (a === undefined) throw new Error(`规则 ${key} 未出现在审计结果中`);
    assert.ok(a.drift.length === 0 && a.matched === 1,
      `${key}：共行双键各自正确应判 Matched=1，得到 Matched=${a.matched} Drift=${a.drift.length}`);
  }
});

// 近邻写错仍必须红：61 写成 60（紧贴 replay 关键词）。
test("nearBind：近邻写错仍红", () => {
  const res = writeAuditFixture(
    "| **C 端到端** | Clang golden 733 全量 / replay 60 / serve_smoke 57 | 备注 |",
  );
  const a = findAudit(res, "replay_assertions");
  assert.ok(a !== undefined && a.drift.length === 1,
    `近邻写错（replay 60，真值 61）必须判漂移：Drift=${a?.drift.length ?? -1}`);
});

// 数字前置写法（"675 个 Shadow golden"，真值 676）必须仍被抓：
// 双向最近绑定下 675 的最近关键词是右侧的 Shadow。
test("nearBind：数字前置写法仍红且写对转绿", () => {
  const res = writeAuditFixture(
    "- 字节码格式与 675 个 Shadow golden（C# 侧只允许按既有规则追加 opcode）",
  );
  const a = findAudit(res, "shadow_c_cases");
  assert.ok(a !== undefined && a.drift.length === 1,
    `数字前置写法的漂移（675 个 Shadow，真值 676）必须判漂移：Drift=${a?.drift.length ?? -1}`);
  // 改对后必须绿（同形态复检，防止只红不绿）。
  const res2 = writeAuditFixture(
    "- 字节码格式与 676 个 Shadow golden（C# 侧只允许按既有规则追加 opcode）",
  );
  const a2 = findAudit(res2, "shadow_c_cases");
  assert.ok(a2 !== undefined && a2.matched === 1 && a2.drift.length === 0,
    `数字前置写法写对（676 个 Shadow）应判 Matched=1：Matched=${a2?.matched} Drift=${a2?.drift.length}`);
});

// 键位平局取右："cargo test 70 套件" 的 70 左右等距，
// 后置的"套件"是计量单位——归套件数规则，不归前置的用例数规则。
test("nearBind：平局取右归后置单位", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-nearbind-tie-"));
  const rel = path.join(root, "docs", "current", "01-定位与路线", "夹具.md");
  fs.mkdirSync(path.dirname(rel), { recursive: true });
  fs.writeFileSync(rel, "验收：cargo test 70 套件全绿\n");
  const doc: FactsDoc = {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: {
      cargo_test_suites: {
        value: 70, unit: "", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "",
      },
    },
  };
  const res = auditDocs(root, doc);
  const s = findAudit(res, "cargo_test_suites");
  assert.ok(s !== undefined && s.matched === 1,
    `"cargo test 70 套件" 的 70 应归属套件数规则（Matched=1）：Matched=${s?.matched} Drift=${s?.drift.length}`);
});

// 就近归属跨规则并集：serve_smoke 关键词出现在 replay 之后时，
// 其后的数字只归 serve，不再落进 replay 的候选。
test("nearBind：最近关键词胜出", () => {
  const res = writeAuditFixture(
    "| 项 | replay 断言数见 serve_smoke 57 项 | 备注 |",
  );
  const a = findAudit(res, "serve_smoke_assertions");
  assert.ok(a !== undefined && a.matched === 1,
    `57 紧贴 serve_smoke 关键词应判 Matched=1：得到 ${a?.drift.length ?? -1}`);
  const r = findAudit(res, "replay_assertions");
  if (r !== undefined) {
    assert.ok(r.drift.length === 0 && r.matched === 0,
      `57 的最近关键词是 serve_smoke，不应再归属 replay：Matched=${r.matched} Drift=${r.drift.length}`);
  }
});
