// gen_demo_algorithms.test.mts —— 分组完备性 J9 / JS 反引号清洗 / 真实仓库全覆盖。
// #36 收编批（2026-10-31）：族集/display_name/分组三源切引擎出口——旧锚
// （GROUPS 分组对账/detect 兜底）随源退役，新锚=引擎出口纯函数族。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  camel,
  jsBacktick,
  catalogArtifactPath,
  catalogConsistencyErrors,
  deriveGroups,
  fetchCatalog,
  type CatalogExport,
} from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const RULES = "scripts/teaching_annotation_diff/rules.json";

function realMigrated(): Set<string> {
  const j = JSON.parse(fs.readFileSync(path.join(projectRoot(), RULES), "utf8")) as {
    migrated_algorithms: string[];
  };
  return new Set(j.migrated_algorithms);
}

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

// ── #36 收编批（2026-10-31）：引擎出口纯函数锚 ─────────────────────

function fakeCatalog(): CatalogExport {
  return {
    schema: "algorithms.catalog/1",
    total: 2,
    groups: [
      { id: "sorting", label: "排序" },
      { id: "mathdp", label: "数学与动态规划" },
    ],
    algorithms: [
      { family: "bubble_sort", display_name: "冒泡排序", group: "sorting", vis_events: true },
      { family: "gcd", display_name: "最大公约数", group: "mathdp", vis_events: true },
    ],
  };
}

test("catalogConsistencyErrors：自洽目录零误差（引擎↔rules 双向一致）", () => {
  const errs = catalogConsistencyErrors(fakeCatalog(), new Set(["bubble_sort", "gcd"]));
  assert.deepEqual(errs, []);
});

test("J9：display_name 空即红", () => {
  const cat = fakeCatalog();
  cat.algorithms[0]!.display_name = "";
  const errs = catalogConsistencyErrors(cat, new Set(["bubble_sort", "gcd"]));
  assert.ok(errs.some((e) => /display_name/.test(e)), errs.join(" / "));
});

test("J9：group 引用不在 groups 即红", () => {
  const cat = fakeCatalog();
  cat.algorithms[0]!.group = "no_such_group";
  const errs = catalogConsistencyErrors(cat, new Set(["bubble_sort", "gcd"]));
  assert.ok(errs.some((e) => /no_such_group/.test(e)), errs.join(" / "));
});

test("J9：引擎↔rules 族集双向漂移即红（缺/多各证一路）", () => {
  // rules 多出（引擎缺族）
  const more = catalogConsistencyErrors(fakeCatalog(), new Set(["bubble_sort", "gcd", "hanoi"]));
  assert.ok(more.some((e) => /hanoi/.test(e) && /rules/.test(e)), more.join(" / "));
  // 引擎多出（rules 缺族）
  const less = catalogConsistencyErrors(fakeCatalog(), new Set(["bubble_sort"]));
  assert.ok(less.some((e) => /gcd/.test(e) && /引擎/.test(e)), less.join(" / "));
});

test("J9：同族重复登记即红", () => {
  const cat = fakeCatalog();
  cat.algorithms.push({ ...cat.algorithms[0]! });
  const errs = catalogConsistencyErrors(cat, new Set(["bubble_sort", "gcd"]));
  assert.ok(errs.some((e) => /重复/.test(e)), errs.join(" / "));
});

test("deriveGroups：分组按引擎 groups 派生，组内序 = 引擎 catalog 序", () => {
  const cat = fakeCatalog();
  // 插入一个同组族在中间——组内序须跟随引擎序而非字典序
  cat.algorithms.splice(1, 0, {
    family: "selection_sort", display_name: "选择排序", group: "sorting", vis_events: true,
  });
  const groups = deriveGroups(cat);
  assert.deepEqual(
    groups.map((g) => g.id),
    ["sorting", "mathdp"],
  );
  const sorting = groups[0];
  assert.deepEqual(sorting?.algos, ["bubble_sort", "selection_sort"]);
  assert.equal(sorting?.label, "排序");
});

test("真实仓库：引擎出口（api --batch 拉取）↔ rules.json 43 族双向零误差", (t) => {
  // P1-1（PR #403 审阅）：缺产物显式 skip——ensureFresh 的 die 是
  // process.exit(1)，直接调会吞掉同文件其余锚（干净检出 npm test 必红）。
  // 真拉取端到端锚保留给有产物的环境（catalog-check / demo 发射 / 本地）。
  const artifact = catalogArtifactPath(projectRoot());
  if (!fs.existsSync(artifact)) {
    t.skip(`前置缺失：${artifact}（先跑 cd moonbit && moon build --release --target js cmd/vitro_js）`);
    return;
  }
  const cat = fetchCatalog(projectRoot());
  const errs = catalogConsistencyErrors(cat, realMigrated());
  assert.deepEqual(errs, []);
  assert.equal(cat.total, 43);
});
