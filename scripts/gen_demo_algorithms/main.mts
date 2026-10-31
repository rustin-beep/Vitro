#!/usr/bin/env node
// gen_demo_algorithms.mts —— demo「算法可视化」侧栏数据生成器（#273 存量 Go
// 重写批；原 go scripts/gen_demo_algorithms，2026-10-04，refs #28）。
//
// 输入（全部机判真值源，禁手画——侧栏列表 = 渲染产物）：
//
//   ① 引擎 algorithms.catalog 出口（#36 收编批 2026-10-31 起）——43 族全集 /
//      display_name 中文名 / 七组分组全部单源自引擎（vitro_js api --batch 拉取；
//      判据源码即数据源，天然零漂移）
//   ② scripts/teaching_annotation_diff/rules.json → 引擎↔rules 双向对账锚
//      （rules 仍是 teaching 43 族权威——teaching_annotation_diff 闸输入地位不变）
//   ③ scripts/teaching_annotation_diff/golden/algorithm_annotations_v3.json →
//      模板→族映射（display_name 消费已随 #36 退役，引擎出口承担）
//   ④ templates/<tpl>/source.c → 每族代表示例源码（内容资产非引擎逻辑，不进 wasm）
//
// 输出：demo/algorithms.js（浏览器脚本形态，同 cases.js：全局 const 无导出）——
//
//   DEMO_ALGORITHMS = { groups: [{ id, label, items: [{ id, name, source }] }] }
//
// 完备性断言（漂移即红）：引擎出口自洽（display_name 非空/分组引用/无重复）+
// 引擎↔rules.json 43 族双向一致；每族须有代表模板（golden 首现）与非空
// source.c；模板三桶对账 == templates 全集。
//
// 产物不入库（2026-10-04 发射化）：ci.yml 与 pages.yml 消费前现场发射，发射即
// 检查闸（断言失败即红）。.gitignore 有 demo/algorithms.js。
//
// 用法：node scripts/gen_demo_algorithms/main.mts
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import { goQuote, sortBytes } from "../internal/gofmt.mts";
import { makeFail } from "../internal/genio.mts";
import { ensureFresh } from "../internal/freshness.mts";

/** 呈现层分组形态（#36 收编批 2026-10-31 起由引擎 catalog 派生，硬编码退役）。 */
export interface Group {
  id: string;
  label: string;
  algos: string[];
}

/** 引擎 algorithms.catalog 出口帧（steps catalog emitter 单源——判据源码即数据源）。 */
export interface CatalogAlgo {
  family: string;
  display_name: string;
  group: string;
  vis_events: boolean;
}
export interface CatalogExport {
  schema: string;
  total: number;
  groups: Array<{ id: string; label: string }>;
  algorithms: CatalogAlgo[];
}

/** vitro_js.js 产物路径（js 臂统一入口——CI build-products artifact 含此件）。 */
const VITRO_JS = ["_build", "js", "release", "build", "cmd", "vitro_js", "vitro_js.js"].join(path.sep);

/**
 * catalog 拉取产物路径（测试 prereq guard 用：缺产物显式 skip 而非
 * `process.exit(1)` 吞掉同文件其余锚——PR #403 审阅 P1-1，干净检出
 * `npm test` 必红的根因；真拉取端到端锚保留给有产物的环境）。
 */
export function catalogArtifactPath(root: string): string {
  return path.join(root, "moonbit", VITRO_JS);
}

/**
 * 拉取引擎 algorithms.catalog 出口（#36：族集/display_name/分组三源收编——
 * 此前 rules.json 族集 + golden display_name + detect_*.mbt 兜底 + GROUPS
 * 硬编码四源拼装）。ensureFresh 前置（mtime 触发 + moon 内容 hash 复核）——
 * 陈旧产物假红/假绿由此封死（陷阱 41）。
 */
export function fetchCatalog(root: string): CatalogExport {
  const artifact = catalogArtifactPath(root);
  ensureFresh("gen_demo_algorithms", artifact, [
    "build",
    "--release",
    "--target",
    "js",
    "cmd/vitro_js",
  ]);
  const r = spawnSync(process.execPath, [artifact, "api", "--batch"], {
    input: '{"id":1,"method":"algorithms.catalog"}',
    encoding: "utf8",
  });
  if (r.status !== 0 || r.stdout === undefined || r.stdout === "") {
    die(`algorithms.catalog 拉取失败（vitro_js api --batch exit ${r.status}）：${(r.stderr ?? "").slice(0, 300)}`);
  }
  let frame: { ok?: boolean; result?: CatalogExport };
  try {
    frame = JSON.parse(r.stdout.split("\n", 1)[0] ?? "") as { ok?: boolean; result?: CatalogExport };
  } catch (e) {
    return die(`algorithms.catalog 响应非 JSON: ${(e as Error).message}`);
  }
  if (frame.ok !== true || frame.result === undefined) {
    die("algorithms.catalog 响应帧 ok:false / 缺 result");
  }
  const cat = frame.result;
  if (cat.schema !== "algorithms.catalog/1") {
    die(`algorithms.catalog schema 不识别: ${cat.schema}`);
  }
  if (!Array.isArray(cat.algorithms) || cat.algorithms.length === 0) {
    die("algorithms.catalog algorithms 为空");
  }
  return cat;
}

