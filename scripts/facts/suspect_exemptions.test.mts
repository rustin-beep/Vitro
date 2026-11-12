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
// 空表）与夹具文档，跑 auditDocs 返回结果。truth=null 表示零真值
// （facts 空表）——模拟 docs-quick 薄通道 fresh 检出态（无 reports/facts.json）。
function suspectExemptFixture(line: string, exempts: string, truth: number | null = 683, key = "shadow_c_cases"): AuditResult {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "facts-sx-"));
  const p = path.join(root, "docs", "current", "01-定位与路线", "夹具.md");
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, line + "\n");
  fs.mkdirSync(path.join(root, "scripts", "facts"), { recursive: true });
  fs.writeFileSync(path.join(root, "scripts", "facts", "suspect_exemptions.json"), exempts);
  const fact: Fact = {
    value: 0, unit: "", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "",
  };
  if (truth !== null) fact.value = truth;
  const doc: FactsDoc = {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: truth !== null ? { [key]: fact } : {},
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

// 5：零真值环境（docs-quick 薄通道 fresh 检出态，无 reports/facts.json）——
// suspect 判读结构性不发生（键无真值行进 pending），豁免条目不可能命中，
// 零命中不得判僵尸（2026-11-12 run 140 实锤：#493 真值依赖型豁免条目
// 〔replay_assertions〕在薄通道必误报红——PR 不触发 docs-quick，合入后
// master push 首跑即红）。复刻 #493 真实形态：行内「回放」关键词 +
// exec_step.mbt:95-100 源码行号被误抓进回放断言数值域（20-200）。
const REPLAY_LINE = `**VisEvent 高频成本实测方案**（任务书点名）：基线**不进载体**（run 态零消费方已实证，\`exec_step.mbt:95-100\`）。若未来产品需要「快路径过程回放」（长跑算法动画加速），实测方案=**块粒度 vis 锚 import**（\`env.vitro_vis(line, extra0, extra1)\` 仅在含 vis 登记行的基块首插入；预期量级：vis 行密度典型 ≤1/10 块，跨界开销参照 W4 host-call 51ns/次——推断 <5% 长跑耗时）。启用条件与实测脚本列入 §6-6 期 3，**本设计批不实测**（纯设计纪律）。`;

test("suspect 豁免：零真值环境零命中不判僵尸（薄通道让位）", () => {
  const res = suspectExemptFixture(REPLAY_LINE, `[{
		"path": "docs/current/01-定位与路线/夹具.md",
		"contains": "exec_step.mbt:95-100",
		"reason": "测试锚：零真值下不应判僵尸"
	}]`, null, "replay_assertions");
  const a = findAudit(res, "replay_assertions")!;
  assert.ok(a.suspect.length === 0 && a.pending.length === 1,
    `零真值下该行应进 pending 而非 suspect：suspect=${a.suspect.length} pending=${a.pending.length}`);
  assert.equal(res.staleSuspectExempts.length, 0,
    `零真值环境豁免零命中不得判僵尸（薄通道让位）：got ${res.staleSuspectExempts.length}`);
});

// 5b：对照锚——同一行有真值（61）时该行必进 suspect 且豁免命中（证明
// 第 5 路的绿不是「行没被抓」的假绿——真值在场时判读与豁免照常工作）。
test("suspect 豁免：真值在场时同款条目命中（对照锚）", () => {
  const res = suspectExemptFixture(REPLAY_LINE, `[{
		"path": "docs/current/01-定位与路线/夹具.md",
		"contains": "exec_step.mbt:95-100",
		"reason": "测试锚：有真值时命中"
	}]`, 61, "replay_assertions");
  const a = findAudit(res, "replay_assertions")!;
  assert.ok(a.suspect.length === 0 && a.suspectExempted.length === 1 && a.pending.length === 0,
    `有真值时该行应进 suspect 且被豁免命中：suspect=${a.suspect.length} exempted=${a.suspectExempted.length} pending=${a.pending.length}`);
  assert.equal(res.staleSuspectExempts.length, 0);
});
