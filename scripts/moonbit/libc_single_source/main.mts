#!/usr/bin/env node
// libc_single_source：libc 三名单单源对账闸（Go→.mts 重写，refs #273；原 S5 收尾批 · S6 前置）。
//
// 背景：Rust 侧「这个名字是不是 builtin」的判据是两张表的并集——
// `host_func_id::by_user_name`（路由名）∪ `BYTECODE_LIBC_ALL_FUNCS`（固定索引名）。
// MoonBit 侧照搬时把并集**手抄**成 libc 包的 `builtin_all`——于是同一事实有第四份
// 副本，且三份之间零对账。本闸把「三表一致」从注释里的承诺变成机判红线。
//
// 用法（**仓库根**）：
//   node scripts/moonbit/libc_single_source/main.mts            # 三表关系报告 + 判定
//   node scripts/moonbit/libc_single_source/main.mts -check     # 判定（CI 门禁用）
//   node scripts/moonbit/libc_single_source/main.mts --selftest # J9：注入差异必红
//
// 判据（规则见 rules.json）：
//   ① 四表各自无重复且非空（防「解析失败→空集→全绿」）
//   ② builtin_all == (host_names ∪ bytecode_names) - excluded_from_union
//   ③ |host_names ∩ bytecode_names| == expect.host_intersect_bytecode
//   ④ pure_names ⊆ host_names ∩ bytecode_names
//
// fail loud：源文件缺失或锚点找不到 → exit 2；断言不过 → exit 1。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

export const RULES_PATH = "scripts/moonbit/libc_single_source/rules.json";

export interface SourceSpec {
  file: string;
  anchor_start: string;
  anchor_end: string;
  kind: string;
}

export interface RulesDoc {
  schema: number;
  sources: Record<string, SourceSpec>;
  excluded_from_union: string[];
  expect: { host_intersect_bytecode: number };
}

export interface Table {
  name: string;
  names: string[];
  set: Set<string>;
  dupes: string[];
  srcPath: string;
}

const RE_STRING_LIT = /"([^"]+)"/g;
/** match_arms：`"name" => Some(HOST_X)`（生成物已把 `"a" | "b" =>` 别名展开成多臂）。 */
const RE_MATCH_ARM = /^[ \t]*"([^"]+)"[ \t]*=>[ \t]*Some\(/gm;
/** match_arms 的函数体结束启发式：下一个顶层 `fn `/`pub fn `。 */
const RE_NEXT_TOP_FN = /^(pub )?fn /m;