/**
 * 引擎分组派生（组序 = 引擎 groups 序；组内序 = 引擎 catalog 序——
 * #36 起侧栏呈现序即引擎目录序，呈现层不再自带排序真相）。
 */
export function deriveGroups(cat: CatalogExport): Group[] {
  return cat.groups.map((g) => ({
    id: g.id,
    label: g.label,
    algos: cat.algorithms.filter((a) => a.group === g.id).map((a) => a.family),
  }));
}

/**
 * 引擎出口自洽 + 引擎↔rules.json 双向对账（错误清单，供 node:test 注入证红）：
 *   ① display_name 非空 ② group 引用落在 groups ③ 无同族重复
 *   ④ 引擎族集 ↔ rules migrated 集双向一致（rules 仍是 teaching 43 族权威——
 *      teaching_annotation_diff 闸输入地位不变，此处是过渡期互证锚）
 */
export function catalogConsistencyErrors(cat: CatalogExport, migrated: Set<string>): string[] {
  const errs: string[] = [];
  const groupIds = new Set(cat.groups.map((g) => g.id));
  const seen = new Set<string>();
  const fams = new Set<string>();
  for (const a of cat.algorithms) {
    if (a.display_name === "") errs.push(`族 ${a.family} display_name 为空`);
    if (!groupIds.has(a.group)) errs.push(`族 ${a.family} 引用未知分组 "${a.group}"`);
    if (seen.has(a.family)) errs.push(`族 ${a.family} 重复登记`);
    seen.add(a.family);
    fams.add(a.family);
  }
  const rulesOnly = sortBytes([...migrated].filter((x) => !fams.has(x)));
  const engOnly = sortBytes([...fams].filter((x) => !migrated.has(x)));
  if (rulesOnly.length > 0 || engOnly.length > 0) {
    errs.push(
      `族集漂移：rules.json 有而引擎无 [${rulesOnly.join(" ")}]；引擎有而 rules.json 无 [${engOnly.join(" ")}]`,
    );
  }
  return errs;
}

interface GoldenEntry {
  algorithm: string;
  display_name: string;
}
interface RulesFile {
  migrated_algorithms: string[];
}

const PARAM_MARK_RE = /\/\*__PARAM_[a-z_0-9]+__\*\//g;

function die(msg: string): never {
  return makeFail("gen_demo_algorithms: ", 1)(msg);
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

  // ① 引擎 algorithms.catalog 出口（#36 收编：族集/display_name/分组三源单点）
  const cat = fetchCatalog(root);

  // ② rules.json——teaching 43 族权威（teaching_annotation_diff 闸输入地位不变），
  // 此处降为引擎↔rules 双向对账参照（漂移任一侧即红）
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

  // 完备性断言一：引擎出口自洽 + 引擎↔rules 族集双向一致
  const coverageErrs = catalogConsistencyErrors(cat, migrated);
  if (coverageErrs.length > 0) die(coverageErrs[0] ?? "引擎 catalog 对账失败");

  // 引擎派生：中文名（display_name）与七组分组（组内序 = 引擎 catalog 序）
  const GROUPS = deriveGroups(cat);
  const nameByAlgo = new Map<string, string>(
    cat.algorithms.map((a) => [a.family, a.display_name] as const),
  );

  // ③ golden：模板→族映射（#36 起 display_name 消费退役——引擎出口承担）
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
  const tpls = sortBytes(Object.keys(golden)); // 稳定序：同族多模板取字典序首
  for (const tpl of tpls) {
    for (const e of golden[tpl] ?? []) {
      if (e.algorithm === "") continue;
      if (!tplByAlgo.has(e.algorithm)) tplByAlgo.set(e.algorithm, tpl);
    }
  }

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
  b.push("// 43 算法族/中文名/七组分组 = 引擎 algorithms.catalog 出口单源（#36 收编，\n");
  b.push("// 2026-10-31）；引擎↔rules.json 双向对账；示例源码 = templates/ 代表\n");
  b.push("//（golden 首现）+ extra/ 覆盖源；同族其余模板 = variants；未归类模板 = 扩展\n");
  b.push("// 练习组（2026-10-04，refs #28 + 用户拍板全量纳入：82 个 .c 模板全覆盖——\n");
  b.push("// cpp_ 前缀不进，F-2 已裁砍 C++，class/template 编译必败）。组内呈现序 =\n");
  b.push("// 引擎 catalog 序（#36 起呈现层不再自带排序真相）。\n");
  b.push('"use strict";\n\n');
  b.push("// 分组 × 族清单；source = 可直接载入编辑器的判据命中示例；\n");
  b.push("// variants = 同族其它模板（点击切换示例形态）；xlab = 扩展练习。\n");
  b.push("const DEMO_ALGORITHMS = {\n  groups: [\n");
  for (const grp of GROUPS) {
    b.push(`    { id: ${goQuote(grp.id)}, label: ${goQuote(grp.label)}, items: [\n`);
    for (const a of grp.algos) {
      const name = nameByAlgo.get(a) ?? "";
      if (name === "") die(`族 ${a} 无 display_name（引擎 catalog——上游对账已断言非空，此处死防御）`);
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
