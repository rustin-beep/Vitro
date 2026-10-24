#!/usr/bin/env node
// mbti_sync：MoonBit 接口面同步闸（Go→.mts 重写，refs #273；原 2026-09-22）。
//
// 断言「跑 moon info 前后 moonbit/**/pkg.generated.mbti 的内容集合逐字节不变」。
// 背景：.mbt（实现）与 .mbti（接口面）的一致性此前纯靠人工跑 moon info，已漏过
// 一次（libc 包 .mbti 少一个 type）。本闸把它变成机判。
//
// 判据：snapshot(moon info 前) == snapshot(moon info 后)；不等即脱节，列全部变化
// 文件后 exit 1。0 个 .mbti 亦红（拒绝空转判绿）。
//
// **自愈特性**：闸自己会跑 moon info ⇒ 判红的同时把 .mbti 同步到当前实现。第一次
// 跑红、紧接着再跑即绿——刻意的红→绿形态。CI 侧语义不变；本地侧省掉"手动跑
// moon info"这一步。
//
// 完备性断言（#43）：非 executable / foreign_library 的包必须存在 pkg.generated.mbti
// ——此前判据对「从未生成过」的包永远绿（gateway 因 canonical backend=wasm 被
// moon info 跳过，.mbti 从不存在而闸恒绿）。
//
// 用法：node scripts/moonbit/mbti_sync/main.mts [-check] [--selftest]
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

export const RULES_PATH = "scripts/moonbit/mbti_sync/rules.json";
const PKG_PREFIX = "vitro/engine/";

export interface RulesDoc {
  schema: number;
  module_dir: string;
  mbti_filename: string;
  moon_info_args: string[];
  skip_dirs: string[];
}

export interface DiffResult {
  added: string[];
  removed: string[];
  changed: string[];
}

function fatal(msg: string): never {
  process.stderr.write(`FATAL: ${msg}\n`);
  process.exit(2);
}

function abs(p: string): string {
  return path.isAbsolute(p) ? p : path.join(projectRoot(), p);
}

function byteSort(xs: string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
}

function sha256(b: Buffer): string {
  return crypto.createHash("sha256").update(b).digest("hex");
}

