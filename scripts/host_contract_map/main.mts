#!/usr/bin/env node
// host_contract_map —— Host Contract 三态对账闸（Go→.mts 重写，refs #273；原 2026-10-04 建）。
//
// 命题：Rust 侧 host_contract_tests.rs（103 条契约测试）与 MoonBit 侧锚
// （host/memory/vm 三包 wbtest）**数量反超但注入面未必对齐**——本闸把
// 「每条 Rust 契约测试在 MoonBit 侧有对应覆盖」变成机判事实：
//
//   anchored  语义精确对应（1:1）
//   merged    mb 锚合并覆盖（多 Rust 测试并一锚 / 跨包锚）
//   missing   缺失（补锚段照搬 oracle 断言补齐——非红提示，清零即收官）
//
// 判据（fail loud，全部实测非缓存）：
//  1. Rust 侧实测测试名 ⊆ 表（漏映射即红——映射有洞）；
//  2. 表内每条 mb_anchors 实存于三包 wbtest 锚名集（陈旧引用即红）；
//  3. mb 锚未被任何条目引用 → 提示（MoonBit 侧自增锚，无 Rust 对应——
//     正常形态：mb 侧受检化分叉锚/输出通道锚等本就多于 oracle）；
//  4. missing 条目数打印（非红）；`--strict` 时 missing>0 红（收官门）。
//
// J9：--selftest 注入三路（漏映射 / 陈旧锚名 / 零误报）必红。
//
// 退出码（与 Go 版一致）：判红 1 / 用法或环境错 2。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export const RULES_PATH = "scripts/host_contract_map/rules.json";
export const RUST_NAMES_PATH = "scripts/host_contract_map/rust_contract_names.json";
const MB_PKGS = ["moonbit/host", "moonbit/memory", "moonbit/vm"];

const RE_MB_TEST = /^\s*test "([^"]+)"/gm;

export interface Mapping {
  rust_test: string;
  state: string;
  mb_anchors: string[];
  note?: string;
}

export interface Rules {
  mappings: Mapping[];
}

