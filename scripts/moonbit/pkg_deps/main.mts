#!/usr/bin/env node
// pkg_deps：MoonBit 包依赖方向断言（Go→.mts 重写，refs #273；原 S5 收尾批 · 架构审阅 v2 A 组 #6）。
//
// 总计划 §4 的硬约束是「依赖严格单向无环」，并按 L0–L9 分层给出包图——
// 但此前零 CI 校验。本闸把它变成红线。
//
// 用法（**仓库根**）：
//   node scripts/moonbit/pkg_deps/main.mts            # 分层与依赖报告 + 判定
//   node scripts/moonbit/pkg_deps/main.mts -check     # 判定（CI 门禁用）
//   node scripts/moonbit/pkg_deps/main.mts --selftest # J9：注入越层边必红
//
// 判据（分层表见 rules.json）：
//   ① 每个包必须匹配到层号（新包未登记 → 红）
//   ② 模块内依赖 D 满足 level(D) <= level(P)（同层允许，向上越层即红）
//   ③ 跨包依赖图无环（DFS 回边即红）
//   ④ 空集不得绿（0 包或 0 依赖 → 红）
//
// cmd/* 为差分工具层，豁免方向检查（仍参与环检测）；外部分依赖不参与判定。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

export const RULES_PATH = "scripts/moonbit/pkg_deps/rules.json";

export interface RulesDoc {
  schema: number;
  root: string;
  module: string;
  levels: Record<string, number>;
  exempt_prefixes: string[];
}

export interface PkgInfo {
  /** 相对 root，如 "lexer/internal/pp" */
  name: string;
  deps: string[];
  level: number;
  levelKey: string;
  exempt: boolean;
}

const RE_IMPORT_BLOCK = /import\s*\{([\s\S]*?)\}/g;
const RE_QUOTED = /"([^"]+)"/g;

function fatal(msg: string): never {
  process.stderr.write(`pkg_deps: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

function byteSort(xs: string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

/** parseDeps：解析 moon.pkg 全部 import 块（含 for "test"），只留同 module 前缀。 */
export function parseDeps(pkgPath: string, module: string, selfName: string): string[] {
  let data: string;
  try {
    data = fs.readFileSync(abs(pkgPath), "utf8");
  } catch (e) {
    fatal(`读 ${pkgPath} 失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  const seen = new Set<string>();
  const out: string[] = [];
  const prefix = module + "/";
  for (const blk of data.matchAll(RE_IMPORT_BLOCK)) {
    for (const m of (blk[1] ?? "").matchAll(RE_QUOTED)) {
      const dep = m[1] ?? "";
      if (!dep.startsWith(prefix)) continue; // 外部分（moonbitlang/*）不判定
      const pkgName = dep.slice(prefix.length);
      if (pkgName === selfName || seen.has(pkgName)) continue;
      seen.add(pkgName);
      out.push(pkgName);
    }
  }
  return byteSort(out);
}

/** 最长前缀匹配（子包继承父包层号）。 */
export function longestPrefixLevel(pkg: string, levels: Record<string, number>): { key: string; level: number } {
  let best = "";
  for (const k of Object.keys(levels)) {
    if (pkg === k || pkg.startsWith(k + "/")) {
      if (k.length > best.length) best = k;
    }
  }
  if (best === "") return { key: "", level: -1 };
  return { key: best, level: levels[best]! };
}

function hasPrefixAny(s: string, prefixes: string[]): boolean {
  return prefixes.some((p) => s === p || s.startsWith(p + "/"));
}

export function scan(rd: RulesDoc): { pkgs: Map<string, PkgInfo>; order: string[] } {
  const pkgs = new Map<string, PkgInfo>();
  const rootSlash = rd.root.replace(/\/+$/, "");
  const walk = (rel: string): void => {
    const dir = rel === "" ? rootSlash : `${rootSlash}/${rel}`;
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(abs(dir), { withFileTypes: true });
    } catch {
      return;
    }
    const hasPkg = ents.some((e) => !e.isDirectory() && e.name === "moon.pkg");
    if (hasPkg && rel !== "" && rel !== ".") {
      const deps = parseDeps(`${dir}/moon.pkg`, rd.module, rel);
      const lv = longestPrefixLevel(rel, rd.levels ?? {});
      pkgs.set(rel, { name: rel, deps, level: lv.level, levelKey: lv.key, exempt: hasPrefixAny(rel, rd.exempt_prefixes ?? []) });
    }
    for (const ent of ents) {
      if (!ent.isDirectory()) continue;
      if (ent.name === "_build" || ent.name === ".mooncakes" || ent.name === ".git") continue;
      walk(rel === "" ? ent.name : `${rel}/${ent.name}`);
    }
  };
  walk("");
  if (pkgs.size === 0) fatal(`未发现任何包（root=${rd.root}）——检查工作目录或 rules.json 的 root`);
  return { pkgs, order: byteSort([...pkgs.keys()]) };
}

