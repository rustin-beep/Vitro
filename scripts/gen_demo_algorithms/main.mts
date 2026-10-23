#!/usr/bin/env node
// gen_demo_algorithms.mts —— demo「算法可视化」侧栏数据生成器（#273 存量 Go
// 重写批；原 go scripts/gen_demo_algorithms，2026-10-04，refs #28）。
//
// 输入（全部机判真值源，禁手画——侧栏列表 = 渲染产物）：
//
//   ① scripts/teaching_annotation_diff/rules.json → migrated_algorithms 43 族全集
//   ② scripts/teaching_annotation_diff/golden/algorithm_annotations_v3.json →
//      模板→族映射 + display_name 中文名（工序③固化迁出冻结区 2026-10-05）
//   ③ templates/<tpl>/source.c → 每族代表示例源码
//   ④ moonbit/teaching/steps/detect*.mbt → build_match("<族>", "<中文名>") 兜底
//
// 输出：demo/algorithms.js（浏览器脚本形态，同 cases.js：全局 const 无导出）——
//
//   DEMO_ALGORITHMS = { groups: [{ id, label, items: [{ id, name, source }] }] }
//
// 完备性断言（漂移即红）：分组并集 == rules.json 43 族集合（漏/多/改名即红）；
// 每族须有代表模板（golden 首现）与非空 source.c；模板三桶对账 == templates 全集。
//
// 产物不入库（2026-10-04 发射化）：ci.yml 与 pages.yml 消费前现场发射，发射即
// 检查闸（断言失败即红）。.gitignore 有 demo/algorithms.js。
//
// 用法：node scripts/gen_demo_algorithms/main.mts
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { goQuote, sortBytes } from "../internal/gofmt.mts";

/** 七组呈现层分组（组概念属 UI 非引擎语义；完备性由断言机判）。 */
export interface Group {
  id: string;
  label: string;
  algos: string[];
}
export const GROUPS: Group[] = [
  {
    id: "sorting",
    label: "排序",
    algos: [
      "bubble_sort",
      "insertion_sort",
      "merge_sort",
      "quick_sort",
      "selection_sort",
      "heap_sort",
      "counting_sort",
      "shell_sort",
      "radix_sort",
    ],
  },
  { id: "search", label: "查找", algos: ["binary_search", "is_prime"] },
  {
    id: "graph",
    label: "图",
    algos: [
      "bfs",
      "dfs",
      "dijkstra",
      "floyd",
      "kruskal_mst",
      "prim_mst",
      "topological_sort",
    ],
  },
  {
    id: "tree",
    label: "树",
    algos: [
      "bst_insert",
      "bst_search",
      "bst_delete",
      "bst_validate",
      "avl_tree",
      "huffman_tree",
      "level_order",
      "threaded_binary_tree",
    ],
  },
  {
    id: "structures",
    label: "结构",
    algos: [
      "linked_list_append",
      "linked_list_delete",
      "static_linked_list",
      "circular_linked_list",
      "linked_stack",
      "linked_queue",
      "circular_queue",
      "hash_table",
      "seq_list",
      "union_find",
      "josephus",
    ],
  },
  {
    id: "string",
    label: "字符串",
    algos: ["string_match_bf", "string_match_kmp", "string_reverse"],
  },
  { id: "mathdp", label: "数学与动态规划", algos: ["gcd", "hanoi", "dp"] },
];

interface GoldenEntry {
  algorithm: string;
  display_name: string;
}
interface RulesFile {
  migrated_algorithms: string[];
}

const PARAM_MARK_RE = /\/\*__PARAM_[a-z_0-9]+__\*\//g;
const BUILD_MATCH_RE = /build_match\(\s*"([a-z_0-9]+)",\s*"([^"]+)"/g;

function die(msg: string): never {
  process.stderr.write("gen_demo_algorithms: " + msg + "\n");
  process.exit(1);
}

/**
 * 完备性断言一（纯函数，供 node:test 内存注入证红）：分组并集 == rules.json 族
 * 集合——同族双挂 / 漏族 / 多族各自成条。返回错误清单，main 里首条即 fail loud。
 */
export function groupCoverageErrors(migrated: Set<string>): string[] {
  const errs: string[] = [];
  const union = new Map<string, string>(); // algo → group id
  for (const grp of GROUPS) {
    for (const a of grp.algos) {
      const prev = union.get(a);
      if (prev !== undefined) {
        errs.push(`算法 ${a} 同时出现在组 ${prev} 与 ${grp.id}`);
        continue;
      }
      union.set(a, grp.id);
    }
  }
  const missing: string[] = [];
  const extra: string[] = [];
  for (const a of migrated) if (!union.has(a)) missing.push(a);
  for (const a of union.keys()) if (!migrated.has(a)) extra.push(a);
  if (missing.length > 0 || extra.length > 0) {
    sortBytes(missing);
    sortBytes(extra);
    errs.push(
      `分组表漂移：rules.json 有而分组缺 [${missing.join(" ")}]；分组有而 rules.json 无 [${extra.join(" ")}]`,
    );
  }
  return errs;
}

