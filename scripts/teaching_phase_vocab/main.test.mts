// teaching_phase_vocab.test.mts —— 抽取面 / 四路判定 / 真实仓库端到端。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { checkSet, extract, loadRules, selftestAll } from "./main.mts";
import type { Call, Rules } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

function tmpSteps(files: Record<string, string>): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-phasev-"));
  for (const [name, src] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), src);
  return dir;
}

const RULES: Rules = {
  schema: 1,
  min_call_sites: 2,
  phases: [
    { phase: "compare", families: ["infer_bubble_sort"] },
    { phase: "swap", families: ["infer_bubble_sort"] },
  ],
};

test("extract：字面量命中 + family 归因到最近的 infer_* 函数", () => {
  const dir = tmpSteps({
    "infer_sorting.mbt": [
      "fn infer_bubble_sort(a : Array[Int]) -> Unit {",
      '  build_step(x, "compare", "比较")',
      '  build_step(x, "swap", "交换")',
      "}",
      "fn infer_quick_sort(a : Array[Int]) -> Unit {",
      '  build_step(a, "compare", "比较")',
      "}",
      "",
    ].join("\n"),
    "not_infer.mbt": 'build_step(x, "ignored", "y")\n',
  });
  const { calls, occurrences } = extract(dir);
  assert.equal(occurrences, 3);
  assert.deepEqual(
    calls.map((c) => [c.phase, c.family]),
    [
      ["compare", "infer_bubble_sort"],
      ["swap", "infer_bubble_sort"],
      ["compare", "infer_quick_sort"],
    ],
  );
});

test("extract：非字面量调用计入 occurrences 但不进 calls（④的判定前提）", () => {
  const dir = tmpSteps({
    "infer_dp.mbt": ['fn infer_dp() -> Unit {', '  build_step(x, "compare", "c")', "  build_step(x, ph, \"c\")", "}"].join("\n"),
  });
  const { calls, occurrences } = extract(dir);
  assert.equal(calls.length, 1);
  assert.equal(occurrences, 2);
});

test("checkSet：绿路径（四路全过）", () => {
  const calls: Call[] = [
    { phase: "compare", family: "infer_bubble_sort", file: "a.mbt" },
    { phase: "swap", family: "infer_bubble_sort", file: "a.mbt" },
  ];
  assert.deepEqual(checkSet(RULES, calls, 2), []);
});

test("J9 四路：未登记扩张 / 僵尸条目 / family 漂移 / 非字面量 + 下限塌缩", () => {
  const calls: Call[] = [
    { phase: "compare", family: "infer_bubble_sort", file: "a.mbt" },
    { phase: "swap", family: "infer_bubble_sort", file: "a.mbt" },
  ];
  const errsOf = (r: Rules, c: Call[], occ: number): string => checkSet(r, c, occ).join("\n");

  // ①未登记扩张
  const extra = errsOf(RULES, [...calls, { phase: "zz_new", family: "infer_bubble_sort", file: "a.mbt" }], 3);
  assert.match(extra, /未登记扩张：phase "zz_new"/);
  // ②僵尸条目
  const zombieRules: Rules = { ...RULES, phases: [...RULES.phases, { phase: "zz_zombie", families: ["infer_bubble_sort"] }] };
  assert.match(errsOf(zombieRules, calls, 2), /僵尸条目：rules\.json phase "zz_zombie"/);
  // ③family 漂移（双向）
  const driftRules: Rules = { ...RULES, phases: [{ phase: "compare", families: ["infer_old"] }, RULES.phases[1]!] };
  const drift = errsOf(driftRules, calls, 2);
  assert.match(drift, /family 漂移：phase "compare" 代码新增 \[infer_bubble_sort\] \/ 登记-renamed或删除 \[infer_old\]/);
  // ④非字面量
  assert.match(errsOf(RULES, calls, 5), /非字面量 phase 调用 3 处/);
  // 下限塌缩
  assert.match(errsOf(RULES, calls.slice(0, 1), 1), /抽取面塌缩：字面量命中 1 < min_call_sites 2/);
});

test("selftestAll：真数据基线上四路均红（返回 0）", () => {
  const root = projectRoot();
  const rules = loadRules(root);
  const { calls, occurrences } = extract(path.join(root, "moonbit/teaching/steps"));
  assert.equal(selftestAll(rules, calls, occurrences), 0);
});

test("真实仓库：绿路径文案与 Go 版逐字一致", () => {
  const root = projectRoot();
  const rules = loadRules(root);
  const { calls, occurrences } = extract(path.join(root, "moonbit/teaching/steps"));
  assert.deepEqual(checkSet(rules, calls, occurrences), []);
  const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts")], {
    cwd: root,
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(
    r.stdout,
    `teaching_phase_vocab 绿（phase ${rules.phases.length} 条 ↔ infer_* 调用 ${calls.length} 处字面量全等，四路判红在岗）\n`,
  );
});

test("selftest 子进程：exit 0；未知参数 exit 2（与 Go flag 用法错分流）", () => {
  const root = projectRoot();
  const ok = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "-selftest"], {
    cwd: root,
    encoding: "utf8",
  });
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout, /selftest 全过|selftest 路 4 OK/);

  const bad = spawnSync(process.execPath, [path.join(import.meta.dirname, "main.mts"), "--nope"], {
    cwd: root,
    encoding: "utf8",
  });
  assert.equal(bad.status, 2);
  assert.match(bad.stderr, /未知参数/);
});
