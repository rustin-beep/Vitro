// suspect.test.mts —— Manual 桶兜底（FactAudit.suspect，2026-09-23）的证红锚
// 测试（J9）。直译自 suspect_test.go。
//
// 背景：分解式行（`682 个用例（678 + 3 + 1）`）因"子项与总数无法机判区分"
// 被归入 Manual 桶豁免漂移判定——`facts check` 恒绿。于是**真值变化时若只改
// 了一部分数字**（或整行都没跟上），门禁完全看不见。实测：d1b2d54 批次
// README.md:81 写 `682 个用例（完全匹配 678 + 3 + 1）` 而真值 683，
// `facts check` 报"漂移 0"。
//
// 兜底判据：整行候选数字中**是否有任一个等于真值**。本测试锁三件事：
//   1. 整行无数字对上真值 → 进 suspect（默认提醒、--strict 判红的依据）；
//   2. 行内任一数字对上真值 → 不进 suspect（不误伤正确维护的分解式行）；
//   3. suspect 是 manual 的**子集**（不改变 manual 桶口径，纯增量）。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { auditDocs, findAudit, truthsInRange, rules } from "./audit.mts";
import type { AuditResult, FactAudit } from "./audit.mts";
import type { Fact, FactsDoc } from "./facts.mts";

function tmpRoot(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "facts-suspect-"));
}

// suspectFixture：写一行到 docs/current 下的临时文档，跑 auditDocs。
function suspectFixture(key: string, truth: number, line: string): FactAudit {
  const root = tmpRoot();
  const p = path.join(root, "docs", "current", "01-定位与路线", "夹具.md");
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, line + "\n");
  const doc: FactsDoc = {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: { [key]: { value: truth, unit: "", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "" } as Fact },
  };
  const res = auditDocs(root, doc);
  const a = findAudit(res, key);
  if (a === undefined) throw new Error(`规则 ${key} 未出现在审计结果中`);
  return a;
}

// 真实样本（README.md:81 形态）：总数与全部子项都没跟上真值 → 必进 suspect。
test("suspect：整行无数字对上真值必进 suspect", () => {
  const a = suspectFixture("shadow_c_cases", 683,
    "- **C 教学子集**：C Shadow Verification **682 个用例**（完全匹配 678 + known_issue 3 + gap_extension 1，无非预期差异；vitro_better 已清零）");
  assert.equal(a.manual.length, 1, `分解式行应进 manual：manual=${a.manual.length}`);
  assert.equal(a.suspect.length, 1, `整行无数字等于真值 683（行内 {682,678,3,1}）应进 suspect：suspect=${a.suspect.length}`);
});

// 反向：只改了总数、子项仍留旧值 —— 行内含真值（总数那处）⇒ 不进 suspect。
test("suspect：行内总数等于真值不进 suspect", () => {
  const a = suspectFixture("shadow_c_cases", 683,
    "- C Shadow Verification **683 个用例**（完全匹配 678 + known_issue 3 + gap_extension 1）");
  assert.equal(a.manual.length, 1, "仍应进 manual");
  assert.equal(a.suspect.length, 0, "行内总数 683 等于真值，不应进 suspect");
});

// 子项对上真值也算——用"真值落在子项位"的形态复检，确保不是只看首数。
test("suspect：真值落在子项位不进 suspect", () => {
  const a = suspectFixture("shadow_cpp_cases", 95,
    "- C++ 侧 **99 个用例**（95 一致 + 4 clang_compile_fail）");
  assert.equal(a.suspect.length, 0, "子项 95 等于真值，不应进 suspect");
});

// suspect 必须是 manual 的子集（本兜底是纯增量，不改 manual 口径）。
test("suspect：必为 manual 子集", () => {
  const a = suspectFixture("shadow_c_cases", 683,
    "- C Shadow Verification **682 个用例**（完全匹配 678 + 3 + 1）");
  assert.ok(a.suspect.length <= a.manual.length, `suspect(${a.suspect.length}) 必须 ≤ manual(${a.manual.length})`);
  for (const s of a.suspect) {
    const found = a.manual.some((m) => m.file === s.file && m.lineNo === s.lineNo);
    assert.ok(found, `suspect 条目 ${s.file}:${s.lineNo} 不在 manual 中`);
  }
});

