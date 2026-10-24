#!/usr/bin/env node
// diff_ledger —— 差异台账对账闸（Go→.mts 重写，refs #273；原 S8 批零号二段 2026-09-30）。
//
// 单源：scripts/diff_ledger/ledger.json。本闸把总计划 §8 的守门规则机判化：
//   「引擎行为与台账冲突时要么改行为要么改台账，禁止沉默漂移」
//
// 判定四路（任一红即 exit 1；输入读不到/解析失败 fail loud exit 2）：
//  1. schema：schema 版本串；capability_flags 恰 17 键（键集锁定——加键/删键即红）；
//     differences 非空；ID 唯一且格式 ^DIFF-[A-Z0-9]+(-[A-Z0-9]+)*-[0-9]{2}$；
//     class / carry_over / status / evidence 枚举域；anchors 三键齐备且元素非空；
//     detectable_by_defense 值域 + 与 anchors 一致性（D18）。
//  2. 正向对账：ledger anchors 引用的每条 case 必须真实存在于对应防线的 known 白名单。
//  3. 反向对账：三防线 known 白名单的每一条必须被 ledger 至少一条引用（沉默漂移即红）。
//  4. --selftest：注入六路违规证红（J9；任一路不红 exit 2）。
//
// 三防线 known 真值源：
//   - clang_direct：scripts/clang_direct/known_direct.json（case 字段）
//   - vm_diff：scripts/vm_diff/known_diffs.json（case 字段）
//   - shadow：**闸内清单**（下方 SHADOW_KNOWN，原 native/AGENTS.md 随删区冻结于此）
//
// 用法：
//   node scripts/diff_ledger/main.mts [ledger.json]
//   node scripts/diff_ledger/main.mts --selftest
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export const LEDGER_PATH = "scripts/diff_ledger/ledger.json";
export const CLANG_DIRECT_KNOWN = "scripts/clang_direct/known_direct.json";
export const VM_DIFF_KNOWN = "scripts/vm_diff/known_diffs.json";

// ---------------------------------------------------------------- ledger 模型

export interface Anchors {
  shadow_known: string[];
  clang_direct_known: string[];
  vm_diff_known: string[];
}

export interface Difference {
  id: string;
  title: string;
  class: string;
  carry_over: string;
  status: string;
  evidence: string;
  anchors: Anchors;
  detectable_by_defense: string[];
}

export interface Ledger {
  schema: string;
  capability_flags: Record<string, unknown>;
  differences: Difference[];
}

// ---------------------------------------------------------------- 枚举与常量

const CLASS_SET = new Set(["architectural", "implementable", "pedagogical"]);
const CARRY_OVER_SET = new Set(["inherit", "fix", "drop", "retest"]);
const STATUS_SET = new Set([
  "verified-run",
  "verified-code",
  "verified-anchor",
  "verified-doc",
  "resolved-verified",
  "open",
  "open-unverified",
]);
const EVIDENCE_SET = new Set(["run", "code", "anchor", "doc"]);

/** detectable_by_defense 值域（D18 修复 2026-09-30；加值须连坐本枚举）。 */
const DETECTABLE_SET = new Set([
  "shadow",
  "clang_direct",
  "vm_diff",
  "libc_single_source",
  "memory-verify-wbtest",
]);

const RE_ID = /^DIFF-[A-Z0-9]+(-[A-Z0-9]+)*-[0-9]{2}$/;

/** 17 键锁定（知识沉淀附录 A 原数；键集变更即红——改承诺面须连坐本闸与 §8）。 */
export const CAPABILITY_FLAGS_KEYS = [
  "pointer_width_bytes",
  "struct_layout",
  "float_literal_default",
  "float_compare",
  "allocator",
  "quarantine_budget_kb",
  "heap_size_bytes",
  "realloc_always_moves",
  "printf_dynamic_width",
  "fprintf_custom_stream",
  "generic_match",
  "compound_literal_lifetime",
  "wasm_catch_unwind",
  "time_source",
  "include_once_implicit",
  "max_include_depth",
  "include_cycle_detect",
];

/**
 * shadow 防线实跑 known_issue 清单（真值源见头注；.c 后缀与 ledger anchors 口径一致）。
 * putchar_range.c 已移除（2026-10-05 脱钩修复批：出口层字节直写修复）。
 */
