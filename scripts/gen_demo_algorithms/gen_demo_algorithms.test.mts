// gen_demo_algorithms.test.mts —— 分组完备性 J9 / JS 反引号清洗 / 真实仓库全覆盖。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { GROUPS, camel, groupCoverageErrors, jsBacktick } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const RULES = "scripts/teaching_annotation_diff/rules.json";

function realMigrated(): Set<string> {
  const j = JSON.parse(fs.readFileSync(path.join(projectRoot(), RULES), "utf8")) as {
    migrated_algorithms: string[];
  };
  return new Set(j.migrated_algorithms);
}

test("真实仓库：分组表并集 == rules.json 迁移族全集（零误差）", () => {
  const errs = groupCoverageErrors(realMigrated());
  assert.deepEqual(errs, []);
});

test("J9：漏族即红（分组表少一个迁移族）", () => {
  const migrated = realMigrated();
  const errs = groupCoverageErrors(migrated);
  assert.equal(errs.length, 0);
  // 把一个不在组表里的族塞进迁移全集 → 必报「分组缺」
  const withGhost = new Set([...migrated, "not_a_real_family"]);
  const red = groupCoverageErrors(withGhost);
  assert.equal(red.length, 1);
  assert.match(red[0] ?? "", /分组表漂移/);
  assert.match(red[0] ?? "", /not_a_real_family/);
});

test("J9：多族即红（分组表有而 rules.json 无）", () => {
  const migrated = realMigrated();
  // 摘掉一个真实族 → 该族成为「分组有而 rules.json 无」
  const drop = migrated.values().next().value as string;
  const shrunk = new Set([...migrated].filter((a) => a !== drop));
  const red = groupCoverageErrors(shrunk);
  assert.equal(red.length, 1);
  assert.match(red[0] ?? "", new RegExp(drop));
});

test("J9：同族双挂即红（组表重复登记）", () => {
  // 直接对组表本体做注入：临时把首族塞进第二个组，跑完还原
  const g1 = GROUPS[1];
  assert.ok(g1 !== undefined);
  const before = [...(g1.algos ?? [])];
  g1.algos.push(GROUPS[0]?.algos[0] ?? "");
  try {
    const red = groupCoverageErrors(realMigrated());
    assert.ok(red.some((e) => /同时出现在组/.test(e)), red.join(" / "));
  } finally {
    g1.algos = before;
  }
});

test("camel：snake → camel（空段跳过）", () => {
  assert.equal(camel("kruskal_mst"), "kruskalMst");
  assert.equal(camel("bubble_sort"), "bubbleSort");
  assert.equal(camel("dp"), "dp");
  assert.equal(camel("a__b"), "aB");
});

test("jsBacktick：剥 PARAM 标记 + 反引号/反斜杠/${ 转义 + CRLF 归一", () => {
  assert.equal(jsBacktick("int a;/*__PARAM_x__*/"), "int a;");
  assert.equal(jsBacktick("a`b"), "a\\`b");
  assert.equal(jsBacktick("a\\b"), "a\\\\b");
  assert.equal(jsBacktick("`${x}`"), "\\`\\${x}\\`");
  assert.equal(jsBacktick("a\r\nb"), "a\nb");
  // 顺序锚：CRLF 归一是最后一步，反斜杠转义先做 → \r 不被二次处理
  assert.equal(jsBacktick("a\r\nb\\c"), "a\nb\\\\c");
});