export function findCycle(pkgs: Map<string, PkgInfo>, order: string[]): string[] {
  const WHITE = 0;
  const GRAY = 1;
  const BLACK = 2;
  const color = new Map<string, number>();
  let stack: string[] = [];
  let cycle: string[] = [];

  const dfs = (n: string): boolean => {
    color.set(n, GRAY);
    stack.push(n);
    const p = pkgs.get(n)!;
    for (const d of p.deps) {
      if (!pkgs.has(d)) continue;
      const c = color.get(d) ?? WHITE;
      if (c === GRAY) {
        const i = stack.indexOf(d);
        cycle = i >= 0 ? [...stack.slice(i), d] : [d, n, d];
        return true;
      }
      if (c === WHITE && dfs(d)) return true;
    }
    stack.pop();
    color.set(n, BLACK);
    return false;
  };

  for (const n of order) {
    if ((color.get(n) ?? WHITE) === WHITE && dfs(n)) return cycle;
  }
  return [];
}

/** 三条判据全过才绿；不早退，一次暴露全部违规。 */
export function verdict(rd: RulesDoc, pkgs: Map<string, PkgInfo>, order: string[]): boolean {
  let ok = true;
  const unregistered: string[] = [];
  let totalDeps = 0;
  for (const n of order) {
    const p = pkgs.get(n)!;
    if (!p.exempt && p.levelKey === "") unregistered.push(n);
    totalDeps += p.deps.length;
  }
  if (unregistered.length > 0) {
    ok = false;
    process.stdout.write(`  [未登记] 下列包在 rules.json 的 levels 中无匹配（新包必须登记分层）：${unregistered.join(", ")}\n`);
  }
  if (totalDeps === 0) {
    ok = false;
    process.stdout.write("  [空集] 解析出 0 条模块内依赖——扫描口径可能已失效，拒绝判定\n");
  }

  const violations: string[] = [];
  for (const n of order) {
    const p = pkgs.get(n)!;
    if (p.exempt) continue;
    for (const d of p.deps) {
      const dp = pkgs.get(d);
      if (dp === undefined || dp.exempt) continue;
      if (dp.levelKey === "") continue; // 已在①报
      if (dp.level > p.level) {
        ok = false;
        violations.push(`${n}(L${p.level} ${p.levelKey}) → ${d}(L${dp.level} ${dp.levelKey})`);
      }
    }
  }
  if (violations.length > 0) {
    process.stdout.write(`  [越层] ${violations.length} 条依赖指向更高层（依赖必须向下或同层）：\n`);
    for (const v of violations) process.stdout.write(`    ${v}\n`);
  }

  const cycle = findCycle(pkgs, order);
  if (cycle.length > 0) {
    ok = false;
    process.stdout.write(`  [成环] ${cycle.join(" → ")}\n`);
  }
  return ok;
}

