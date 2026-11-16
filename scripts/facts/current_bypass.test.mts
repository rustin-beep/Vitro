// current_bypass.test.mts —— #532 现值行判据锚（J9 证红）
//
// 背景：#532 实锤 README.md:28/145 的现值句（`moon test` 1426 用例）因行尾
// 附历史勘探注记（as_of 2026-10-02）被 classifyLine 整行冻结——陈旧测试数
// 搭日期便车，`facts --strict` 长期报"漂移 0"的假绿。
//
// 判据（本文件锁三件事）：
//   1. 现值声明词与日期/as-of 词同行的 → 不得整行冻结，降级 manual+suspect
//      （--strict 判红，可经 suspect_exemptions.json 豁免）；
//   2. 纯历史行（无现值声明词）→ 维持冻结豁免不变；
//   3. 现值词+日期但数字已对 → 不冻结、不进漂移（不误伤已维护行）。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { auditDocs, findAudit, rules } from "./audit.mts";
import { collectAll, collectDiagCodeCount, collectOpcodeVariants } from "./facts.mts";
import type { Fact, FactsDoc } from "./facts.mts";

function tmpRoot(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "facts-current-bypass-"));
}

function fixture(truth: number, line: string) {
  const root = tmpRoot();
  const p = path.join(root, "docs", "current", "01-定位与路线", "夹具.md");
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, line + "\n");
  const doc: FactsDoc = {
    schema: "vitro.facts.v1", generated_at: "", git: { rev: "", branch: "", dirty: false },
    facts: {
      moonbit_test_passed: {
        value: truth, unit: "用例", source: "", provenance: "", as_of: "", status: "ok", note: "", how_to_get: "",
      } as Fact,
    },
  };
  const a = findAudit(auditDocs(root, doc), "moonbit_test_passed");
  if (a === undefined) throw new Error("规则 moonbit_test_passed 未出现在审计结果中");
  return a;
}

test("现值词+日期同行：不冻结，陈旧数字降级 Suspect", () => {
  const a = fixture(1546,
    "- **验证**：`moon test` **1426 用例**全绿（本行为现值行——留在 facts 数字对账管束内，漂移即红即连坐）；历史勘探 as_of 2026-10-02");
  assert.equal(a.frozen.length, 0, "现值声明行不得整行冻结（#532 核心判据）");
  assert.equal(a.manual.length, 1, "混合行应进 manual（不自动 sync）");
  assert.equal(a.suspect.length, 1, "现值数字未连坐应进 Suspect（--strict 判红）");
  assert.equal(a.drift.length, 0, "混合行不直接判 drift（降级 Suspect 语义）");
});

test("纯历史行（无现值词）：维持冻结豁免", () => {
  const a = fixture(1546,
    "- 历史记录：当时 `moon test` **1426 用例**（as_of 2026-10-02，已过时）");
  assert.equal(a.frozen.length, 1, "无现值声明的历史行照旧冻结");
  assert.equal(a.suspect.length, 0, "冻结行不进 Suspect");
});

test("现值词+日期但数字已对：不冻结也不进 Suspect", () => {
  const a = fixture(1546,
    "- **验证**：`moon test` **1546 用例**全绿（本行为现值行；漂移即红）——历史勘探 as_of 2026-10-02");
  assert.equal(a.frozen.length, 0);
  assert.equal(a.suspect.length, 0);
  assert.equal(a.drift.length, 0);
});

test("规则表含 #534 双键（opcode_variants / diag_code_count）", () => {
  const keys = new Set(rules().map((r) => r.key));
  assert.ok(keys.has("opcode_variants"), "缺少 opcode_variants 规则");
  assert.ok(keys.has("diag_code_count"), "缺少 diag_code_count 规则");
});

// ── #534 采集器锚（J9）：真仓静态采集值 + 缺失路径 fail loud 不丢键 ──────

const repoRoot = path.resolve(import.meta.dirname, "..", "..");

test("#534 真仓采集：opcode_variants=154 / diag_code_count=129", () => {
  const facts: Record<string, Fact> = {};
  collectOpcodeVariants(repoRoot, facts);
  collectDiagCodeCount(repoRoot, facts);
  assert.equal(facts["opcode_variants"]!.status, "ok", JSON.stringify(facts["opcode_variants"]));
  assert.equal(facts["opcode_variants"]!.value, 154, "enum OpCode 变体数（增删须连坐文档三族与 README 声明）");
  assert.equal(facts["diag_code_count"]!.status, "ok", JSON.stringify(facts["diag_code_count"]));
  assert.equal(facts["diag_code_count"]!.value, 129, "error_codes.json arms 排除 Unknown（增删须连坐文档三族）");
});

test("J9：源文件缺失 → unavailable 且键不丢（#298 病族防线）", () => {
  const root = tmpRoot();
  const facts: Record<string, Fact> = {};
  collectOpcodeVariants(root, facts);
  collectDiagCodeCount(root, facts);
  assert.ok("opcode_variants" in facts, "采集失败也必须写键（缺键=落盘丢键假绿）");
  assert.ok("diag_code_count" in facts);
  assert.equal(facts["opcode_variants"]!.status, "unavailable");
  assert.equal(facts["diag_code_count"]!.status, "unavailable");
});

test("#534 三处对称：非 --run 的 collectAll 两键即有真值（静态采集档）", () => {
  const doc: FactsDoc = collectAll(repoRoot, false, false, "", null);
  assert.equal(doc.facts["opcode_variants"]?.status, "ok", "非 --run 档必须已有静态真值（占位不得覆盖）");
  assert.equal(doc.facts["diag_code_count"]?.status, "ok");
  assert.equal(doc.facts["opcode_variants"]!.value, 154);
});