/**
 * 源码文本 → JS 反引号字面量内容，三项机械清洗：
 *
 *   ① 剥对拍模板的参数化注释标记 /*__PARAM_x__*\/（对拍 harness 的注入锚语法，
 *      直接展示教学观感差；剥注释不改语义，可编译性由 demo_smoke 43 源 compile 兜底）
 *   ② 反引号 / 反斜杠 / `${` 转义（JS 模板串字面量必需）
 *   ③ CRLF 归一（模板源 LF；防 Windows checkout 翻转产物字节）
 *
 * 顺序与 Go 版逐条对齐——CRLF 归一是最后一步（`\r` 不被前面任何替换触及）。
 */
export function jsBacktick(s: string): string {
  let out = s.replace(PARAM_MARK_RE, "");
  out = out.split("\\").join("\\\\");
  out = out.split("`").join("\\`");
  out = out.split("${").join("\\${");
  return out.split("\r\n").join("\n");
}

function appendUnique(list: string[], v: string): string[] {
  return list.includes(v) ? list : [...list, v];
}

/** Go `camel`：snake → camel（首段原样，后续段首字母大写）。 */
export function camel(snake: string): string {
  const parts = snake.split("_");
  let out = parts[0] ?? "";
  for (const w of parts.slice(1)) {
    if (w === "") continue;
    out += w.slice(0, 1).toUpperCase() + w.slice(1);
  }
  return out;
}

function readText(p: string, what: string): string {
  try {
    return fs.readFileSync(p, "utf8");
  } catch (e) {
    return die(`${what}: ${(e as Error).message}`);
  }
}

function listDir(p: string, what: string): fs.Dirent[] {
  try {
    return fs.readdirSync(p, { withFileTypes: true });
  } catch (e) {
    return die(`${what}: ${(e as Error).message}`);
  }
}

/** extra 覆盖源（scripts/gen_demo_algorithms/extra/<族>.c）→ 内容 + 是否命中。 */
function extraSrcFor(root: string, algo: string): { src: string; ok: boolean } {
  const p = path.join(root, "scripts", "gen_demo_algorithms", "extra", algo + ".c");
  try {
    return { src: fs.readFileSync(p, "utf8"), ok: true };
  } catch {
    return { src: "", ok: false };
  }
}

/** extra 族代表源已脱离 templates 目录——此处只兜底「camel 名恰与 extra 族同名」。 */
function isExtraRepresented(tpl: string, root: string): boolean {
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(path.join(root, "scripts", "gen_demo_algorithms", "extra"), {
      withFileTypes: true,
    });
  } catch {
    return false;
  }
  for (const e of entries) {
    const n = e.name.replace(/\.c$/, "");
    if (camel(n) === tpl) return true;
  }
  return false;
}

function tplTagFor(root: string, algo: string, tplByAlgo: Map<string, string>): string {
  const ex = extraSrcFor(root, algo);
  if (ex.ok && ex.src !== "") return "extra";
  return tplByAlgo.get(algo) ?? "";
}

function loadTplSource(root: string, tpl: string): string {
  const p = path.join(root, "templates", tpl, "source.c");
  let sb: string;
  try {
    sb = fs.readFileSync(p, "utf8");
  } catch (e) {
    return die(`模板 ${tpl} source.c: ${(e as Error).message}`);
  }
  if (sb.trim() === "") die(`模板 ${tpl} source.c 为空`);
  return sb;
}

function loadAlgoSource(root: string, algo: string, tplByAlgo: Map<string, string>): string {
  const ex = extraSrcFor(root, algo);
  if (ex.ok && ex.src !== "") return ex.src;
  const tpl = tplByAlgo.get(algo) ?? "";
  if (tpl === "") {
    die(`族 ${algo} 在 golden 无代表模板（对拍面缺口——rules.json 与 golden 漂移？）`);
  }
  return loadTplSource(root, tpl);
}

/** 从 cwd 向上找仓库根（templates/ + moonbit/moon.mod）。 */
function findRoot(): string {
  let root = process.cwd();
  for (;;) {
    const hasTpls = fs.existsSync(path.join(root, "templates"));
    const hasMod = fs.existsSync(path.join(root, "moonbit", "moon.mod"));
    if (hasTpls && hasMod) return root;
    const parent = path.dirname(root);
    if (parent === root) die("找不到仓库根（templates/ + moonbit/moon.mod）");
    root = parent;
  }
}