function fatal(msg: string): never {
  process.stderr.write(`libc_single_source: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

/** 字节序排序（Go sort.Strings 口径）。 */
function byteSort(xs: string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

function toSet(xs: string[]): Set<string> {
  return new Set(xs);
}

export function unionOf(a: Table, b: Table): string[] {
  return byteSort([...new Set([...a.set, ...b.set])]);
}

export function intersectOf(a: Table, b: Table): string[] {
  return byteSort([...a.set].filter((n) => b.set.has(n)));
}

function diff(xs: string[], exclude: Set<string>): string[] {
  return byteSort(xs.filter((x) => !exclude.has(x)));
}

function exclIn(u: string[], excl: string[]): string[] {
  const e = new Set(excl);
  return u.filter((n) => e.has(n));
}

/** sliceByAnchors：anchor_start 定位；anchor_end 为空时用「下一个顶层 fn」收尾。 */
export function sliceByAnchors(text: string, spec: SourceSpec): { body: string; error?: string } {
  const i = text.indexOf(spec.anchor_start);
  if (i < 0) return { body: "", error: `anchor_start 未命中: ${JSON.stringify(spec.anchor_start)}` };
  const rest = text.slice(i + spec.anchor_start.length);
  if (spec.anchor_end !== "" && spec.anchor_end !== undefined) {
    const j = rest.indexOf(spec.anchor_end);
    if (j < 0) return { body: "", error: `anchor_end 未命中: ${JSON.stringify(spec.anchor_end)}` };
    return { body: rest.slice(0, j) };
  }
  const m = RE_NEXT_TOP_FN.exec(rest);
  if (m !== null && m.index > 0) return { body: rest.slice(0, m.index) };
  return { body: rest };
}

export function mustTable(rd: RulesDoc, key: string): Table {
  const spec = rd.sources[key];
  if (spec === undefined) fatal(`规则缺 source 定义: ${key}`);
  let text: string;
  try {
    text = fs.readFileSync(abs(spec.file), "utf8");
  } catch (e) {
    fatal(`读源失败 ${spec.file}（须在仓库根运行）: ${e instanceof Error ? e.message : String(e)}`);
  }
  const sliced = sliceByAnchors(text, spec);
  if (sliced.error !== undefined) fatal(`源 ${spec.file} 的锚点定位失败: ${sliced.error}`);
  const body = sliced.body;
  const names: string[] = [];
  if (spec.kind === "string_list") {
    for (const m of body.matchAll(RE_STRING_LIT)) names.push(m[1] ?? "");
  } else if (spec.kind === "match_arms") {
    for (const m of body.matchAll(RE_MATCH_ARM)) names.push(m[1] ?? "");
  } else {
    fatal(`未知 kind: ${spec.kind}（source ${key}）`);
  }
  const counts = new Map<string, number>();
  for (const n of names) counts.set(n, (counts.get(n) ?? 0) + 1);
  const dupes = byteSort([...counts].filter(([, c]) => c > 1).map(([n, c]) => `${n}×${c}`));
  return { name: key, names, set: toSet(names), dupes, srcPath: spec.file };
}

/** 四项判据全过才是绿；返回 false 时打印全部差异（不早退）。 */
export function verdict(b: Table, h: Table, bc: Table, p: Table, rd: RulesDoc): boolean {
  let ok = true;
  for (const t of [b, h, bc, p]) {
    if (t.dupes.length > 0) {
      ok = false;
      process.stdout.write(`  [重复] ${t.name} 内有重复名 ${t.dupes.length} 个: ${t.dupes.join(", ")}\n`);
    }
  }
  for (const t of [b, h, bc, p]) {
    if (t.names.length === 0) {
      ok = false;
      process.stdout.write(`  [空集] ${t.name} 解析出 0 个名——锚点或源文件已变，拒绝判定\n`);
    }
  }
  if (!ok) return false;

  // ② builtin_all == (host ∪ bytecode) - excluded
  const u = unionOf(h, bc);
  const excl = toSet(rd.excluded_from_union ?? []);
  const want = u.filter((n) => !excl.has(n));
  const missing = diff(want, b.set);
  const extra = diff(byteSort([...b.set]), toSet(want));
  if (missing.length > 0 || extra.length > 0) {
    ok = false;
    process.stdout.write(
      `  [等式] builtin_all(${b.names.length}) != (host ∪ bytecode)(${u.length}) - excluded(${(rd.excluded_from_union ?? []).length})\n`,
    );
    if (missing.length > 0) {
      process.stdout.write(`    builtin_all 缺少（并集有而 libc 无）: ${missing.join(", ")}\n`);
    }
    if (extra.length > 0) {
      process.stdout.write(`    builtin_all 多出（libc 有而并集无）: ${extra.join(", ")}\n`);
    }
  }

  // ③ 交集计数
  const inter = intersectOf(h, bc);
  if (inter.length !== rd.expect.host_intersect_bytecode) {
    ok = false;
    process.stdout.write(
      `  [交集] |host ∩ bytecode| = ${inter.length}，期望 ${rd.expect.host_intersect_bytecode}（差集详情见下）\n`,
    );
  }
  // ④ PURE ⊆ 交集
  const interSet = toSet(inter);
  const pureOut = p.names.filter((n) => !interSet.has(n));
  if (pureOut.length > 0) {
    ok = false;
    process.stdout.write(`  [PURE] 下列 PURE 名不在 host ∩ bytecode 内: ${pureOut.join(", ")}\n`);
  }
  return ok;
}

export function report(b: Table, h: Table, bc: Table, p: Table, rd: RulesDoc): void {
  const inter = intersectOf(h, bc);
  const u = unionOf(h, bc);
  process.stdout.write("libc 三名单单源对账（S5 收尾批 · S6 前置）\n");
  for (const t of [b, h, bc, p]) {
    process.stdout.write(`  ${t.name.padEnd(16)} ${String(t.names.length).padStart(4)} 名  ← ${t.srcPath}\n`);
  }
  process.stdout.write(
    `  ${"host ∪ bytecode".padEnd(16)} ${String(u.length).padStart(4)} 名（|host ∩ bytecode|=${inter.length}，并集 - excluded(${(rd.excluded_from_union ?? []).length}) = ${u.length - exclIn(u, rd.excluded_from_union ?? []).length}）\n`,
  );
}

/** J9：先确认基线绿，再模拟「builtin_all 漏抄一名」，必须判红。 */
export function selftestRun(b: Table, h: Table, bc: Table, p: Table, rd: RulesDoc): number {
  if (!verdict(b, h, bc, p, rd)) {
    process.stdout.write("libc_single_source: selftest ABORT——基线不绿，注入后的红无法归因\n");
    return 2;
  }
  const u = unionOf(h, bc);
  if (u.length === 0) {
    process.stdout.write("libc_single_source: selftest ABORT——并集为空，无法构造注入\n");
    return 2;
  }
  const victim = u[0]!;
  const reduced = b.names.filter((n) => n !== victim);
  if (reduced.length === b.names.length) {
    process.stdout.write("libc_single_source: selftest ABORT——移除目标不在 builtin_all 中\n");
    return 2;
  }
  const injected: Table = { name: `${b.name}(injected: 抽掉 ${victim})`, names: reduced, set: toSet(reduced), dupes: [], srcPath: b.srcPath };
  process.stdout.write(`libc_single_source: selftest 已注入——builtin_all 抽掉 ${JSON.stringify(victim)}（模拟漏抄）\n`);
  if (verdict(injected, h, bc, p, rd)) {
    process.stdout.write("libc_single_source: selftest FAIL——注入后仍判绿，闸门失效\n");
    return 1;
  }
  process.stdout.write("libc_single_source: selftest PASS——注入差异被捕获（红），J9 证红成立\n");
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
  const builtin = mustTable(rd, "builtin_all");
  const host = mustTable(rd, "host_names");
  const bytecode = mustTable(rd, "bytecode_names");
  const pure = mustTable(rd, "pure_names");

  if (!check) report(builtin, host, bytecode, pure, rd);
  if (selftest) return selftestRun(builtin, host, bytecode, pure, rd);

  if (verdict(builtin, host, bytecode, pure, rd)) {
    process.stdout.write("libc_single_source: PASS（三表一致：builtin_all == (host ∪ bytecode) - excluded，交集与 PURE 子集均符合）\n");
    return 0;
  }
  process.stdout.write("libc_single_source: FAIL——三名单已分叉（详见上方差异）\n");
  return 1;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
