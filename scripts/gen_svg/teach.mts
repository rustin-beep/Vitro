// teach.mts —— 图 M：教学智能 43 算法族流水线（detect + infer 双机制）（#273 存量
// Go 重写批；原 teach.go，S8 收官文档配套）。
//
// 输入源 = 盘上真值文件活值直读（不经 facts 中转）：① rules.json 迁移族全集
// ② golden 总条数 ③ templates 模板数。
//
// 七组分组表与 gen_demo_algorithms 同源复制，完备性断言同款（组表并集 ==
// 迁移族全集、组表不含非迁移族，违者 fatal）——两处表一处变，另一处 gen_svg
// -check（CI hygiene）即红顶人审。
import fs from "node:fs";
import path from "node:path";
import {
  MARKER_DEF,
  arrow,
  box,
  fatal,
  svgOpen,
  textF,
  textL,
  writeSVG,
} from "./svg.mts";

/**
 * 七组呈现层分组（与 scripts/gen_demo_algorithms 的 GROUPS 表同源——组概念属
 * UI 非引擎语义；完备性由机判断言保证）。注意 mathdp 组的 label 与
 * gen_demo_algorithms 的「数学与动态规划」刻意不同（历史排版宽度约束），
 * 两侧同步时不要「顺手统一」——那会让 teach 图失步。
 */
const TEACH_GROUPS: { id: string; label: string; algos: string[] }[] = [
  {
    id: "sorting",
    label: "排序",
    algos: ["bubble_sort", "insertion_sort", "merge_sort", "quick_sort", "selection_sort", "heap_sort", "counting_sort", "shell_sort", "radix_sort"],
  },
  { id: "search", label: "查找", algos: ["binary_search", "is_prime"] },
  { id: "graph", label: "图", algos: ["bfs", "dfs", "dijkstra", "floyd", "kruskal_mst", "prim_mst", "topological_sort"] },
  {
    id: "tree",
    label: "树",
    algos: ["bst_insert", "bst_search", "bst_delete", "bst_validate", "avl_tree", "huffman_tree", "level_order", "threaded_binary_tree"],
  },
  {
    id: "structures",
    label: "结构",
    algos: ["linked_list_append", "linked_list_delete", "static_linked_list", "circular_linked_list", "linked_stack", "linked_queue", "circular_queue", "hash_table", "seq_list", "union_find", "josephus"],
  },
  { id: "string", label: "字符串", algos: ["string_match_bf", "string_match_kmp", "string_reverse"] },
  { id: "mathdp", label: "数学·DP", algos: ["gcd", "hanoi", "dp"] },
];

function readOrDie(p: string, what: string): string {
  try {
    return fs.readFileSync(p, "utf8");
  } catch (e) {
    return fatal(`读 ${what} 失败: ${(e as Error).message}`);
  }
}

