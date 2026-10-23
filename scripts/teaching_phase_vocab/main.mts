#!/usr/bin/env node
// teaching_phase_vocab：#51 批① phase 受控词表冻结闸（Go→.mts 重写，refs #273）。
//
// 原 Go 版（scripts/teaching_phase_vocab/main.go，281 行）语义逐条保留——
// 本文件只换实现载体，判定面、文案、退出码不变。
//
// teaching/steps/infer_*.mbt 的 `build_step(algorithm, "phase", "文案")`
// 第二参 phase 是算法过程语义的受控词表（#51：70+ 自由串无契约——
// 「该契约化的没契约」）。本闸对齐 semantic_label 纪律：词表只增不改、
// 漂移即红。四路判红：
//
//   ①未登记扩张：代码出现 rules.json 未登记的 phase；
//   ②僵尸条目：rules.json 条目代码零命中；
//   ③family 漂移：phase 的使用函数集（infer_* 家族）与登记集双向不等；
//   ④非字面量调用：`build_step(` 出现次数 > 字面量命中数（插值/变量
//     作 phase —— 词表闸的抽取面直接失明）。
//
// 另有抽取面下限（total < min_call_sites 红——正则失能防护：规则改坏时
// 命中塌缩不会静默绿）。`-selftest` 内存注入四路证红（J9），不落盘。
//
// 用法（仓库根）：
//   node scripts/teaching_phase_vocab/main.mts           # 对账（CI 形态）
//   node scripts/teaching_phase_vocab/main.mts -selftest # 四路注入证红
//
// 口径差异（有意，均已实测）：Go 版「未登记扩张」按 map 迭代序输出（随机），
// 本版排序输出——红路径的可复现性提升，绿路径文案逐字一致。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export const STEPS_DIR = "moonbit/teaching/steps";
export const RULES_PATH = "scripts/teaching_phase_vocab/rules.json";

export interface Entry {
  phase: string;
  families: string[];
}

export interface Rules {
  schema: number;
  min_call_sites: number;
  phases: Entry[];
}

/** 一次 build_step 调用的抽取产物（字面量形态）。 */
export interface Call {
  phase: string;
  family: string;
  file: string;
}

