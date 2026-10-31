#!/usr/bin/env node
// release_preflight —— 发布前置闸（ds 报告 2026-10-31 §4.1.1 七项缺口的机判化批③）。
//
// 用法（仓库根）：
//   node scripts/release_preflight/main.mts            # 日常档（CI 跑）
//   node scripts/release_preflight/main.mts --release  # 发版彩排档（人工/dispatch）
//
// 背景：0.9.0 在架包被工具链升级打死（moonc ≥0.10.18 删 core/abort，包内
// time_travel 仍 import ⇒ 下游 moon add 后 build 必红）且发布物零工具链声明
// ——该缺陷形态在发布彩排里**没有任何闸能抓**（彩排只验 registry 投放与包
// 自身 check，没验「publish 视角健康」与「发布件非退化」）。本闸两档补面：
//
//  日常档（默认）：
//   1. `moon publish --dry-run`（cwd=moonbit/）断言输出含 "Check passed"
//      ——缺失即红（抓 import 断供 / publish 视角构建红——0.9.0 型防线）；
//   2. 版本重复 409（「is duplicated with an existing version」）不红，
//      报「版本未 bump（发版预期态）」提示——兼任 bump 状态探针；
//   3. 其余失败（无 Check passed 且无 409——网络/未知构建红）fail loud。
//
//  --release 档（发版彩排）：
//   1. dry-run 须 rc=0（版本已 bump 且 registry 无冲突——409 即红，先 bump）；
//   2. `moon package` 产物非退化：zip >100KB 且 >400 文件——非 git 管理面
//      `moon package` 曾实测 22 字节空 zip 且 rc=0 静默成功（报告 §4.1.1-3）；
//   3. 根级四件在位：LICENSE / README.md / README.mbt.md / moon.mod
//      （T5 发布验收四件，mooncakes 模块页渲染依赖）。
//
// 反刷量设计约束（用户拍板 2026-10-31，refs riantr 家 CI 刷量实锤）：本闸
// 全程**零 mooncakes zip GET**——dry-run 只打 publish 查重 API（版本重复
// 409），package 是本地打包；「干净消费工程 moon add + build」会产生真实
// zip GET（下载计数 +1），**不自动化进 CI**——人工步骤落在 vitro-release-
// playbook skill 的发版 checklist（发版当日一次，真实语义下载）。
//
// 纪律：零第三方依赖；fail loud；禁静默 default；rc=0 绿 / 1 判红 / 2 致命。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

export type DryRunVerdict = {
  /** moon publish --dry-run 输出里 "Check passed" 在场（publish 视角构建健康） */
  checkPassed: boolean;
  /** 版本与在架重复（409 形态）——日常档不红（未 bump 预期态），release 档红 */
  versionConflict: string | null;
  /** 从输出提取的待发版本号（供提示行） */
  version: string | null;
};

export type ZipVerdict = {
  size: number;
  fileCount: number;
  /** 根级四件缺哪些（zip 清单首段无目录前缀的条目） */
  missingRoot: string[];
};

const ROOT_FILES = ["LICENSE", "README.md", "README.mbt.md", "moon.mod"] as const;

/** zip 条目下限（git 管理面实测 520 条目；非 git 面退化 22 字节/0 条目） */
export const ZIP_MIN_FILES = 400;
/** zip 字节下限（git 管理面实测 ~1.5MB；退化 22 字节） */
export const ZIP_MIN_BYTES = 100 * 1024;

export function fatal(msg: string): never {
  process.stderr.write("release_preflight: " + msg + "\n");
  process.exit(2);
}

/** moon.mod 文本 → version 字段（TOML 裸键，容忍注释/引号）。 */
export function moonModVersion(text: string): string | null {
  const m = /^version\s*=\s*"([^"]+)"/m.exec(text);
  return m?.[1] ?? null;
}

/** dry-run 合并输出 → 判定（样本来自 2026-10-31 master 实测）。 */
export function parseDryRun(out: string): DryRunVerdict {
  const checkPassed = out.includes("Check passed");
  // 形态：Server status: 409 Conflict, detail: Version Error: The version you
  // are attempting to upload (0.9.0) is duplicated with an existing version
  const m = /is duplicated with an existing version \(([^)]+)\)/.exec(out);
  const vm = /attempting to upload \(([^)]+)\)/.exec(out);
  return {
    checkPassed,
    versionConflict: m?.[1] ?? null,
    version: vm?.[1] ?? null,
  };
}

/** `tar -tf` 清单文本 → 条目数组（CRLF 归一；空行剔除）。 */
export function parseZipListing(text: string): string[] {
  return text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
}

/** zip 清单 → 非空闸判定（大小由调用方 stat）。 */
export function verdictFromListing(entries: readonly string[], size: number): ZipVerdict {
  const roots = new Set(entries.map((e) => e.split("/")[0] ?? ""));
  const missingRoot = ROOT_FILES.filter((f) => !roots.has(f));
  return { size, fileCount: entries.length, missingRoot: [...missingRoot] };
}

