// suspect_exemptions.test.mts —— suspect_exemptions 白名单机制锚（2026-10-01
// --strict 接线批，模块审阅 09 P2-1 处方①）。直译自 suspect_exemptions_test.go。
// 四路 J9：
//   1. 未登记的 Suspect 行 → 仍计数（--strict 判红依据不变）；
//   2. 登记（path+contains 命中）→ 豁免并留痕（suspectExemptedN）；
//   3. 登记但本轮零命中 → staleSuspectExempts（僵尸豁免面，check 无条件红）；
//   4. 坏条目（缺字段/文件不存在/坏 JSON）→ loadSuspectExemptions 拒绝。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { auditDocs, findAudit } from "./audit.mts";
import type { AuditResult } from "./audit.mts";
import { loadSuspectExemptions } from "./audit.mts";
import type { Fact, FactsDoc } from "./facts.mts";

// suspectExemptFixture：在 TempDir 下同时铺 suspect_exemptions.json（可为
// 空表）与夹具文档，跑 auditDocs 返回结果。
function suspectExemptFixture(line: string, exempts: string): AuditResult {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-sx-"));
  const p = path.join(root, "docs", "current", "01-定位与路线", "夹具.md");
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, line + "\n");
  fs.mkdirSync(path.join(root, "scripts", "facts"), { recursive: true });
  fs.writeFileSync(path.join(root, "scripts", "facts", "suspect_exemptions.json"), exempts);
  const fact: Fact = {
    value: 683, unit: "", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "",
  };
  const doc: FactsDoc = {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: { shadow_c_cases: fact },
  };
  return auditDocs(root, doc);
}

const SUSPECT_LINE = "- **C 教学子集**：C Shadow Verification **682 个用例**（完全匹配 678 + known_issue 3 + gap_extension 1，无非预期差异）";

// 1：未登记 → Suspect 计数不变（--strict 判红依据）。空白名单 = 全计数。
test("suspect 豁免：未登记行原样计数", () => {
  const res = suspectExemptFixture(SUSPECT_LINE, "[]\n");
  const a = findAudit(res, "shadow_c_cases");
  assert.ok(a !== undefined, "规则未出现在审计结果中");
  assert.ok(a!.suspect.length === 1 && a!.suspectExempted.length === 0,
    `未登记的 Suspect 行应原样计数：suspect=${a!.suspect.length} exempted=${a!.suspectExempted.length}`);
  assert.ok(res.suspectN === 1 && res.suspectExemptedN === 0 && res.staleSuspectExempts.length === 0,
    `空白名单下计数应全落 suspect：suspectN=${res.suspectN} exemptedN=${res.suspectExemptedN} stale=${res.staleSuspectExempts.length}`);
});

// 2：登记（path 对 + contains 命中行文本）→ 豁免留痕、suspectN 归零。
test("suspect 豁免：登记命中行豁免留痕", () => {
  const res = suspectExemptFixture(SUSPECT_LINE, `[{
		"path": "docs/current/01-定位与路线/夹具.md",
		"contains": "682 个用例",
		"reason": "测试锚：合法未来值行"
	}]`);
  const a = findAudit(res, "shadow_c_cases")!;
  assert.ok(a.suspect.length === 0 && a.suspectExempted.length === 1,
    `登记命中的行应豁免：suspect=${a.suspect.length} exempted=${a.suspectExempted.length}`);
  assert.ok(res.suspectN === 0 && res.suspectExemptedN === 1 && res.staleSuspectExempts.length === 0,
    `豁免后 suspectN 应为 0 且无僵尸条目：suspectN=${res.suspectN} exemptedN=${res.suspectExemptedN} stale=${res.staleSuspectExempts.length}`);
});

// 3：登记但 contains 零命中 → 行仍计数 + 僵尸条目标红（check 无条件红依据）。
test("suspect 豁免：零命中条目判僵尸", () => {
  const res = suspectExemptFixture(SUSPECT_LINE, `[{
		"path": "docs/current/01-定位与路线/夹具.md",
		"contains": "不存在的内容锚",
		"reason": "测试锚：应判僵尸"
	}]`);
  const a = findAudit(res, "shadow_c_cases")!;
  assert.ok(a.suspect.length === 1 && a.suspectExempted.length === 0,
    `零命中的条目不得豁免任何行：suspect=${a.suspect.length} exempted=${a.suspectExempted.length}`);
  assert.equal(res.staleSuspectExempts.length, 1,
    `零命中条目应进 staleSuspectExempts（无条件红）：got ${res.staleSuspectExempts.length}`);
});

// 4：坏条目三形态 → loadSuspectExemptions 拒绝（fail loud，不走 auditDocs
// 以免 process.exit 杀测试进程）。
test("suspect 豁免：坏条目三形态拒绝加载", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-sx-bad-"));
  const dir = path.join(root, "scripts", "facts");
  fs.mkdirSync(dir, { recursive: true });
  const p = path.join(dir, "suspect_exemptions.json");

  const bads: [string, string][] = [
    ["坏 JSON", `[{`],
    ["缺字段", `[{"path": "docs/current/x.md", "contains": "x"}]`],
    ["文件不存在", `[{"path": "docs/current/无此文件.md", "contains": "x", "reason": "r"}]`],
  ];
  for (const [name, body] of bads) {
    fs.writeFileSync(p, body);
    assert.throws(() => loadSuspectExemptions(root), `${name} 应被拒绝（fail loud）`);
  }

  // 合法空表 + 缺文件（向后兼容）均通过。
  fs.writeFileSync(p, "[]");
  assert.deepEqual(loadSuspectExemptions(root), [], "空表应通过");
  fs.rmSync(p);
  assert.deepEqual(loadSuspectExemptions(root), [], "缺文件应视为空表（向后兼容）");
});

// 回归锚：豁免不改变 Suspect 语义本身——同一行在无白名单时必先进 Suspect
// （防止"为过闸改判定"的回归形态）。
test("suspect 豁免：不得弱化判定本身", () => {
  const res = suspectExemptFixture(SUSPECT_LINE, "[]\n");
  const a = findAudit(res, "shadow_c_cases")!;
  assert.equal(a.suspect.length, 1, "基准：该行必进 suspect（豁免机制不得改变判定本身）");
});