function main(): void {
  const root = findRoot();
  const g = (p: string): string => path.join(root, p);

  // ① rules.json 43 族全集
  const rulesRaw = readText(g("scripts/teaching_annotation_diff/rules.json"), "rules.json");
  let rl: RulesFile;
  try {
    rl = JSON.parse(rulesRaw) as RulesFile;
  } catch (e) {
    return die(`rules.json 坏 JSON: ${(e as Error).message}`);
  }
  if (!Array.isArray(rl.migrated_algorithms) || rl.migrated_algorithms.length === 0) {
    die("rules.json migrated_algorithms 为空");
  }
  const migrated = new Set(rl.migrated_algorithms);

  // ② golden：模板→族 + display_name
  const goldenRaw = readText(
    g("scripts/teaching_annotation_diff/golden/algorithm_annotations_v3.json"),
    "golden",
  );
  let golden: Record<string, GoldenEntry[]>;
  try {
    golden = JSON.parse(goldenRaw) as Record<string, GoldenEntry[]>;
  } catch (e) {
    return die(`golden 坏 JSON: ${(e as Error).message}`);
  }
  const tplByAlgo = new Map<string, string>();
  const nameByAlgo = new Map<string, string>();
  const tpls = sortBytes(Object.keys(golden)); // 稳定序：同族多模板取字典序首
  for (const tpl of tpls) {
    for (const e of golden[tpl] ?? []) {
      if (e.algorithm === "") continue;
      if (!tplByAlgo.has(e.algorithm)) tplByAlgo.set(e.algorithm, tpl);
      if (!nameByAlgo.has(e.algorithm) && e.display_name !== "") {
        nameByAlgo.set(e.algorithm, e.display_name);
      }
    }
  }

  // ③ 中文名兜底：引擎判据源 detect_*.mbt 的 build_match（Go Glob 返回排序结果，
  // 首次命中优先——TS 侧显式补排序，否则「谁先谁赢」口径漂移）
  let detectFiles: string[];
  try {
    detectFiles = sortBytes(
      fs
        .readdirSync(g("moonbit/teaching/steps"))
        .filter((n) => /^detect.*\.mbt$/.test(n))
        .map((n) => g(path.join("moonbit/teaching/steps", n))),
    );
  } catch (e) {
    return die(`detect_*.mbt 不可读: ${(e as Error).message}`);
  }
  if (detectFiles.length === 0) die("detect_*.mbt 不可读: 零命中");
  for (const df of detectFiles) {
    const db = readText(df, `读 ${df}`);
    for (const m of db.matchAll(BUILD_MATCH_RE)) {
      const algo = m[1] ?? "";
      const cn = m[2] ?? "";
      if (!nameByAlgo.has(algo)) nameByAlgo.set(algo, cn);
    }
  }

  // 完备性断言一：分组并集 == rules.json 族集合
  const coverageErrs = groupCoverageErrors(migrated);
  if (coverageErrs.length > 0) die(coverageErrs[0] ?? "分组表漂移");

  // ── 模板全量纳入（2026-10-04 拍板「资源放着浪费」：82 个 .c 模板全进侧栏；
  // cpp_ 前缀 6 个不进——source.cpp 无 source.c 自然出局 + F-2 已裁砍 C++）。
  // 三桶归类：① golden 有条目 → 按族归（字典序首为代表，其余变体）；
  //          ② camel 名精确匹配族名 → 归该族变体；③ 其余 → 扩展练习组平铺。
  const templates = new Map<string, string[]>();
  for (const tpl of tpls) {
    for (const e of golden[tpl] ?? []) {
      if (e.algorithm !== "" && migrated.has(e.algorithm)) {
        templates.set(
          e.algorithm,
          appendUnique(templates.get(e.algorithm) ?? [], tpl),
        );
      }
    }
  }
  const consumedTpls = new Set<string>();
  for (const list of templates.values()) for (const t of list) consumedTpls.add(t);

  let allTpls: string[] = [];
  for (const e of listDir(g("templates"), "templates/ 不可读")) {
    if (e.isDirectory() && fs.existsSync(g(path.join("templates", e.name, "source.c")))) {
      allTpls.push(e.name);
    }
  }
  sortBytes(allTpls);
  for (const a of rl.migrated_algorithms) {
    const c = camel(a);
    // Windows 文件系统大小写不敏感——camel 名须经 allTpls 精确匹配取目录真名
    //（kruskalMst 幽灵命中 kruskalMST 实锤），否则 Set 对账多算。
    const real = allTpls.find((t) => t.toLowerCase() === c.toLowerCase()) ?? "";
    if (real !== "" && !consumedTpls.has(real)) {
      templates.set(a, appendUnique(templates.get(a) ?? [], real));
      consumedTpls.add(real);
    }
  }
  const xlab: string[] = [];
  for (const t of allTpls) {
    if (!consumedTpls.has(t) && !isExtraRepresented(t, root)) xlab.push(t);
  }

  // 全集对账（Set 语义——跨族归属的模板只算一次）
  const setUnion = new Set<string>(consumedTpls);
  for (const t of xlab) setUnion.add(t);
  if (setUnion.size !== allTpls.length) {
    const ghost = sortBytes([...setUnion].filter((t) => !allTpls.includes(t)));
    const missed = sortBytes(allTpls.filter((t) => !setUnion.has(t)));
    die(
      `模板全集对账失败：消耗+扩展=${setUnion.size} != templates/*.c=${allTpls.length}（幽灵=[${ghost.join(" ")}] / 漏归=[${missed.join(" ")}]）`,
    );
  }

  // ── 发射 ────────────────────────────────────────────────────────────────
  const b: string[] = [];
  b.push("// @generated by scripts/gen_demo_algorithms — 勿手改（产物不入库：CI/pages 现场发射）\n");
  b.push("// 43 算法族 = teaching/steps 全集（rules.json 机判）；中文名 = golden display_name\n");
  b.push("// + detect_*.mbt build_match 提取；示例源码 = templates/ 代表（golden 首现）\n");
  b.push("// + extra/ 覆盖源；同族其余模板 = variants；未归类模板 = 扩展练习组\n");
  b.push("//（2026-10-04，refs #28 + 用户拍板全量纳入：82 个 .c 模板全覆盖——\n");
  b.push("// cpp_ 前缀不进，F-2 已裁砍 C++，class/template 编译必败）。\n");
  b.push('"use strict";\n\n');
  b.push("// 分组 × 族清单；source = 可直接载入编辑器的判据命中示例；\n");
  b.push("// variants = 同族其它模板（点击切换示例形态）；xlab = 扩展练习。\n");
  b.push("const DEMO_ALGORITHMS = {\n  groups: [\n");
  for (const grp of GROUPS) {
    b.push(`    { id: ${goQuote(grp.id)}, label: ${goQuote(grp.label)}, items: [\n`);
    for (const a of grp.algos) {
      const name = nameByAlgo.get(a) ?? "";
      if (name === "") die(`族 ${a} 无 display_name（golden 首现条目缺中文名）`);
      // 变体 = 该族模板列表 - 代表（extra 族代表为 extra 源，golden 模板全作变体）
      let variants: string[];
      if (extraSrcFor(root, a).ok) {
        variants = templates.get(a) ?? [];
      } else {
        const tlist = templates.get(a) ?? [];
        variants = tlist.length > 1 ? tlist.slice(1) : [];
      }
      b.push(
        `      { id: ${goQuote(a)}, name: ${goQuote(name)}, template: ${goQuote(
          tplTagFor(root, a, tplByAlgo),
        )}, source: \`${jsBacktick(loadAlgoSource(root, a, tplByAlgo))}\`, variants: [`,
      );
      variants.forEach((v, i) => {
        if (i > 0) b.push(", ");
        b.push(`\n        { tpl: ${goQuote(v)}, source: \`${jsBacktick(loadTplSource(root, v))}\` }`);
      });
      b.push(variants.length > 0 ? "\n      ] },\n" : "] },\n");
    }
    b.push("    ] },\n");
  }
  b.push('    { id: "xlab", label: "扩展练习", xitems: [\n');
  for (const t of xlab) {
    b.push(
      `      { id: ${goQuote(t)}, name: ${goQuote(t)}, source: \`${jsBacktick(loadTplSource(root, t))}\` },\n`,
    );
  }
  b.push("    ] },\n");
  b.push("  ],\n};\n");

  const outPath = g(path.join("demo", "algorithms.js"));
  try {
    fs.writeFileSync(outPath, b.join(""), { mode: 0o644 });
  } catch (e) {
    return die(`写 ${outPath}: ${(e as Error).message}`);
  }
  process.stdout.write(
    `gen_demo_algorithms: 生成 ${outPath}（${migrated.size} 族 × ${GROUPS.length} 组）\n`,
  );
}

// 入口守卫：被 node:test import 时只取纯函数，不落盘
if (
  process.argv[1] !== undefined &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
) {
  main();
}