export const SHADOW_KNOWN = ["function_pointer_sizeof.c", "sizeof_array_param.c", "bTree_default.c"];

// ---------------------------------------------------------------- 判定核心

function has(xs: string[], v: string): boolean {
  return xs.includes(v);
}

function referenced(l: Ledger, which: "shadow" | "cd" | "vd", c: string): boolean {
  return l.differences.some((d) => {
    const list =
      which === "shadow" ? d.anchors.shadow_known : which === "cd" ? d.anchors.clang_direct_known : d.anchors.vm_diff_known;
    return has(list, c);
  });
}

/**
 * 对 ledger 副本跑 schema + 双向对账；返回全部违规（空 = 绿）。
 * known 三参为防线真值清单，由调用方注入（正常跑 = 读盘 / selftest = 构造）。
 */
export function validate(l: Ledger, shadow: string[], clangDirect: string[], vmDiff: string[]): string[] {
  const bad: string[] = [];

  // —— schema ——
  if (l.schema !== "vitro-diff-ledger-v1") bad.push("schema 字符串 ≠ vitro-diff-ledger-v1: " + l.schema);
  const flagKeys = Object.keys(l.capability_flags ?? {});
  if (flagKeys.length !== CAPABILITY_FLAGS_KEYS.length) {
    bad.push(`capability_flags 键数 ${flagKeys.length} ≠ ${CAPABILITY_FLAGS_KEYS.length}（键集锁定）`);
  }
  for (const k of CAPABILITY_FLAGS_KEYS) {
    if (!(k in (l.capability_flags ?? {}))) bad.push("capability_flags 缺锁定键: " + k);
  }
  if (l.differences.length === 0) bad.push("differences 为空");
  const seen = new Set<string>();
  for (const d of l.differences) {
    if (!RE_ID.test(d.id)) bad.push("ID 格式非法: " + d.id);
    if (seen.has(d.id)) bad.push("ID 重复: " + d.id);
    seen.add(d.id);
    if (!CLASS_SET.has(d.class)) bad.push(d.id + ": class 越界: " + d.class);
    if (!CARRY_OVER_SET.has(d.carry_over)) bad.push(d.id + ": carry_over 越界: " + d.carry_over);
    if (!STATUS_SET.has(d.status)) bad.push(d.id + ": status 越界: " + d.status);
    if (!EVIDENCE_SET.has(d.evidence)) bad.push(d.id + ": evidence 越界: " + d.evidence);
    for (const c of d.anchors.shadow_known) if (c.trim() === "") bad.push(d.id + ": shadow_known 含空串");
    for (const c of d.anchors.clang_direct_known) if (c.trim() === "") bad.push(d.id + ": clang_direct_known 含空串");
    for (const c of d.anchors.vm_diff_known) if (c.trim() === "") bad.push(d.id + ": vm_diff_known 含空串");
    // D18：detectable_by_defense 域枚举 + 与 anchors 一致性（⊇ 有锚防线名）
    for (const v of d.detectable_by_defense) {
      if (!DETECTABLE_SET.has(v)) bad.push(d.id + ": detectable_by_defense 越界: " + v);
    }
    const anchored: Array<[string, string[]]> = [
      ["shadow", d.anchors.shadow_known],
      ["clang_direct", d.anchors.clang_direct_known],
      ["vm_diff", d.anchors.vm_diff_known],
    ];
    for (const [defense, cases] of anchored) {
      if (cases.length > 0 && !has(d.detectable_by_defense, defense)) {
        bad.push(d.id + ": detectable_by_defense 缺有锚防线 " + defense + "（anchors 与旁证字段矛盾——D18）");
      }
    }
  }

  // —— 正向：anchors 引用 ⊆ 防线真值 ——
  for (const d of l.differences) {
    for (const c of d.anchors.shadow_known) {
      if (!has(shadow, c)) bad.push(d.id + ": shadow_known 引用不存在的豁免条目: " + c);
    }
    for (const c of d.anchors.clang_direct_known) {
      if (!has(clangDirect, c)) bad.push(d.id + ": clang_direct_known 引用不存在的豁免条目: " + c);
    }
    for (const c of d.anchors.vm_diff_known) {
      if (!has(vmDiff, c)) bad.push(d.id + ": vm_diff_known 引用不存在的豁免条目: " + c);
    }
  }

  // —— 反向：防线真值每条必须被至少一条差异收编 ——
  for (const c of shadow) {
    if (!referenced(l, "shadow", c)) bad.push("shadow known 条目未被台账收编（沉默漂移）: " + c);
  }
  for (const c of clangDirect) {
    if (!referenced(l, "cd", c)) bad.push("clang_direct known 条目未被台账收编（沉默漂移）: " + c);
  }
  for (const c of vmDiff) {
    if (!referenced(l, "vd", c)) bad.push("vm_diff known 条目未被台账收编（沉默漂移）: " + c);
  }
  return bad;
}

