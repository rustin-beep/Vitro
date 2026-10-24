// catalog.mts —— teaching_annotation_diff 的 --catalog-check / --catalog-selftest 实现
// （Go→.mts 重写，refs #273；原 catalog_check.go 414 行 / #36 2026-10-16）。
//
// 引擎 algorithms.catalog 导出的三方对账闸：
//
//   A. 判据源码提取物：detect_*.mbt 的 build_match 调用（括号平衡扫描，
//      family/display_name/第 5 参是否恒空 []）
//   B. 引擎导出：`vitro api algorithms.catalog` 双臂（native exe + js 直编
//      壳）——两臂先互拍一致（纪律 14 最小面：两臂都是单源壳直连引擎）
//   C. rules.json migrated_algorithms（43 族全集）
//   D. gen_demo_algorithms 呈现层分组表（id/label/组内族集）
//
// 断言：A↔B 逐条（display_name + vis_events 位）；B.family 集 == C 集；
// B.groups == D 的 id/label 且 B 条目 group 归属 == D 组内成员（双向）。
//
// J9 义务：--catalog-selftest 内存注入四路证红（display_name 篡改 / rules 缺键 /
// demo 幽灵族 / demo 归属分叉）——不落盘。
//
// 口径差异（有意）：Go 版双臂互拍用 `fmt.Sprint(struct)` 比对，本版改
// `JSON.stringify` 深比较——语义等价且更强（结构体打印会把零值省略差异藏进
// 格式里）。其余判定与文案逐字保留。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { ensureFresh } from "../internal/freshness.mts";

export interface CatalogEntry {
  family: string;
  display_name: string;
  group: string;
  vis_events: boolean;
}

export interface CatalogGroup {
  id: string;
  label: string;
}

export interface CatalogExport {
  schema: string;
  total: number;
  groups: CatalogGroup[];
  algorithms: CatalogEntry[];
}

/** 判据源码提取物（A）。 */
export interface BuildMatchSource {
  family: string;
  displayName: string;
  /** 第 5 参非恒空 [] */
  visEvents: boolean;
}

export interface DemoGroup {
  id: string;
  label: string;
  algos: string[];
}

export interface Rules {
  as_of: string;
  migrated_algorithms: string[];
  step_budget: number;
  exemptions: unknown[];
}

const DETECT_FILES = [
  "detect.mbt",
  "detect_search.mbt",
  "detect_graph.mbt",
  "detect_tree.mbt",
  "detect_structures.mbt",
  "detect_math.mbt",
];

function firstN(s: string, n: number): string {
  const chars = Array.from(s);
  return chars.length > n ? chars.slice(0, n).join("") : s;
}