// 抽取面：与 Go 版逐字符同一正则（`(?s)` = dotAll；`(?m)` = 多行）。
// 每次使用都新建实例——带 g 的正则复用会污染 lastIndex。
function callRe(): RegExp {
  return /build_step\(\s*[A-Za-z_][\w.]*\s*,\s*"([a-z_0-9]+)"\s*,/gs;
}
function fnRe(): RegExp {
  return /^fn (infer_\w+)\(/gm;
}

/**
 * 扫 infer_*.mbt。返回字面量命中与 `build_step(` 总出现数
 * （两者差 = 非字面量调用数）。family = 调用点所在的最近 infer_* 函数
 * （词表漂移按函数粒度归因——函数即判据族）。
 *
 * 读取序显式排序：Go 的 os.ReadDir 保证文件名字典序，Node 的 readdirSync
 * 不保证——不排序会让 calls 顺序随文件系统漂移（红路径输出不可复现）。
 */
export function extract(dir: string): { calls: Call[]; occurrences: number } {
  const names = fs
    .readdirSync(dir)
    .filter((n) => n.startsWith("infer_") && n.endsWith(".mbt"))
    .sort();
  const calls: Call[] = [];
  let occurrences = 0;
  for (const name of names) {
    const src = fs.readFileSync(path.join(dir, name), "utf8");
    occurrences += src.split("build_step(").length - 1;
    const fns: number[] = [];
    for (const m of src.matchAll(fnRe())) fns.push(m.index);
    for (const m of src.matchAll(callRe())) {
      const phase = m[1] ?? "";
      // 最近一个「起点在调用点之前」的 fn —— fns 天然升序，取末尾命中。
      let family = "";
      for (const idx of fns) {
        if (idx < m.index) family = fnNameAt(src, idx);
        else break;
      }
      calls.push({ phase, family, file: name });
    }
  }
  return { calls, occurrences };
}

/** 从 `fn name(` 的匹配起点取出函数名（复算一次，避免二次捕获组）。 */
function fnNameAt(src: string, index: number): string {
  const tail = src.slice(index, index + 200);
  const m = /^fn (infer_\w+)\(/.exec(tail);
  return m === null ? "" : (m[1] ?? "");
}

/**
 * 四路 + 下限。输入抽取产物与登记表，返回红清单（空 = 绿）。
 * 文案与 Go 版逐字一致（`%q` 对 ASCII phase 名的结果即双引号包裹）。
 */
export function checkSet(rules: Rules, calls: Call[], occurrences: number): string[] {
  const errs: string[] = [];
  // 抽取面下限（正则失能防护）
  if (calls.length < rules.min_call_sites) {
    errs.push(
      `抽取面塌缩：字面量命中 ${calls.length} < min_call_sites ${rules.min_call_sites}（正则失能或大批删除——人工核对后更新 rules.json）`,
    );
  }
  // ④非字面量调用
  if (occurrences > calls.length) {
    errs.push(
      `非字面量 phase 调用 ${occurrences - calls.length} 处（build_step( 出现 ${occurrences} vs 字面量命中 ${calls.length}）——phase 须为字符串字面量（词表闸抽取面要求）`,
    );
  }
  // 代码侧 phase → families
  const codeMap = new Map<string, Set<string>>();
  for (const c of calls) {
    let set = codeMap.get(c.phase);
    if (set === undefined) {
      set = new Set<string>();
      codeMap.set(c.phase, set);
    }
    set.add(c.family);
  }
  // ①未登记扩张（排序输出：Go 侧 map 序随机，此处在等价前提下收紧可复现性）
  for (const ph of [...codeMap.keys()].sort()) {
    if (!hasEntry(rules, ph)) {
      errs.push(
        `未登记扩张：phase "${ph}"（infer_* 新串须先入 rules.json 受控词表——只增不改纪律）`,
      );
    }
  }
  // ②僵尸条目 + ③family 漂移
  for (const e of rules.phases) {
    const got = codeMap.get(e.phase);
    if (got === undefined) {
      errs.push(`僵尸条目：rules.json phase "${e.phase}" 代码零命中（删或回填使用点）`);
      continue;
    }
    const want = new Set(e.families);
    const onlyCode = [...got].filter((f) => !want.has(f)).sort();
    const onlyRules = [...want].filter((f) => !got.has(f)).sort();
    if (onlyCode.length > 0 || onlyRules.length > 0) {
      errs.push(
        `family 漂移：phase "${e.phase}" 代码新增 [${onlyCode.join(" ")}] / 登记-renamed或删除 [${onlyRules.join(" ")}]（连坐 rules.json families）`,
      );
    }
  }
  return errs;
}

function hasEntry(rules: Rules, phase: string): boolean {
  return rules.phases.some((e) => e.phase === phase);
}

function anyStartsWith(errs: string[], prefix: string): boolean {
  return errs.some((e) => e.startsWith(prefix));
}

/** 四路内存注入证红（真数据基线上各注入一路）。 */
export function selftestAll(rules: Rules, calls: Call[], occurrences: number): number {
  const lines: string[] = [];
  let fail = 0;
  const probe = (label: string, errs: string[], prefix: string, shown = prefix): void => {
    if (!anyStartsWith(errs, prefix)) {
      lines.push(`selftest ${label} FAIL：${shown}未红`);
      fail++;
    } else {
      lines.push(`selftest ${label} OK（${shown}红）`);
    }
  };
  // 路 1：未登记扩张
  probe(
    "路 1",
    checkSet(rules, [...calls, { phase: "zz_unregistered", family: "infer_bubble_sort", file: "zz.mbt" }], occurrences + 1),
    "未登记扩张",
  );
  // 路 2：僵尸条目
  const r2: Rules = { ...rules, phases: [...rules.phases, { phase: "zz_zombie", families: ["infer_bubble_sort"] }] };
  probe("路 2", checkSet(r2, calls, occurrences), "僵尸条目");
  // 路 3：family 漂移（把一个登记族的 family 集改掉一格）
  const phases = rules.phases.map((e) => ({ phase: e.phase, families: [...e.families] }));
  for (const e of phases) {
    if (e.families.length > 0) {
      e.families[0] = "infer_zz_renamed";
      break;
    }
  }
  probe("路 3", checkSet({ ...rules, phases }, calls, occurrences), "family 漂移");
  // 路 4：非字面量调用（出现数 > 命中数）
  probe("路 4", checkSet(rules, calls, calls.length + 3), "非字面量", "非字面量调用");
  for (const l of lines) console.log(l);
  return fail;
}

export function loadRules(root: string): Rules {
  const p = path.join(root, RULES_PATH);
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch {
    fatal(`读 ${RULES_PATH}: 文件不存在`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    fatal(`解析 ${RULES_PATH}: ${e instanceof Error ? e.message : String(e)}`);
  }
  const rules = parsed as Rules;
  if (!Array.isArray(rules.phases) || rules.phases.length === 0 || !(rules.min_call_sites > 0)) {
    fatal("rules.json 空词表或 min_call_sites 非法——不得绿");
  }
  return rules;
}

function fatal(msg: string): never {
  process.stderr.write("teaching_phase_vocab: " + msg + "\n");
  process.exit(1);
}

export function main(argv: string[]): number {
  let selftest = false;
  for (const a of argv) {
    if (a === "-selftest" || a === "--selftest") selftest = true;
    else {
      // 用法错 = exit 2（Go flag 包同口径），与判定红的 1 分流
      process.stderr.write(`teaching_phase_vocab: 未知参数 ${JSON.stringify(a)}（用法: teaching_phase_vocab [-selftest]）\n`);
      return 2;
    }
  }
  const root = projectRoot();
  const rules = loadRules(root);
  let ex: { calls: Call[]; occurrences: number };
  try {
    ex = extract(path.join(root, STEPS_DIR));
  } catch (e) {
    fatal(`提取失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (selftest) {
    const fail = selftestAll(rules, ex.calls, ex.occurrences);
    if (fail > 0) return 2;
    process.stdout.write("teaching_phase_vocab selftest 全过（四路注入均红）\n");
    return 0;
  }
  const errs = checkSet(rules, ex.calls, ex.occurrences);
  if (errs.length > 0) {
    process.stderr.write("teaching_phase_vocab 红（phase 受控词表对账不符）：\n");
    for (const e of errs) process.stderr.write("  - " + e + "\n");
    return 1;
  }
  process.stdout.write(
    `teaching_phase_vocab 绿（phase ${rules.phases.length} 条 ↔ infer_* 调用 ${ex.calls.length} 处字面量全等，四路判红在岗）\n`,
  );
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