function run(name: string, args: readonly string[], cwd?: string): { code: number; out: string } {
  const r = spawnSync(name, args, { cwd, encoding: "buffer", maxBuffer: 64 * 1024 * 1024 });
  const out = Buffer.concat([r.stdout ?? Buffer.alloc(0), r.stderr ?? Buffer.alloc(0)]).toString("utf8");
  return { code: r.status ?? -1, out };
}

function main(): void {
  const release = process.argv.includes("--release") || process.argv.includes("-release");
  const root = path.resolve(import.meta.dirname, "..", "..");
  const moonbit = path.join(root, "moonbit");

  if (!fs.existsSync(path.join(moonbit, "moon.mod"))) fatal(`moonbit/moon.mod 不存在（cwd 语义破坏）`);
  const modVer = moonModVersion(fs.readFileSync(path.join(moonbit, "moon.mod"), "utf8"));
  if (modVer === null) fatal("moon.mod 无 version 字段——无法对拍 bump 状态");

  process.stdout.write(`release_preflight: 档位=${release ? "release（发版彩排）" : "daily（CI 日常）"} · 待发版本=${modVer}\n`);

  // ── 1. dry-run（两档共用；release 档要求 rc=0）──
  const dry = run("moon", ["publish", "--dry-run"], moonbit);
  const v = parseDryRun(dry.out);
  if (!release) {
    // 日常档三态：健康+未 bump（409，预期）/ 健康+已 bump / 不健康（红）
    if (!v.checkPassed) {
      fatal(
        v.versionConflict !== null
          ? `dry-run 未过 Check 且版本重复之外另有失败（异常组合）：\n${dry.out.slice(-1200)}`
          : `dry-run 无 "Check passed" 且非版本重复——publish 视角构建红（0.9.0 型断供防线）：\n${dry.out.slice(-1200)}`,
      );
    }
    if (v.versionConflict === null && dry.code !== 0) {
      fatal(`dry-run Check passed 但 rc=${dry.code}（非 409 形态的未知失败）：\n${dry.out.slice(-600)}`);
    }
    process.stdout.write(
      v.versionConflict !== null
        ? `release_preflight: Check passed ✓ · 版本 ${v.version} 与在架重复（未 bump——发版前预期态，release 档将红）\n`
        : `release_preflight: Check passed ✓ · 版本 ${v.version}（registry 无冲突——已 bump 形态）\n`,
    );
    process.stdout.write("release_preflight: PASS（日常档）\n");
    return;
  }

  // ── release 档 ──
  if (dry.code !== 0) {
    fatal(
      v.versionConflict !== null
        ? `版本 ${v.version} 与在架重复——先 bump moon.mod version（发布流程 T5：修复发布 patch / 新增面 minor）`
        : `dry-run rc=${dry.code}：\n${dry.out.slice(-1200)}`,
    );
  }
  process.stdout.write(`release_preflight: dry-run rc=0 ✓（版本 ${v.version} registry 无冲突）\n`);

  // ── 2. moon package 非退化闸 ──
  const pkg = run("moon", ["package"], moonbit);
  if (pkg.code !== 0) fatal(`moon package rc=${pkg.code}：\n${pkg.out.slice(-800)}`);
  const zipMatch = /Package to (\S+)/.exec(pkg.out);
  if (zipMatch === null) fatal(`moon package 输出无产物路径：\n${pkg.out.slice(-400)}`);
  const zipPath = zipMatch[1]!.replace(/^\\\\\?\\/, "");
  if (!fs.existsSync(zipPath)) fatal(`package 产物不存在：${zipPath}`);
  const size = fs.statSync(zipPath).size;
  // bsdtar（Windows 10+ 自带）列 zip 清单；Git Bash tar 同源
  const list = run("tar", ["-tf", zipPath]);
  if (list.code !== 0) fatal(`tar -tf 失败（zip 损坏？）：\n${list.out.slice(-400)}`);
  const zv = verdictFromListing(parseZipListing(list.out), size);
  if (zv.fileCount < ZIP_MIN_FILES || zv.size < ZIP_MIN_BYTES) {
    fatal(`package 产物疑似退化空包：${zv.fileCount} 条 / ${zv.size}B（阈值 ≥${ZIP_MIN_FILES} 条 / ≥${ZIP_MIN_BYTES}B；非 git 管理面 22 字节空 zip 实锤形态）`);
  }
  if (zv.missingRoot.length > 0) fatal(`package 产物缺根级件：${zv.missingRoot.join(", ")}（T5 验收四件）`);
  process.stdout.write(`release_preflight: package ✓ ${zv.fileCount} 条 / ${Math.round(zv.size / 1024)}KB · 根级四件在位\n`);
  process.stdout.write("release_preflight: PASS（release 档）——干净消费验收（moon add + build，真实 zip GET）按 playbook 人工执行，不进 CI（反刷量约束）\n");
}

// 直接执行时跑 main；被 import（node:test）时不跑。
if (process.argv[1] !== undefined && import.meta.filename === path.resolve(process.argv[1])) {
  main();
}