/** 读规则文件（catalog 与主路径共用，故落在此处由 main.mts import）。 */
export function loadRules(rulesPath: string): Rules {
  let raw: string;
  try {
    raw = fs.readFileSync(rulesPath, "utf8");
  } catch (e) {
    throw new Error(`读取规则失败 ${rulesPath}: ${e instanceof Error ? e.message : String(e)}`);
  }
  let r: Rules;
  try {
    r = JSON.parse(raw) as Rules;
  } catch (e) {
    throw new Error(`规则 JSON 解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (!Array.isArray(r.migrated_algorithms) || r.migrated_algorithms.length === 0) {
    throw new Error("migrated_algorithms 为空（禁静默全比对）");
  }
  if (!(r.step_budget > 0)) throw new Error("step_budget 缺失或非正（Rust 口径 4000）");
  for (const e of r.exemptions ?? []) {
    const ex = e as { kind?: string; template?: string; reason?: string };
    if (ex.kind !== "missing" && ex.kind !== "extra" && ex.kind !== "diff") {
      throw new Error(`豁免 kind 非法: "${ex.kind}"（须 missing|extra|diff）`);
    }
    if (!ex.template || !ex.reason) throw new Error(`豁免条目缺 template/reason: ${JSON.stringify(ex)}`);
  }
  return r;
}

/**
 * extractBuildMatches：括号平衡扫描 build_match 调用块，取前两个字符串参数与
 * 最后一个参数（第 5 参）。
 */
export function extractBuildMatches(stepsDir: string): BuildMatchSource[] {
  const out: BuildMatchSource[] = [];
  for (const f of DETECT_FILES) {
    let text: string;
    try {
      text = fs.readFileSync(path.join(stepsDir, f), "utf8");
    } catch (e) {
      throw new Error(`读取判据源码失败 ${f}: ${e instanceof Error ? e.message : String(e)}`);
    }
    let idx = 0;
    for (;;) {
      const rel = text.indexOf("build_match(", idx);
      if (rel < 0) break;
      const pos = rel;
      let j = pos + "build_match(".length;
      let depth = 1;
      while (depth > 0 && j < text.length) {
        const c = text[j];
        if (c === "(") depth++;
        else if (c === ")") depth--;
        j++;
      }
      if (depth !== 0) throw new Error(`build_match 调用块未闭合：${f}`);
      const block = text.slice(pos, j);
      const inner = block.slice(block.indexOf("(") + 1, block.lastIndexOf(")"));
      // 逐参切分（顶层逗号——字符串字面量内逗号不算）
      const params: string[] = [];
      let cur = "";
      let inStr = false;
      for (const c of inner) {
        if (c === '"') {
          inStr = !inStr;
          cur += c;
          continue;
        }
        if (c === "," && !inStr) {
          params.push(cur.trim());
          cur = "";
          continue;
        }
        cur += c;
      }
      params.push(cur.trim());
      // 尾逗号后的空白残参丢弃（moon fmt 多行形态）
      const kept = params.filter((p) => p !== "");
      let use = kept;
      if (use.length !== 5) {
        // #224：evidence~ 具名参数（第 6 参，name/structure 判别依据）合法附加
        if (use.length === 6 && (use[5] ?? "").startsWith("evidence=")) use = use.slice(0, 5);
        else {
          throw new Error(`build_match 参数数 ${use.length} ≠ 5（第 6 参仅允许 evidence=）：${f} 内 "${firstN(inner, 60)}"`);
        }
      }
      const fam = (use[0] ?? "").replace(/^"|"$/g, "");
      const disp = (use[1] ?? "").replace(/^"|"$/g, "");
      const vis = (use[4] ?? "").trim() !== "[]";
      out.push({ family: fam, displayName: disp, visEvents: vis });
      idx = j;
    }
  }
  return out;
}

function exeName(): string {
  return process.platform === "win32" ? "vitro.exe" : "vitro";
}

/** 跑 `api algorithms.catalog {}` 并解析响应帧 result。 */
export function fetchCatalog(name: string, argv: string[]): CatalogExport {
  const r = spawnSync(name, [...argv, "api", "algorithms.catalog", "{}"], { encoding: "utf8" });
  if (r.error !== undefined || r.status !== 0) {
    const why = r.error?.message ?? `exit ${r.status}`;
    throw new Error(`${name} 执行失败: ${why}\nstderr: ${firstN(r.stderr ?? "", 200)}`);
  }
  const stdout = r.stdout ?? "";
  let frame: { ok?: boolean; result?: CatalogExport };
  try {
    frame = JSON.parse(stdout) as typeof frame;
  } catch (e) {
    throw new Error(`响应帧解析失败（${name}）: ${e instanceof Error ? e.message : String(e)}\nstdout: ${firstN(stdout, 200)}`);
  }
  if (frame.ok !== true) throw new Error(`响应帧 ok=false（${name}）`);
  return frame.result as CatalogExport;
}

/** 三方对账（返回全部红项——fail loud 但一次性报全）。 */
export function compareCatalogs(
  a: BuildMatchSource[],
  b: CatalogExport,
  migrated: Set<string>,
  demoGroups: DemoGroup[],
): string[] {
  const errs: string[] = [];
  if (a.length !== b.algorithms.length) {
    errs.push(`条数：判据提取物 ${a.length} ≠ 引擎导出 ${b.algorithms.length}`);
  }
  const byFamily = new Map<string, CatalogEntry>();
  for (const e of b.algorithms) byFamily.set(e.family, e);
  for (const s of a) {
    const e = byFamily.get(s.family);
    if (e === undefined) {
      errs.push(`判据族 "${s.family}" 不在引擎导出`);
      continue;
    }
    if (e.display_name !== s.displayName) {
      errs.push(`${s.family} display_name：判据 "${s.displayName}" ≠ 引擎 "${e.display_name}"`);
    }
    if (e.vis_events !== s.visEvents) {
      errs.push(`${s.family} vis_events：判据第 5 参恒空=${!s.visEvents} ≠ 引擎 ${e.vis_events}`);
    }
  }
  // C：rules.json migrated_algorithms 集
  if (migrated.size !== b.algorithms.length) {
    errs.push(`族数：rules.json ${migrated.size} ≠ 引擎导出 ${b.algorithms.length}`);
  }
  for (const fam of migrated) {
    if (!byFamily.has(fam)) errs.push(`rules.json 族 "${fam}" 不在引擎导出`);
  }
  // D：gen_demo_algorithms 分组表
  if (demoGroups.length !== b.groups.length) {
    errs.push(`分组数：demo 生成器 ${demoGroups.length} ≠ 引擎导出 ${b.groups.length}`);
  }
  const demoByID = new Map<string, DemoGroup>();
  for (const g of demoGroups) demoByID.set(g.id, g);
  for (const g of b.groups) {
    const d = demoByID.get(g.id);
    if (d === undefined) {
      errs.push(`引擎分组 "${g.id}" 不在 demo 生成器表`);
      continue;
    }
    if (d.label !== g.label) errs.push(`分组 "${g.id}" label：demo "${d.label}" ≠ 引擎 "${g.label}"`);
    const want = new Set(d.algos);
    for (const e of b.algorithms) {
      if (e.group === g.id && !want.has(e.family)) {
        errs.push(`族 "${e.family}" 引擎归组 "${g.id}" ≠ demo 生成器归属`);
      }
    }
  }
  // D 反向（2026-10-17 审阅 P3-⑧）：demo 生成器表多列的族（幽灵 / 归属分叉）
  const engineGroupByFamily = new Map<string, string>();
  for (const e of b.algorithms) engineGroupByFamily.set(e.family, e.group);
  for (const g of demoGroups) {
    for (const f of g.algos) {
      const eg = engineGroupByFamily.get(f);
      if (eg === undefined) {
        errs.push(`demo 生成器组 "${g.id}" 列族 "${f}" 不在引擎导出（僵尸/拼写）`);
        continue;
      }
      if (eg !== g.id) errs.push(`demo 生成器组 "${g.id}" 列族 "${f}" 引擎归组为 "${eg}"（归属分叉）`);
    }
  }
  return errs;
}

/** 正则提取 gen_demo_algorithms 的 groups var（Go 版真源仍是 main.go）。 */
export function extractDemoGroups(p: string): DemoGroup[] {
  let text: string;
  try {
    text = fs.readFileSync(p, "utf8");
  } catch (e) {
    throw new Error(`${p}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const start = text.indexOf("var groups = ");
  if (start < 0) throw new Error("gen_demo_algorithms 未找到 groups var");
  // []struct {...}{ 字面量起始——从字面量段起扫描，避免类型声明结尾的 \n}{ 提前截断
  let body = text.slice(start);
  const braceOpen = body.indexOf("}{");
  if (braceOpen < 0) throw new Error("groups 字面量起始 }{ 未找到");
  body = body.slice(braceOpen + 1);
  const end = body.indexOf("\n}");
  if (end < 0) throw new Error("groups 字面量未闭合");
  const block = body.slice(0, end);
  const re = /\{"([a-z]+)", "([^"]+)", \[\]string\{([^}]*)\}\}/g;
  const out: DemoGroup[] = [];
  for (const m of block.matchAll(re)) {
    const algos: string[] = [];
    for (const a of (m[3] ?? "").split(",")) {
      // 先 trim 再剥引号——顺序反了前导空格会挡住引号剥除（Go 版注释同款）
      const t = a.trim().replace(/^"|"$/g, "");
      if (t !== "") algos.push(t);
    }
    out.push({ id: m[1] ?? "", label: m[2] ?? "", algos });
  }
  if (out.length === 0) throw new Error("groups 提取零条（正则失配？）");
  return out;
}

/** --catalog-check 主流程（双臂 + 三方）。返回 exit 码，错误消息由调用方打印。 */
export function runCatalogCheck(root: string, selftest: boolean): { code: number; error?: string } {
  try {
    const stepsDir = path.join(root, "moonbit", "teaching", "steps");
    const a = extractBuildMatches(stepsDir);

    // B：双臂拉取（native release vitro.exe + js release vitro_js.js）
    const vitroExe = path.join(root, "moonbit", "_build", "native", "release", "build", "cmd", "vitro", exeName());
    ensureFresh("catalog_check_native", vitroExe, ["build", "--release", "--target", "native", "cmd/vitro"]);
    const jsEntry = path.join(root, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_js", "vitro_js.js");
    ensureFresh("catalog_check_js", jsEntry, ["build", "--release", "--target", "js", "cmd/vitro_js"]);

    const bNative = fetchCatalog(vitroExe, []);
    const bJs = fetchCatalog("node", [jsEntry]);
    // 双臂互拍（Go 版用 fmt.Sprint；本版 JSON 深比较，更强）
    const n = JSON.stringify(bNative);
    const j = JSON.stringify(bJs);
    if (n !== j) throw new Error(`双臂导出不一致：\nnative: ${firstN(n, 300)}\njs:     ${firstN(j, 300)}`);

    // C：rules.json migrated 集
    const rules = loadRules(path.join(root, "scripts", "teaching_annotation_diff", "rules.json"));
    const migrated = new Set(rules.migrated_algorithms);

    // D：gen_demo_algorithms 分组表
    const demoGroups = extractDemoGroups(path.join(root, "scripts", "gen_demo_algorithms", "main.go"));

    const errs = compareCatalogs(a, bNative, migrated, demoGroups);
    if (selftest) {
      // J9 四路内存注入证红（路 3/4 = 2026-10-17 审阅 P3-⑧ 补：D 反向双形态）
      const spoiled = a.map((x) => ({ ...x }));
      spoiled[0]!.displayName = "篡改名";
      if (compareCatalogs(spoiled, bNative, migrated, demoGroups).length === 0) {
        throw new Error("selftest：display_name 篡改未红（锚无牙）");
      }
      const dropOne = new Set(migrated);
      for (const k of dropOne) {
        dropOne.delete(k);
        break;
      }
      if (compareCatalogs(a, bNative, dropOne, demoGroups).length === 0) {
        throw new Error("selftest：rules 缺键未红（锚无牙）");
      }
      const ghost = demoGroups.map((g) => ({ ...g, algos: [...g.algos] }));
      ghost[0]!.algos.push("phantom_family_zz");
      if (compareCatalogs(a, bNative, migrated, ghost).length === 0) {
        throw new Error("selftest：demo 幽灵族未红（D 反向无牙）");
      }
      const misfile = demoGroups.map((g) => ({ ...g, algos: [...g.algos] }));
      if (misfile.length < 2 || misfile[0]!.algos.length === 0) {
        throw new Error("selftest：分组表形态不足（<2 组或空组）——注入前提缺失");
      }
      misfile[1]!.algos.push(misfile[0]!.algos[0]!);
      if (compareCatalogs(a, bNative, migrated, misfile).length === 0) {
        throw new Error("selftest：demo 归属分叉未红（D 反向无牙）");
      }
      process.stdout.write("teaching_annotation_diff --catalog-check selftest: 四路注入均红（锚有牙）\n");
      return { code: 0 };
    }
    if (errs.length > 0) {
      process.stdout.write("teaching_annotation_diff --catalog-check 红：\n");
      for (const e of [...errs].sort((x, y) => Buffer.compare(Buffer.from(x), Buffer.from(y)))) {
        process.stdout.write("  - " + e + "\n");
      }
      process.exit(1);
    }
    process.stdout.write(
      `teaching_annotation_diff --catalog-check 绿（判据 ${a.length} 条 ↔ 双臂导出一致 ↔ rules 43 ↔ demo 分组表）\n`,
    );
    return { code: 0 };
  } catch (e) {
    return { code: 2, error: e instanceof Error ? e.message : String(e) };
  }
}
