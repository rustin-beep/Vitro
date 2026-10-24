// diff_ledger.test.mts —— schema / 双向对账 / D18 一致性（内存注入）+ 真实仓库端到端。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { CAPABILITY_FLAGS_KEYS, loadKnownCases, main, selftest, validate } from "./main.mts";
import type { Difference, Ledger } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

function flags(): Record<string, unknown> {
  const o: Record<string, unknown> = {};
  for (const k of CAPABILITY_FLAGS_KEYS) o[k] = 1;
  return o;
}

function diff(over: Partial<Difference> = {}): Difference {
  return {
    id: "DIFF-PTR-4BYTE-01",
    title: "t",
    class: "architectural",
    carry_over: "inherit",
    status: "open",
    evidence: "run",
    anchors: { shadow_known: ["bTree_default.c"], clang_direct_known: [], vm_diff_known: [] },
    detectable_by_defense: ["shadow"],
    ...over,
  };
}

function mini(over: Partial<Ledger> = {}): Ledger {
  return { schema: "vitro-diff-ledger-v1", capability_flags: flags(), differences: [diff()], ...over };
}

const SHADOW = ["bTree_default.c"];
const CD = ["case_a.c"];
const VD = ["case_v.c"];

test("绿：单条差异 + 三防线 known 全被收编", () => {
  assert.deepEqual(validate(mini(), SHADOW, [], []), []);
  assert.deepEqual(validate(mini({ differences: [diff({ anchors: { shadow_known: [], clang_direct_known: ["case_a.c"], vm_diff_known: ["case_v.c"] }, detectable_by_defense: ["clang_direct", "vm_diff"] })] }), [], CD, VD), []);
});

test("J9 六路：假 anchor / 反向失覆盖 / class / ID 重复 / 删 flag / D18 矛盾", () => {
  const bad = (l: Ledger): string => validate(l, SHADOW, CD, VD).join("\n");

  // 假 anchor（引用不在防线真值的 case）
  const ghost = mini({ differences: [diff({ anchors: { shadow_known: ["ghost.c"], clang_direct_known: ["case_a.c"], vm_diff_known: ["case_v.c"] }, detectable_by_defense: ["shadow", "clang_direct", "vm_diff"] })] });
  assert.match(bad(ghost), /shadow_known 引用不存在的豁免条目: ghost\.c/);

  // 反向失覆盖（known 有条目但无差异收编）
  const uncovered = mini({ differences: [diff({ anchors: { shadow_known: ["bTree_default.c"], clang_direct_known: ["case_a.c"], vm_diff_known: [] }, detectable_by_defense: ["shadow", "clang_direct"] })] });
  assert.match(bad(uncovered), /vm_diff known 条目未被台账收编（沉默漂移）: case_v\.c/);

  // class 越界
  assert.match(bad(mini({ differences: [diff({ class: "cosmetic" })] })), /class 越界: cosmetic/);

  // ID 重复 + 格式
  const dup = mini({ differences: [diff(), diff()] });
  assert.match(bad(dup), /ID 重复: DIFF-PTR-4BYTE-01/);
  const badId = mini({ differences: [diff({ id: "diff-1" })] });
  assert.match(bad(badId), /ID 格式非法: diff-1/);

  // 删 flag 键
  const noFlag = mini();
  delete noFlag.capability_flags["time_source"];
  assert.match(bad(noFlag), /capability_flags 键数 16 ≠ 17（键集锁定）/);

  // D18：有锚防线未列入 detectable
  const d18 = mini({ differences: [diff({ detectable_by_defense: [] })] });
  assert.match(bad(d18), /detectable_by_defense 缺有锚防线 shadow（anchors 与旁证字段矛盾——D18）/);
});

test("J9：detectable 值域 / evidence 值域 / schema / empty / 空锚串", () => {
  const bad = (l: Ledger): string => validate(l, SHADOW, CD, VD).join("\n");
  assert.match(bad(mini({ differences: [diff({ detectable_by_defense: ["shadow", "ninja"] })] })), /detectable_by_defense 越界: ninja/);
  assert.match(bad(mini({ differences: [diff({ evidence: "vibes" })] })), /evidence 越界: vibes/);
  assert.match(bad(mini({ schema: "v0" })), /schema 字符串 ≠ vitro-diff-ledger-v1: v0/);
  assert.match(bad(mini({ differences: [] })), /differences 为空/);
  assert.match(bad(mini({ differences: [diff({ anchors: { shadow_known: [" "], clang_direct_known: [], vm_diff_known: [] } })] })), /shadow_known 含空串/);
});

test("loadKnownCases：真实两文件可读；缺文件 exit 2", () => {
  assert.equal(loadKnownCases("scripts/clang_direct/known_direct.json").length, 16);
  assert.equal(loadKnownCases("scripts/vm_diff/known_diffs.json").length, 5);

  const missing = spawnSync(process.execPath, [MAIN, "scripts/diff_ledger/nope.json"], {
    cwd: projectRoot(),
    encoding: "utf8",
  });
  assert.equal(missing.status, 2);
  assert.match(missing.stderr, /fail loud：读不到/);
});

test("selftest：六路注入均红（返回 0，无 exit）", () => {
  const l = JSON.parse(
    fs.readFileSync(path.join(projectRoot(), "scripts/diff_ledger/ledger.json"), "utf8"),
  ) as Ledger;
  assert.equal(selftest(l, SHADOW, loadKnownCases("scripts/clang_direct/known_direct.json"), loadKnownCases("scripts/vm_diff/known_diffs.json")), 0);
});

test("真实仓库端到端：默认 PASS 行逐字 + selftest 六路 + 自定义 ledger 位置参数", () => {
  const root = projectRoot();
  const def = spawnSync(process.execPath, [MAIN], { cwd: root, encoding: "utf8" });
  assert.equal(def.status, 0, def.stderr);
  assert.match(def.stdout, /\[diff_ledger\] 条目 \d+ \| capability_flags 17 \| shadow 3 \+ clang_direct 16 \+ vm_diff 5 条 known 对账/);
  assert.match(def.stdout, /\[diff_ledger\] PASS：schema \+ 双向对账全绿（守门规则机化就位）|\[diff_ledger\] PASS：schema \+ 双向对账全绿/);

  const self = spawnSync(process.execPath, [MAIN, "--selftest"], { cwd: root, encoding: "utf8" });
  assert.equal(self.status, 0, self.stderr);
  assert.match(self.stdout, /\[selftest\] 六路全红，闸可信/);

  // 位置参数：临时 bad ledger 必红 exit 1
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-dl-"));
  const p = path.join(dir, "ledger.json");
  fs.writeFileSync(p, JSON.stringify(mini({ differences: [diff({ class: "cosmetic" })] })));
  const r = spawnSync(process.execPath, [MAIN, p], { cwd: root, encoding: "utf8" });
  assert.equal(r.status, 1);
  // 单条坏差异同时触发反向「未收编」多条——只锁总量与关键违规行
  assert.match(r.stderr, /✗ \d+ 条违规/);
  assert.match(r.stderr, /class 越界: cosmetic/);
  assert.equal(main([p]), 1);
});