function fatal(msg: string): never {
  process.stderr.write(`错误: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

/** 字节序排序（Go sort.Strings 口径）。 */
export function byteSort(keys: Iterable<string>): string[] {
  return [...keys].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

/**
 * oracle 契约测试名册（去 test_ 前缀）。
 * 工序④删区（2026-10-05）：Rust 契约测试源随区删除——名册冻结为仓内资产
 * （native-removal-baseline 提取 103 条）；三态对账语义不变（名册 ⊆ 映射表）。
 */
export function rustHostTestNames(): Set<string> {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(RUST_NAMES_PATH), "utf8");
  } catch (e) {
    fatal(`读契约名册失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  let doc: { names?: unknown };
  try {
    doc = JSON.parse(raw) as { names?: unknown };
  } catch {
    fatal("契约名册坏或空集——空集不得绿");
  }
  if (!Array.isArray(doc.names) || doc.names.length === 0) fatal("契约名册坏或空集——空集不得绿");
  return new Set((doc.names as string[]).map((n) => n.replace(/^test_/, "")));
}

/** 三包 wbtest 锚名（host / memory / vm，文件名含 wbtest 或 _test 的 .mbt）。 */
export function mbAnchorNames(): Set<string> {
  const out = new Set<string>();
  for (const dir of MB_PKGS) {
    let ents: string[];
    try {
      ents = fs.readdirSync(abs(dir));
    } catch (e) {
      fatal(`读包目录失败 ${dir}: ${e instanceof Error ? e.message : String(e)}`);
    }
    for (const name of ents) {
      // Go 原判：!HasSuffix(".mbt") || (!wbtest && !_test)
      if (!name.endsWith(".mbt") || (!name.includes("wbtest") && !name.includes("_test"))) continue;
      let raw: string;
      try {
        raw = fs.readFileSync(abs(path.join(dir, name)), "utf8");
      } catch (e) {
        fatal(`读锚文件失败: ${e instanceof Error ? e.message : String(e)}`);
      }
      for (const m of raw.matchAll(RE_MB_TEST)) out.add(m[1] ?? "");
    }
  }
  if (out.size === 0) fatal("mb 锚名抽取为空集（正则失配？）——空集不得绿");
  return out;
}

export function loadRules(): Mapping[] {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(RULES_PATH), "utf8");
  } catch (e) {
    fatal(`读映射表失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  let r: Rules;
  try {
    r = JSON.parse(raw) as Rules;
  } catch {
    fatal("映射表非法 JSON");
  }
  if (!Array.isArray(r.mappings) || r.mappings.length === 0) fatal("映射表为空集（空集不得绿）");
  for (const m of r.mappings) {
    if (!["anchored", "merged", "missing"].includes(m.state)) {
      fatal(`条目 ${m.rust_test} 非法 state "${m.state}"（三态枚举外）`);
    }
  }
  return r.mappings;
}

/** 判据核心（导出供测试直接注入内存数据）。 */
export function judge(rust: Set<string>, mb: Set<string>, maps: Mapping[], strict: boolean): { lines: string[]; exit: number } {
  const lines: string[] = [];
  let exit = 0;
  const inTable = new Set<string>();
  const anchoredUsed = new Map<string, number>();
  const usedMb = new Set<string>();
  const missing: string[] = [];
  for (const m of maps) {
    if (inTable.has(m.rust_test)) {
      lines.push(`[DUP] 表内重复条目 ${m.rust_test}`);
      exit = 1;
    }
    inTable.add(m.rust_test);
    if (m.state === "missing") {
      missing.push(m.rust_test);
      continue;
    }
    if (m.mb_anchors.length === 0) {
      lines.push(`[BAD] ${m.rust_test} state=${m.state} 但 mb_anchors 为空`);
      exit = 1;
    }
    for (const a of m.mb_anchors) {
      if (!mb.has(a)) {
        lines.push(`[STALE] ${m.rust_test} 指向不存在的锚 "${a}"（陈旧引用）`);
        exit = 1;
      }
      usedMb.add(a);
    }
    // 语义保险丝（审阅 P3-③，2026-10-04）：机判可及的两条——1:1 anchored 要求
    // 锚名与测试名对齐；同一锚被多条 anchored 复用应改 state=merged。
    if (m.state === "anchored") {
      if (m.mb_anchors.length !== 1 || m.mb_anchors[0] !== m.rust_test) {
        lines.push(
          `[CROSS] ${m.rust_test} state=anchored 但锚名不对齐 [${m.mb_anchors.join(" ")}]（1:1 要求同名；合并覆盖改 state=merged）`,
        );
        exit = 1;
      }
      const key = m.mb_anchors[0] ?? "";
      anchoredUsed.set(key, (anchoredUsed.get(key) ?? 0) + 1);
    }
  }
  for (const [a, n] of anchoredUsed) {
    if (n > 1) {
      lines.push(`[REUSE] 锚 "${a}" 被 ${n} 条 anchored 复用——合并覆盖改 state=merged 并补 note`);
      exit = 1;
    }
  }
  // 判据 1：oracle 实测 ⊆ 表
  const holes = byteSort([...rust].filter((t) => !inTable.has(t)));
  if (holes.length > 0) {
    lines.push(`[HOLE] oracle 契约测试 ${holes.length} 条无映射：[${holes.join(" ")}]`);
    exit = 1;
  }
  // 判据 1b：表指向不存在的 oracle 测试
  const ghosts = byteSort([...inTable].filter((t) => !rust.has(t)));
  if (ghosts.length > 0) {
    lines.push(`[GHOST] 表内条目指向不存在的 oracle 测试：[${ghosts.join(" ")}]`);
    exit = 1;
  }
  // 判据 3：mb 侧未被引用锚（提示）
  const extra = byteSort([...mb].filter((a) => !usedMb.has(a)));
  lines.push(
    `oracle 契约 ${rust.size} 条：anchored+merged ${rust.size - missing.length} / missing ${missing.length}；mb 锚 ${mb.size} 个（被引用 ${usedMb.size} / 侧自增 ${extra.length}——受检化分叉锚等正常多出）`,
  );
  if (missing.length > 0) {
    lines.push(`[TODO] 缺失 ${missing.length} 条（补锚段照搬 oracle 断言）：[${missing.join(" ")}]`);
    if (strict) {
      lines.push("strict：missing 非空判红（收官门）");
      exit = 1;
    }
  }
  if (exit === 0) lines.push("host_contract_map: 对账一致（映射无洞 / 锚引用无陈旧）");
  return { lines, exit };
}

export function run(strict: boolean): number {
  const rust = rustHostTestNames();
  const mb = mbAnchorNames();
  const maps = loadRules();
  const { lines, exit } = judge(rust, mb, maps, strict);
  for (const l of lines) process.stdout.write(l + "\n");
  return exit;
}

export function hasHole(rust: Set<string>, maps: Mapping[]): boolean {
  const inTable = new Set(maps.map((m) => m.rust_test));
  return [...rust].some((t) => !inTable.has(t));
}

export function hasStale(mb: Set<string>, maps: Mapping[]): boolean {
  return maps.some((m) => m.mb_anchors.some((a) => !mb.has(a)));
}

/** 三路注入必红：① 漏映射（洞）② 陈旧锚名 ③ 完整映射零误报。 */
export function selfTest(): number {
  const rust = new Set(["t1", "t2"]);
  const mb = new Set(["a1"]);
  const fail = (msg: string): number => {
    process.stdout.write(`selftest: FAIL——${msg}\n`);
    return 2;
  };
  const m1: Mapping[] = [{ rust_test: "t1", state: "anchored", mb_anchors: ["a1"] }];
  if (!hasHole(rust, m1)) return fail("漏映射未检出（洞判据失效）");
  const m2: Mapping[] = [
    { rust_test: "t1", state: "anchored", mb_anchors: ["a1"] },
    { rust_test: "t2", state: "anchored", mb_anchors: ["ghost_anchor"] },
  ];
  if (!hasStale(mb, m2)) return fail("陈旧锚引用未检出");
  const m3: Mapping[] = [
    { rust_test: "t1", state: "anchored", mb_anchors: ["a1"] },
    { rust_test: "t2", state: "merged", mb_anchors: ["a1"] },
  ];
  if (hasHole(rust, m3) || hasStale(mb, m3)) return fail("完整映射误报");
  process.stdout.write("selftest：洞/陈旧/零误报三锚 通过\n");
  return 0;
}

export function main(argv: string[]): number {
  let strict = false;
  let self = false;
  for (const a of argv) {
    if (a === "-strict" || a === "--strict") strict = true;
    else if (a === "-selftest" || a === "--selftest") self = true;
    else {
      // 用法错 = exit 2（Go flag 包同口径）
      process.stderr.write(`错误: 未知参数 ${JSON.stringify(a)}（用法: host_contract_map [-strict] [-selftest]）\n`);
      return 2;
    }
  }
  projectRoot();
  if (self) return selfTest();
  return run(strict);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