// 非分解式行（不触发 warn）走 drift 老路，不被兜底截胡——防止误改判定归属。
test("suspect：不劫持普通 drift", () => {
  const a = suspectFixture("shadow_c_cases", 683,
    "- C Shadow Verification 682 个用例");
  assert.equal(a.drift.length, 1, "非分解式写错仍应判 drift=1");
  assert.equal(a.suspect.length, 0, "非 manual 行不得进 suspect");
});

// cargo 规则 pattern 不得被 facts 键名 `moonbit_test_passed` 的 "passed"
// 子串误命中（2026-09-29 实锤）。
test("cargo 规则忽略 facts 键名形态", () => {
  const a = suspectFixture("cargo_test_passed", 1027,
    "moon check && moon test    # 508 测试（source 14 + opcode 10 分解和 502；裸总数以 facts `moonbit_test_passed` 为准）");
  assert.equal(a.manual.length, 0, "facts 键名 moonbit_test_passed 不得使 moon 分解式行进 cargo 规则 manual");
  assert.equal(a.suspect.length, 0, "facts 键名 moonbit_test_passed 不得使 moon 分解式行进 cargo 规则 suspect");
});

// 反向锚：数字紧邻 passed 的真实形态（"1027 passed"）仍必须命中。
test("cargo 规则仍命中数字紧邻 passed", () => {
  const a = suspectFixture("cargo_test_passed", 1027,
    "- 防线快照：1027 passed，0 failed（分解式 1025 + 2）");
  assert.equal(a.manual.length, 1, "数字紧邻 passed 的分解式行仍应进 manual");
  assert.equal(a.suspect.length, 0, "行内总数 1027 等于真值，不应进 suspect");
});

// moonbit 区间带宽锚（2026-09-29）：真值落在区间内时，行内等于真值的数字
// 使其不进 suspect。
test("moonbit 真值在区间内不进 suspect", () => {
  const a = suspectFixture("moonbit_test_passed", 508,
    "moon check && moon test    # 508 测试（source 14 + opcode 10 分解和 502）");
  assert.equal(a.suspect.length, 0, "行内 508 等于真值且在区间内，不应进 suspect");
});

// truthsInRange 自检锚（2026-09-29，模块审阅 09 P2-2 治本）：真值越出规则
// 带宽必须被检出。两个方向各锁一条（E11 形态 = 越下界；b28736a 形态 =
// 越上限），并锁在界真值不误报。
test("truthsInRange 自检：越界两侧均检出、在界不误报", () => {
  const mkFacts = (kv: Record<string, number>): FactsDoc => ({
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: Object.fromEntries(Object.entries(kv).map(([k, v]): [string, Fact] =>
      [k, { value: v, unit: "", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "" }])),
  });
  // 越下界（09 号 E11 原始形态：shadow_c_cases 区间 [400,900]，真值 383）
  const r1 = truthsInRange(rules(), mkFacts({ shadow_c_cases: 383 }));
  assert.ok(r1.out && r1.key === "shadow_c_cases" && r1.truth === 383,
    `真值 383 越下界 400 未被检出：${JSON.stringify(r1)}`);
  // 越上限（b28736a 原始形态：moonbit 区间 [40,2000]，真值 2001 模拟 S8 后再越界）
  const r2 = truthsInRange(rules(), mkFacts({ moonbit_test_passed: 2001 }));
  assert.ok(r2.out && r2.key === "moonbit_test_passed", `真值 2001 越上限 2000 未被检出`);
  // 在界不误报
  const r3 = truthsInRange(rules(), mkFacts({ moonbit_test_passed: 508 }));
  assert.ok(!r3.out, "真值 508 在区间 [40,2000] 内，不应误报越界");
});

// 供其他测试文件复用的 findAudit re-export 形态（Go 版同文件 helper）。
export { auditDocs, findAudit };
export type { AuditResult, FactAudit };