export function genTeach(root: string): void {
  const g = (rel: string): string => path.join(root, rel);

  // ── 数据采集（fail loud）──
  const rulesRaw = readOrDie(g("scripts/teaching_annotation_diff/rules.json"), "rules.json");
  let migrated: string[];
  try {
    migrated = (JSON.parse(rulesRaw) as { migrated_algorithms: string[] }).migrated_algorithms;
  } catch (e) {
    return fatal(`解析 rules.json 失败: ${(e as Error).message}`);
  }
  if (!Array.isArray(migrated) || migrated.length === 0) fatal("rules.json migrated_algorithms 为空");
  const family = new Set(migrated);
  const nFamilies = migrated.length;

  const goldRaw = readOrDie(
    g("scripts/teaching_annotation_diff/golden/algorithm_annotations_v3.json"),
    "algorithm_annotations_v3.json",
  );
  let golden: Record<string, unknown[]>;
  try {
    golden = JSON.parse(goldRaw) as Record<string, unknown[]>;
  } catch (e) {
    return fatal(`解析 algorithm_annotations_v3.json 失败: ${(e as Error).message}`);
  }
  let nGolden = 0;
  for (const v of Object.values(golden)) nGolden += v.length;

  const tplDir = g("templates");
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(tplDir, { withFileTypes: true });
  } catch (e) {
    return fatal(`读 templates/ 失败: ${(e as Error).message}`);
  }
  let nTemplates = 0;
  for (const e of entries) {
    if (e.isDirectory() && fs.existsSync(path.join(tplDir, e.name, "source.c"))) nTemplates++;
  }

  // 七组交集计数 + 完备性断言（与 gen_demo_algorithms 断言同款，fail loud）
  const counts: number[] = TEACH_GROUPS.map(() => 0);
  const covered = new Set<string>();
  TEACH_GROUPS.forEach((grp, gi) => {
    for (const a of grp.algos) {
      if (!family.has(a)) {
        fatal(`分组表含非迁移族 ${a}（组 ${grp.id}）——与 gen_demo_algorithms 表失去同步，两侧同改`);
      }
      counts[gi] = (counts[gi] ?? 0) + 1;
      covered.add(a);
    }
  });
  for (const a of family) {
    if (!covered.has(a)) {
      fatal(`迁移族 ${a} 未入任何分组——分组表缺族，与 gen_demo_algorithms 两侧同改`);
    }
  }

  // ── 绘制 ──
  const P: string[] = svgOpen(
    1200,
    890,
    "vitro 教学智能算法族流水线",
    "教学智能 · detect 编译期识别 + infer 执行期推断",
    `对账 S8时间旅行与教学智能总览.md §二；数字=盘上真值活值直读（rules.json ${nFamilies} 族 / golden ${nGolden} 条 / templates ${nTemplates} 模板），重生成 node scripts/gen_svg/main.mts teach`,
  );
  P.push(
    MARKER_DEF,
    textF(600, 56, "tt", `教学智能 · ${nFamilies} 算法族识别与逐帧推断`, ""),
    textF(600, 92, "tm", "detect 编译期识别 + infer 执行期推断 · 教学中文文案由引擎生成（非前端拼装）", ""),
  );

  // 输入条：双通道源头
  P.push(box(40, 118, 1120, 64, "core", 12));
  P.push(
    textF(320, 148, "ts", "C 源码", ""),
    textF(320, 172, "tc", `templates/ · ${nTemplates} 模板（含变体）`, ""),
    textF(880, 148, "ts", "VM 逐帧执行现场", ""),
    textF(880, 172, "tc", "调用栈 / 局部变量 / 内存快照 / 输出游标", ""),
  );
  P.push(arrow(320, 182, 320, 230, "edge"), arrow(880, 182, 880, 230, "edge"));

  // 左 zone：编译期识别 detect
  P.push(
    box(40, 236, 545, 356, "zone", 14),
    textF(312, 272, "t", "编译期识别 detect", ""),
    textF(312, 300, "tm", "vitro/engine/teaching/steps · detect*.mbt 按域拆分", ""),
  );
  P.push(
    box(64, 320, 497, 92, "card", 10),
    textF(312, 348, "ts", "U1#1 收紧版判据", ""),
    textL(88, 376, "tc", "函数命名主导（sort / search / tree …）"),
    textL(88, 400, "tc", "结构特征辅助 · 编译期一次判定"),
  );
  P.push(
    box(64, 432, 497, 144, "card", 10),
    textF(312, 460, "ts", "compile 帧 · algorithm_matches 字段", ""),
    textL(88, 488, "tc", "族名 / 中文名 / 函数 / 置信度 / 行号 / vis_events"),
    textL(88, 512, "tc", "协议「只增不改」纪律内 · 自诞生即可选"),
    textL(88, 536, "tc", "消费方：demo 侧栏 · agent（CLI --json 同源）"),
  );

  // 右 zone：执行期推断 infer
  P.push(
    box(615, 236, 545, 356, "zone", 14),
    textF(888, 272, "t", "执行期推断 infer", ""),
    textF(888, 300, "tm", "vitro/engine/teaching/steps · infer*.mbt 逐帧驱动", ""),
  );
  P.push(
    box(639, 320, 497, 92, "card", 10),
    textF(888, 348, "ts", "逐帧推断 · 教学文案模板", ""),
    textL(663, 376, "tc", "「第 1 趟：将第 1 大的元素放到正确位置」"),
    textL(663, 400, "tc", "级说明由引擎生成 · 前端只渲染不拼装"),
  );
  P.push(
    box(639, 432, 497, 144, "card", 10),
    textF(888, 460, "ts", "StepPayload 教学字段（每帧）", ""),
    textL(663, 488, "tc", "semantic_label（受控词表 · schema 附录 B 单源）"),
    textL(663, 512, "tc", "algorithm_step（教学文案）+ vis_events（事件行）"),
    textL(663, 536, "tc", "local_vars / call_stack 快照"),
    textL(663, 560, "tc", "array_snapshots / pointer_snapshots"),
  );

  // 七组分布：活值机判
  P.push(
    box(40, 616, 1120, 108, "zone", 14),
    textF(600, 646, "t", "七组分布（rules.json 迁移族全集机判）", ""),
  );
  TEACH_GROUPS.forEach((grp, i) => {
    const x = 46 + i * 160;
    P.push(
      box(x, 660, 148, 48, "card", 10),
      textF(x + 74, 682, "tc", grp.label, ""),
      textF(x + 74, 702, "ts", String(counts[i] ?? 0), ""),
    );
  });

  // 对拍纪律
  P.push(
    box(40, 748, 1120, 76, "warn", 12),
    textF(600, 778, "t", "对拍纪律", ""),
    textF(
      600,
      806,
      "tc",
      `${nGolden} 条 golden 首现序列 · teaching_annotation_diff 机判（golden 已迁出冻结区，sha 对账自持）· ${nTemplates} 模板全绿（豁免显式过闸）`,
      "",
    ),
  );

  P.push(
    textF(600, 858, "tc", "对账 S8时间旅行与教学智能总览.md §二 · 漂移重生成：node scripts/gen_svg/main.mts teach", ""),
  );
  writeSVG(root, "docs/current/05-教学体验/teaching-detect-infer-pipeline.svg", P);
}