/**
 * 结构守卫（#292 审阅 P3-3）：Go 版靠 `json.Unmarshal` 到 struct 天然拒绝
 * 畸形结构并给出可读违规；`as Ledger` 只骗 tsc，畸形输入会以 `TypeError` 栈
 * 崩掉（仍是红，但不是判定型脚本该有的 fail loud 形态）。
 */
export function assertLedgerShape(l: Ledger): string {
  if (l === null || typeof l !== "object" || Array.isArray(l)) return "顶层必须是对象";
  if (!Array.isArray(l.differences)) return "differences 必须是数组";
  if (l.capability_flags === null || typeof l.capability_flags !== "object" || Array.isArray(l.capability_flags)) {
    return "capability_flags 必须是对象";
  }
  for (const [i, d] of l.differences.entries()) {
    if (d === null || typeof d !== "object" || Array.isArray(d)) return `differences[${i}] 必须是对象`;
    const a = d.anchors;
    if (a === null || typeof a !== "object" || Array.isArray(a)) return `differences[${i}].anchors 必须是对象`;
    for (const k of ["shadow_known", "clang_direct_known", "vm_diff_known"] as const) {
      const v = (a as unknown as Record<string, unknown>)[k];
      if (v === undefined) (a as unknown as Record<string, unknown>)[k] = [];
      else if (!Array.isArray(v)) return `differences[${i}].anchors.${k} 必须是数组`;
    }
    if (d.detectable_by_defense === undefined) d.detectable_by_defense = [];
    else if (!Array.isArray(d.detectable_by_defense)) return `differences[${i}].detectable_by_defense 必须是数组`;
  }
  return "";
}

// ---------------------------------------------------------------- known 加载

export function loadKnownCases(p: string): string[] {
  let raw: string;
  try {
    raw = fs.readFileSync(path.isAbsolute(p) ? p : path.join(projectRoot(), p), "utf8");
  } catch (e) {
    process.stderr.write(`[diff_ledger] fail loud：读不到 ${p}：${e instanceof Error ? e.message : String(e)}\n`);
    process.exit(2);
  }
  let entries: Array<{ case?: string }>;
  try {
    entries = JSON.parse(raw) as typeof entries;
  } catch (e) {
    process.stderr.write(`[diff_ledger] fail loud：${p} 解析失败：${e instanceof Error ? e.message : String(e)}\n`);
    process.exit(2);
  }
  // #292 审阅 P3-3：非对象条目 / 缺 case 一律 fail loud（Go 版 struct 解码同口径）
  return entries.map((e, i) => {
    if (e === null || typeof e !== "object" || Array.isArray(e)) {
      process.stderr.write(`[diff_ledger] fail loud：${p} 第 ${i} 条不是对象\n`);
      process.exit(2);
    }
    if (typeof e.case !== "string") {
      process.stderr.write(`[diff_ledger] fail loud：${p} 第 ${i} 条缺 case 字符串\n`);
      process.exit(2);
    }
    return e.case;
  });
}

// ---------------------------------------------------------------- selftest（J9）