/** module 下全部 .mbti 的「仓库根相对路径（正斜杠）→ sha256」。 */
export function snapshot(root: string, rd: RulesDoc): Map<string, string> {
  const base = path.join(root, rd.module_dir);
  let st: fs.Stats;
  try {
    st = fs.statSync(abs(base));
  } catch (e) {
    fatal(`module_dir 不存在: ${base} (${e instanceof Error ? e.message : String(e)})`);
  }
  if (!st.isDirectory()) fatal(`module_dir 不存在: ${base} (not a directory)`);
  const skip = new Set(rd.skip_dirs ?? []);
  const out = new Map<string, string>();
  const walk = (dir: string): void => {
    for (const ent of fs.readdirSync(abs(dir), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const p = `${dir}/${ent.name}`;
      if (ent.isDirectory()) {
        if (skip.has(ent.name)) continue;
        walk(p);
        continue;
      }
      if (ent.name !== rd.mbti_filename) continue;
      let b: Buffer;
      try {
        b = fs.readFileSync(abs(p));
      } catch (e) {
        fatal(`读 ${p} 失败: ${e instanceof Error ? e.message : String(e)}`);
      }
      out.set(path.relative(root, abs(p)).split(path.sep).join("/"), sha256(b));
    }
  };
  walk(base);
  if (out.size === 0) fatal(`0 个 ${rd.mbti_filename}——闸门空转（module_dir / mbti_filename 配置有误），拒绝判绿`);
  return out;
}

export function diffSnapshots(before: Map<string, string>, after: Map<string, string>): DiffResult {
  const added: string[] = [];
  const removed: string[] = [];
  const changed: string[] = [];
  for (const [k, v] of after) {
    const old = before.get(k);
    if (old === undefined) added.push(k);
    else if (old !== v) changed.push(k);
  }
  for (const k of before.keys()) if (!after.has(k)) removed.push(k);
  return { added: byteSort(added), removed: byteSort(removed), changed: byteSort(changed) };
}

export function isEmpty(r: DiffResult): boolean {
  return r.added.length === 0 && r.removed.length === 0 && r.changed.length === 0;
}

export function total(r: DiffResult): number {
  return r.added.length + r.removed.length + r.changed.length;
}

function tail(s: string, n: number): string {
  const lines = s.replace(/\n+$/, "").split("\n");
  return lines.length <= n ? s : lines.slice(-n).join("\n");
}

export function runMoonInfo(root: string, rd: RulesDoc): void {
  if (!Array.isArray(rd.moon_info_args) || rd.moon_info_args.length === 0) fatal("moon_info_args 为空——拒绝空转");
  const [cmd, ...args] = rd.moon_info_args;
  const r = spawnSync(cmd!, args, { cwd: path.join(root, rd.module_dir), encoding: "utf8" });
  if (r.error !== undefined || r.status !== 0) {
    const why = r.error?.message ?? `exit ${r.status}`;
    fatal(`moon info 失败（${why}）：\n${tail(`${r.stdout ?? ""}${r.stderr ?? ""}`, 30)}`);
  }
}

/** 跑一次「快照 → moon info → 再快照 → 比对」。 */
export function check(root: string, rd: RulesDoc): { result: DiffResult; count: number } {
  const before = snapshot(root, rd);
  runMoonInfo(root, rd);
  const after = snapshot(root, rd);
  return { result: diffSnapshots(before, after), count: before.size };
}

export function report(r: DiffResult): void {
  if (r.added.length > 0) {
    process.stdout.write(`mbti_sync: 新增 ${r.added.length} 个接口面文件（只有跑 moon info 才生成 ⇒ 仓库里漏提交）：\n`);
    for (const f of r.added) process.stdout.write(`  + ${f}\n`);
  }
  if (r.removed.length > 0) {
    process.stdout.write(`mbti_sync: 消失 ${r.removed.length} 个接口面文件（包被删而 .mbti 未清，或 moon info 不再产出）：\n`);
    for (const f of r.removed) process.stdout.write(`  - ${f}\n`);
  }
  if (r.changed.length > 0) {
    process.stdout.write(`mbti_sync: ${r.changed.length} 个接口面与实现脱节（.mbt 改了 pub 面但没跑 moon info）：\n`);
    for (const f of r.changed) process.stdout.write(`  ~ ${f}\n`);
  }
}

/**
 * J9：向一个真实 .mbti 注入「脱节内容」，断言必红；finally 恢复。
 * 为何注入 .mbti 而非 .mbt 源：本闸自己跑 moon info，改源会被正常修复而不可归因；
 * 注入到生成物上，moon info 的重写本身就是「检测到脱节」的充分条件。
 */
export function selftest(root: string, rd: RulesDoc): number {
  const st = snapshot(root, rd);
  const target = byteSort([...st.keys()])[0];
  if (target === undefined) {
    process.stdout.write("mbti_sync: selftest ABORT——无可注入的 .mbti\n");
    return 2;
  }
  const absFile = abs(path.join(root, target));
  let orig: Buffer;
  try {
    orig = fs.readFileSync(absFile);
  } catch (e) {
    process.stdout.write(`mbti_sync: selftest ABORT——读 ${target} 失败: ${e instanceof Error ? e.message : String(e)}\n`);
    return 2;
  }
  let restored = false;
  const restore = (): void => {
    if (restored) return;
    try {
      fs.writeFileSync(absFile, orig);
    } catch (e) {
      process.stdout.write(`mbti_sync: selftest 严重——恢复 ${target} 失败: ${e instanceof Error ? e.message : String(e)}（工作区可能已脏）\n`);
    }
    restored = true;
  };
  try {
    fs.writeFileSync(absFile, Buffer.concat([orig, Buffer.from("\n// mbti_sync selftest probe\n")]));
    process.stdout.write(`mbti_sync: selftest 已向 ${target} 注入脱节内容（模拟手工改坏 / 未同步）\n`);
    const { result } = check(root, rd);
    restore(); // moon info 重写该文件后，恢复原内容即回到同步态
    if (isEmpty(result)) {
      process.stdout.write("mbti_sync: selftest FAIL——注入脱节内容后仍判绿，闸门失效\n");
      return 1;
    }
    process.stdout.write(`mbti_sync: selftest PASS——注入的脱节被捕获（判红 ${total(result)} 个文件），J9 证红成立\n`);
    return 0;
  } finally {
    restore();
  }
}

/** 完备性：moonbit/ 下非 executable / foreign_library 的包必须有 pkg.generated.mbti。 */
export function mbtiCompleteness(root: string, exempt: Map<string, string>): string[] {
  const base = path.join(root, "moonbit");
  const missing: string[] = [];
  const walk = (dir: string): void => {
    for (const ent of fs.readdirSync(abs(dir), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const p = `${dir}/${ent.name}`;
      if (ent.isDirectory()) {
        if (ent.name === "_build" || ent.name === ".mooncakes") continue;
        walk(p);
        continue;
      }
      if (ent.name !== "moon.pkg") continue;
      const relDir = path.relative(base, dir).split(path.sep).join("/");
      const pkgPath = PKG_PREFIX + relDir;
      if (exempt.has(pkgPath)) continue;
      let s: string;
      try {
        s = fs.readFileSync(abs(p), "utf8");
      } catch {
        continue;
      }
      if (s.includes('pkgtype(kind: "executable")') || s.includes('pkgtype(kind: "foreign_library")')) continue;
      if (!fs.existsSync(abs(`${dir}/pkg.generated.mbti`))) missing.push(`${pkgPath}（moon.pkg 无 .mbti 且不在豁免表）`);
    }
  };
  walk(base);
  return missing;
}

/** 结构性不可生成的包（#43 豁免，精确理由）。 */
export const MBTI_EXEMPT = new Map<string, string>([
  [
    "vitro/engine/gateway",
    "moon info 跳过：canonical backend=wasm 而该包 supported_targets=+wasm-gc+native 不含 wasm——mbti 无生成通道，#43 豁免裁定",
  ],
  [
    "vitro/engine/cmd/lib/cli",
    "同病（完备性断言首跑抓出）：supported_targets=native + canonical backend=wasm 被 moon info 跳过。注：fs 同为 native-only 却有 .mbti（d29a3470 手工生成入库）——两形态并存印证通道缺失而非按 target 判定",
  ],
  [
    "vitro/engine/cmd/lib/engine_direct",
    "同病（完备性断言 pin 修复首跑抓出）：supported_targets=+js+native 不含 canonical wasm——moon info 跳过无生成通道（main.js 退役批新包建时漏登，被 108fc42d 的 pin 语法错 Install Failed 掩盖至 .moonbit-version 修复首跑暴露）",
  ],
]);

export function loadRules(root: string): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(abs(path.join(root, RULES_PATH)), "utf8");
  } catch (e) {
    fatal(`读规则失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`解析规则失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (!rd.module_dir || !rd.mbti_filename) fatal("规则缺 module_dir / mbti_filename");
  return rd;
}

export function main(argv: string[]): number {
  let selftestMode = false;
  for (const a of argv) {
    if (a === "-check" || a === "--check") continue; // 与兄弟闸门调用形态一致，无独立语义
    if (a === "-selftest" || a === "--selftest") selftestMode = true;
    else {
      process.stderr.write(`mbti_sync: 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  const root = projectRoot();
  const rd = loadRules(root);
  if (selftestMode) return selftest(root, rd);

  const { result, count } = check(root, rd);

  const missing = mbtiCompleteness(root, MBTI_EXEMPT);
  if (missing.length > 0) {
    for (const m of missing) process.stdout.write("mbti_sync: [完备性] 缺接口面: " + m + "\n");
    fatal("非 executable/foreign_library 包缺 pkg.generated.mbti（从未生成——快照不变量对此恒绿；生成或登记豁免）");
  }

  if (isEmpty(result)) {
    process.stdout.write(`mbti_sync: PASS——${count} 个接口面文件与实现同步（moon info 零变化）+ 完备性豁免 ${MBTI_EXEMPT.size} 包\n`);
    return 0;
  }
  report(result);
  process.stdout.write("mbti_sync: FAIL——接口面与实现脱节；请跑 `cd moonbit && moon info` 并提交 .mbti 变更\n");
  return 1;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