export function report(rd: RulesDoc, pkgs: Map<string, PkgInfo>, order: string[]): void {
  process.stdout.write(`MoonBit 包依赖方向（${pkgs.size} 包；分层源 = 总计划 §4 L0–L9）\n`);
  for (const n of order) {
    const p = pkgs.get(n)!;
    let tag = `L${p.level}`;
    if (p.exempt) tag = "工具层(豁免)";
    else if (p.levelKey === "") tag = "未登记";
    const dep = p.deps.length > 0 ? p.deps.join(", ") : "(无)";
    process.stdout.write(`  ${n.padEnd(24)} ${tag.padEnd(14)} → ${dep}\n`);
  }
}

function lowestAndHighestExisting(pkgs: Map<string, PkgInfo>, order: string[]): { lo: string; hi: string; loLv: number; hiLv: number } {
  let lo = "";
  let hi = "";
  let loLv = Number.MAX_SAFE_INTEGER;
  let hiLv = -1;
  for (const n of order) {
    const p = pkgs.get(n)!;
    if (p.exempt || p.levelKey === "") continue;
    if (p.level < loLv) {
      loLv = p.level;
      lo = n;
    }
    if (p.level > hiLv) {
      hiLv = p.level;
      hi = n;
    }
  }
  return { lo, hi, loLv, hiLv };
}

/** J9：先确认基线绿，再注入一条必然越层的虚拟依赖（最低层 → 最高层）。 */
export function selftestRun(rd: RulesDoc, pkgs: Map<string, PkgInfo>, order: string[]): number {
  if (!verdict(rd, pkgs, order)) {
    process.stdout.write("pkg_deps: selftest ABORT——基线不绿，注入后的红无法归因\n");
    return 2;
  }
  const { lo, hi, loLv, hiLv } = lowestAndHighestExisting(pkgs, order);
  if (lo === "" || hi === "") {
    process.stdout.write("pkg_deps: selftest ABORT——分层表不足以构造越层对\n");
    return 2;
  }
  if (loLv === hiLv) {
    process.stdout.write("pkg_deps: selftest ABORT——实际包全在同层，无法构造越层对\n");
    return 2;
  }
  const inj = new Map<string, PkgInfo>();
  for (const [k, v] of pkgs) inj.set(k, { ...v, deps: [...v.deps] });
  if (inj.get(lo)!.deps.includes(hi)) {
    process.stdout.write(`pkg_deps: selftest ABORT——${lo} 已依赖 ${hi}，注入无效\n`);
    return 2;
  }
  inj.get(lo)!.deps.push(hi);
  process.stdout.write(`pkg_deps: selftest 已注入越层边 ${lo}(L${loLv}) → ${hi}(L${hiLv})\n`);
  if (verdict(rd, inj, order)) {
    process.stdout.write("pkg_deps: selftest FAIL——注入越层边后仍判绿，闸门失效\n");
    return 1;
  }
  process.stdout.write("pkg_deps: selftest PASS——注入的越层边被捕获（红），J9 证红成立\n");
  return 0;
}

export function loadRules(p = RULES_PATH): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(p), "utf8");
  } catch (e) {
    fatal(`读规则失败（须在仓库根运行）: ${e instanceof Error ? e.message : String(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`规则解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (rd.schema !== 1) fatal(`规则 schema 不支持: ${rd.schema}（期望 1）`);
  return rd;
}

export function main(argv: string[]): number {
  let selftest = false;
  let check = false;
  for (const a of argv) {
    if (a === "--selftest" || a === "-selftest") selftest = true;
    else if (a === "-check") check = true;
    else fatal(`未知参数: ${a}（可用：-check / --selftest）`);
  }
  const rd = loadRules();
  const { pkgs, order } = scan(rd);
  if (!check) report(rd, pkgs, order);
  if (selftest) return selftestRun(rd, pkgs, order);
  if (verdict(rd, pkgs, order)) {
    process.stdout.write(`pkg_deps: PASS（${pkgs.size} 包，分层方向与无环均成立）\n`);
    return 0;
  }
  process.stdout.write("pkg_deps: FAIL——依赖方向违规（详见上方）\n");
  return 1;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