/** 注入六路违规，每类必须红；任一不红 = exit 2（闸自身不可信）。 */
export function selftest(good: Ledger, shadow: string[], clangDirect: string[], vmDiff: string[]): number {
  const probes: Array<{ name: string; mutate: (l: Ledger) => void }> = [
    {
      name: "假 anchor（shadow 引用不存在条目）",
      mutate: (l) => {
        for (const d of l.differences) {
          if (d.id === "DIFF-PTR-4BYTE-01") d.anchors.shadow_known.push("ghost_case.c");
        }
      },
    },
    {
      name: "反向失覆盖（摘掉 bTree 收编）",
      mutate: (l) => {
        for (const d of l.differences) {
          d.anchors.shadow_known = d.anchors.shadow_known.filter((c) => c !== "bTree_default.c");
        }
      },
    },
    {
      name: "class 枚举越界",
      mutate: (l) => {
        l.differences[0]!.class = "cosmetic";
      },
    },
    {
      name: "ID 重复",
      mutate: (l) => {
        l.differences[1]!.id = l.differences[0]!.id;
      },
    },
    {
      name: "capability_flags 删键",
      mutate: (l) => {
        delete l.capability_flags["time_source"];
      },
    },
    {
      name: "detectable 与 anchors 矛盾（D18：摘掉有锚防线）",
      mutate: (l) => {
        for (const d of l.differences) {
          if (d.id === "DIFF-PTR-4BYTE-01") d.detectable_by_defense = [];
        }
      },
    },
  ];
  let ok = true;
  for (const p of probes) {
    // 深拷贝差异切片与 map（probe 不得污染 good）
    const cp: Ledger = {
      schema: good.schema,
      capability_flags: { ...good.capability_flags },
      differences: good.differences.map((d) => ({
        ...d,
        anchors: {
          shadow_known: [...d.anchors.shadow_known],
          clang_direct_known: [...d.anchors.clang_direct_known],
          vm_diff_known: [...d.anchors.vm_diff_known],
        },
        detectable_by_defense: [...d.detectable_by_defense],
      })),
    };
    p.mutate(cp);
    const violations = validate(cp, shadow, clangDirect, vmDiff);
    if (violations.length === 0) {
      process.stdout.write(`[selftest] ✗ 不红（缺陷）： ${p.name}\n`);
      ok = false;
    } else {
      process.stdout.write(`[selftest] ✓ 红（${violations.length} 条违规）：${p.name}\n`);
    }
  }
  if (!ok) {
    process.stderr.write("[diff_ledger] selftest 存在不红路径，拒绝运行\n");
    process.exit(2);
  }
  return 0;
}

// ---------------------------------------------------------------- main

export function main(argv: string[]): number {
  let ledgerPath = LEDGER_PATH;
  const first = argv[0];
  if (first !== undefined && !first.startsWith("-")) ledgerPath = first;

  const absLedger = path.isAbsolute(ledgerPath) ? ledgerPath : path.join(projectRoot(), ledgerPath);
  let raw: string;
  try {
    raw = fs.readFileSync(absLedger, "utf8");
  } catch (e) {
    process.stderr.write(`[diff_ledger] fail loud：读不到 ${ledgerPath}：${e instanceof Error ? e.message : String(e)}\n`);
    return 2;
  }
  let l: Ledger;
  try {
    l = JSON.parse(raw) as Ledger;
  } catch (e) {
    process.stderr.write(`[diff_ledger] fail loud：${ledgerPath} 解析失败：${e instanceof Error ? e.message : String(e)}\n`);
    return 2;
  }

  const clangDirect = loadKnownCases(CLANG_DIRECT_KNOWN);
  const vmDiff = loadKnownCases(VM_DIFF_KNOWN);
  const shadow = [...SHADOW_KNOWN];

  if (first === "--selftest" || first === "-selftest") {
    selftest(l, shadow, clangDirect, vmDiff);
    process.stdout.write("[selftest] 六路全红，闸可信\n");
    return 0;
  }

  const shape = assertLedgerShape(l);
  if (shape !== "") {
    process.stderr.write(`[diff_ledger] fail loud：${ledgerPath} 结构不可用：${shape}（输入不可用 = exit 2）\n`);
    return 2;
  }
  const violations = validate(l, shadow, clangDirect, vmDiff);
  process.stdout.write(
    `[diff_ledger] 条目 ${l.differences.length} | capability_flags ${Object.keys(l.capability_flags ?? {}).length} | shadow ${shadow.length} + clang_direct ${clangDirect.length} + vm_diff ${vmDiff.length} 条 known 对账\n`,
  );
  if (violations.length > 0) {
    process.stderr.write(`[diff_ledger] ✗ ${violations.length} 条违规：\n`);
    for (const v of violations) process.stderr.write("  - " + v + "\n");
    return 1;
  }
  process.stdout.write("[diff_ledger] PASS：schema + 双向对账全绿（守门规则机判化就位）\n");
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
