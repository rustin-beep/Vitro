// facts_keys.test.mts —— #534 门面数字双键锚（J9 证红）
//
// 背景：#533 实锤 README / moonbit/README 的「1426 用例 / 153 opcode /
// 119·121·137 诊断码」三族长期人肉同步必漂——本文件锁两件事：
//   1. 两键（opcode_variants / diag_code_count）在规则表在位，且真仓静态
//      采集值与源码同源（枚举变体数 / error_codes.json arms 排除 Unknown）；
//   2. 采集失败必写键（unavailable），不得缺键——缺键=落盘丢键假绿
//      （#298 病族第三例形态）。
//
// 说明（2026-11-17 重建批）：本文件由 #538 分支的 current_bypass.test.mts
// 裁剪而来——原文件同批还含 #532「现值行判据升级」的三条锚，该判据在
// 长历史表格行上误伤（5774 字符行含「漂移即红」即整行失去冻结豁免，
// --strict 假红），未采纳，其锚一并移除。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { rules } from "./audit.mts";
import { collectAll, collectDiagCodeCount, collectOpcodeVariants } from "./facts.mts";
import type { Fact, FactsDoc } from "./facts.mts";

function tmpRoot(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "facts-keys-"));
}

test("规则表含 #534 双键（opcode_variants / diag_code_count）", () => {
  const keys = new Set(rules().map((r) => r.key));
  assert.ok(keys.has("opcode_variants"), "缺少 opcode_variants 规则");
  assert.ok(keys.has("diag_code_count"), "缺少 diag_code_count 规则");
});

// ── #534 采集器锚（J9）：真仓静态采集值 + 缺失路径 fail loud 不丢键 ──────

const repoRoot = path.resolve(import.meta.dirname, "..", "..");
// Stryker 突变沙箱只复制被测闭包文件（无真仓目录树）——依赖真仓的锚必须
// 在沙箱里跳过，否则 mutation gate 干跑红（master 先例：demo_smoke 三向
// 对账在沙箱 ENOENT）。守卫 = 真仓标志文件在场。
const hasRealRepo = fs.existsSync(path.join(repoRoot, "moonbit", "opcode", "opcode.mbt"));

test("#534 真仓采集：opcode_variants=154 / diag_code_count=129", { skip: !hasRealRepo }, () => {
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

test("#534 三处对称：非 --run 的 collectAll 两键即有真值（静态采集档）", { skip: !hasRealRepo }, () => {
  const doc: FactsDoc = collectAll(repoRoot, false, false, "", null);
  assert.equal(doc.facts["opcode_variants"]?.status, "ok", "非 --run 档必须已有静态真值（占位不得覆盖）");
  assert.equal(doc.facts["diag_code_count"]?.status, "ok");
  assert.equal(doc.facts["opcode_variants"]!.value, 154);
});
