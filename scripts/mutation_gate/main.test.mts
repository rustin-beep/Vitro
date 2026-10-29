// mutation_gate 单测（四件套 node:test 面）——hunk 解析/区间合并/导入闭包/
// config 形状/汇总聚合。端到端 J9（已知 survived 必报、已知 killed 不误报）
// 见 #368 落地批的突变重放记录（人工流程，不入单测——须真跑 Stryker）。
import test from "node:test";
import assert from "node:assert/strict";
import {
  parseHunks,
  mergeRanges,
  extractRelativeImports,
  testClosureFor,
  buildStrykerConfig,
  summarizeMutationReport,
  toScriptsRel,
} from "./main.mts";

test("parseHunks：unified=0 diff 的新侧行区间（含省略 count=1 形态与纯删除跳过）", () => {
  const diff = [
    "diff --git a/scripts/x.mts b/scripts/x.mts",
    "--- a/scripts/x.mts",
    "+++ b/scripts/x.mts",
    "@@ -10 +12,3 @@ fn a() {",
    "+let x = 1;",
    "+let y = 2;",
    "+let z = 3;",
    "@@ -20,2 +18 @@ fn b() {",
    "+changed",
    "diff --git a/scripts/gone.mts b/scripts/gone.mts",
    "--- a/scripts/gone.mts",
    "+++ /dev/null",
    "@@ -1,2 +0,0 @@",
    "-deleted",
    "-lines",
    "diff --git a/README.md b/README.md",
    "--- a/README.md",
    "+++ b/README.md",
    "@@ -1 +1 @@",
    "+doc",
  ].join("\n");
  const { rangesByFile, skipped } = parseHunks(diff);
  assert.deepEqual(rangesByFile.get("scripts/x.mts"), [[12, 14], [18, 18]]);
  // gone.mts 的 +++ 是 /dev/null，不登记为 .mts 面
  assert.equal(rangesByFile.has("scripts/gone.mts"), false);
  assert.equal(skipped.includes("scripts/gone.mts"), false);
  assert.equal(rangesByFile.has("README.md"), false);
  void skipped;
});

test("mergeRanges：相邻（gap<=1）合并、远距保留", () => {
  assert.deepEqual(mergeRanges([[5, 6], [1, 3], [4, 4], [10, 12]]), [[1, 6], [10, 12]]);
  assert.deepEqual(mergeRanges([[1, 2], [4, 5]]), [[1, 2], [4, 5]]);
});

test("extractRelativeImports：相对导入解析、裸包名/注释噪声不误收", () => {
  const src = [
    'import fs from "node:fs";',
    'import { canonicalize } from "../../internal/canonicalize.mts";',
    'import "./side.mts";',
    'export { x } from "../lib/a.mts";',
    '// from "nope.mts" 是注释',
  ].join("\n");
  const got = extractRelativeImports(src, "sub/dir/main.mts");
  assert.deepEqual(got, ["internal/canonicalize.mts", "sub/dir/side.mts", "sub/lib/a.mts"]);
});

test("testClosureFor：传递闭包到测试文件为止；测试不再上溯其导入面", () => {
  const graph = new Map<string, Set<string>>([
    ["internal/util.mts", new Set(["realcode/main.mts"])],
    ["realcode/main.mts", new Set(["realcode/main.test.mts", "other/x.mts"])],
    ["other/x.mts", new Set(["other/x.test.mts"])],
    ["orphan.mts", new Set()],
  ]);
  const tests = new Set(["realcode/main.test.mts", "other/x.test.mts"]);
  // util 的闭包经 main.mts 上溯到 x.mts，带出两份测试（传递闭包语义）
  assert.deepEqual(testClosureFor("internal/util.mts", graph, tests), [
    "other/x.test.mts",
    "realcode/main.test.mts",
  ]);
  assert.deepEqual(testClosureFor("other/x.mts", graph, tests), ["other/x.test.mts"]);
  assert.deepEqual(testClosureFor("orphan.mts", graph, tests), []);
});

test("buildStrykerConfig：mutate 区间条目与杀阵命令形状", () => {
  const cfg = buildStrykerConfig(["a.test.mts", "b/c.test.mts"], ["x.mts:1-3", "y.mts:10-12"], "out/m.json", 4);
  assert.equal(cfg.testRunner, "command");
  assert.equal(cfg.commandRunner.command, "node --test --test-concurrency=1 a.test.mts b/c.test.mts");
  assert.deepEqual(cfg.mutate, ["x.mts:1-3", "y.mts:10-12"]);
  assert.equal(cfg.jsonReporter.fileName, "out/m.json");
});

test("summarizeMutationReport：状态分桶 + survived 行带位置与算子", () => {
  const report = {
    files: {
      "x.mts": {
        mutants: [
          { status: "Killed", location: { start: { line: 1 } }, mutatorName: "IfStatement" },
          { status: "Survived", location: { start: { line: 2 } }, mutatorName: "StringLiteral", description: '"" → "x"' },
          { status: "Survived", location: { start: { line: 3 } }, mutatorName: "ArrowFunction" },
          { status: "Timeout", location: { start: { line: 4 } }, mutatorName: "A" },
          { status: "CompileError", location: { start: { line: 5 } }, mutatorName: "B" },
        ],
      },
      "empty.mts": { mutants: [] },
    },
  };
  const { summaries, survivedList } = summarizeMutationReport(report);
  assert.equal(summaries.length, 1);
  const s = summaries[0];
  assert.equal(s?.total, 5);
  assert.equal(s?.killed, 1);
  assert.equal(s?.survived, 2);
  assert.equal(s?.timeout, 1);
  assert.equal(s?.errors, 1);
  assert.equal(survivedList.length, 2);
  assert.match(survivedList[0] ?? "", /^x\.mts:2 \[StringLiteral\]/);
});

test("toScriptsRel：diff 前缀归一（CI 首跑实锤回归锚——前缀不匹配导致闭包空、全部误判零测试可达）", () => {
  assert.equal(toScriptsRel("scripts/mutation_gate/main.mts"), "mutation_gate/main.mts");
  assert.equal(toScriptsRel("internal/canonicalize.mts"), "internal/canonicalize.mts");
});
