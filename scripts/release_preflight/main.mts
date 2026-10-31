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
//  日常档（默认，CI 跑，**零网络**——CI 无 moon login，dry-run 会 login 拦截
//  〔2026-10-31 CI 实锤：Registry login is required〕；import 断供防线由
//  moon check/moon test 的 Hygiene job 承担，本档增量 = 发布件面）：
//   1. `moon package` 产物非退化：zip >100KB 且 >400 文件——非 git 管理面
//      `moon package` 曾实测 22 字节空 zip 且 rc=0 静默成功（报告 §4.1.1-3）；
//   2. 根级四件在位：LICENSE / README.md / README.mbt.md / moon.mod
//      （T5 发布验收四件，mooncakes 模块页渲染依赖）；
//   3. 版本状态探针（不判红）：moon.mod version vs 本地 registry index 尾行
//      （`~/.moon/registry/index/user/vitro/engine.index`，moon update 后在场）
//      ——同号 = 未 bump（发版前预期态）/ 异号 = 已 bump。
//
//  --release 档（发版彩排，发版本机跑——本机有 moon login）：
//   1. `moon publish --dry-run` 须 rc=0（版本已 bump 且 registry 无冲突
//      ——409 版本重复即红「先 bump」；Check passed 断言兜底）；
//   2. 日常档全部三件（package 非退化 + 根级四件 + 版本探针）。
//
// 反刷量设计约束（用户拍板 2026-10-31，refs riantr 家 CI 刷量实锤）：本闸
// 全程**零 mooncakes zip GET**——日常档完全零网络（package 本地打包 + 本地
// index 探针），release 档的 dry-run 只打 publish 查重 API；「干净消费工程
// moon add + build」会产生真实 zip GET（下载计数 +1），**不自动化进 CI**
// ——人工步骤落在 vitro-release-playbook skill 的发版 checklist（发版当日
// 一次，真实语义下载）。
//
// 纪律：零第三方依赖；fail loud；禁静默 default；rc=0 绿 / 1 判红 / 2 致命。
import fs from "node:fs";
import os from "node:os";
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

/** registry index JSONL → 在架最新版本（尾行 version；空/坏 → null）。 */
export function latestPublishedVersion(jsonl: string): string | null {
  const lines = jsonl.split(/\r?\n/).filter((l) => l.trim().length > 0);
  const last = lines[lines.length - 1];
  if (last === undefined) return null;
  try {
    const v = (JSON.parse(last) as { version?: unknown }).version;
    return typeof v === "string" ? v : null;
  } catch {
    return null;
  }
}

// zip central directory 解析（零依赖替代 tar——Git Bash GNU tar 不读 zip、
// bsdtar 路径跨环境不可控；moon package 产物 <2MB 无 ZIP64 顾虑）。
const EOCD_SIG = 0x06054b50;
const CDE_SIG = 0x02014b50;

/** zip 字节 → 条目名数组（EOCD 反向扫描 + central directory 逐条读名）。 */
export function zipEntries(buf: Buffer): string[] {
  // EOCD（22B 定长尾）在最尾部 64KB 内——注释段最长 65535
  const scanStart = Math.max(0, buf.length - 66_000);
  let eocd = -1;
  for (let i = buf.length - 22; i >= scanStart; i--) {
    if (buf.readUInt32LE(i) === EOCD_SIG) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error("zipEntries: EOCD 签名未找到（非 zip 或损坏）");
  const count = buf.readUInt16LE(eocd + 10);
  let off = buf.readUInt32LE(eocd + 16);
  const names: string[] = [];
  for (let i = 0; i < count; i++) {
    if (off + 46 > buf.length || buf.readUInt32LE(off) !== CDE_SIG) {
      throw new Error(`zipEntries: central directory 条目 ${i} 签名错位（损坏？）`);
    }
    const nameLen = buf.readUInt16LE(off + 28);
    const extraLen = buf.readUInt16LE(off + 30);
    const commentLen = buf.readUInt16LE(off + 32);
    names.push(buf.subarray(off + 46, off + 46 + nameLen).toString("utf8"));
    off += 46 + nameLen + extraLen + commentLen;
  }
  return names;
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

  process.stdout.write(`release_preflight: 档位=${release ? "release（发版彩排）" : "daily（CI 日常·零网络）"} · 待发版本=${modVer}\n`);

  // ── release 档前置：dry-run 须 rc=0（本机有 moon login；CI 无登录会
  //    「Registry login is required」拦——故 dry-run 只进 release 档）──
  if (release) {
    const dry = run("moon", ["publish", "--dry-run"], moonbit);
    const v = parseDryRun(dry.out);
    if (dry.code !== 0) {
      fatal(
        v.versionConflict !== null
          ? `版本 ${v.version} 与在架重复——先 bump moon.mod version（发布流程 T5：修复发布 patch / 新增面 minor）`
          : `dry-run rc=${dry.code}（login/网络/构建失败——发版本机须 moon login 后重跑）：\n${dry.out.slice(-1200)}`,
      );
    }
    if (!v.checkPassed) fatal(`dry-run rc=0 但无 "Check passed"（异常形态）：\n${dry.out.slice(-600)}`);
    process.stdout.write(`release_preflight: dry-run rc=0 · Check passed ✓（registry 无冲突）\n`);
  }

  // ── package 非退化闸（两档共用，零网络）──
  const pkg = run("moon", ["package"], moonbit);
  if (pkg.code !== 0) fatal(`moon package rc=${pkg.code}：\n${pkg.out.slice(-800)}`);
  const zipMatch = /Package to (\S+)/.exec(pkg.out);
  if (zipMatch === null) fatal(`moon package 输出无产物路径：\n${pkg.out.slice(-400)}`);
  const zipPath = zipMatch[1]!.replace(/^\\\\\?\\/, "");
  if (!fs.existsSync(zipPath)) fatal(`package 产物不存在：${zipPath}`);
  const size = fs.statSync(zipPath).size;
  // 条目清单走 node 手写 zip central directory 解析（零依赖；外部 tar
  // 跨环境不可控——Git Bash GNU tar 不读 zip、绝对路径盘符被当远程主机）
  let entries: string[];
  try {
    entries = zipEntries(fs.readFileSync(zipPath));
  } catch (e) {
    fatal(`package 产物 zip 不可解析（${(e as Error).message}）：${zipPath}`);
  }
  const zv = verdictFromListing(entries, size);
  if (zv.fileCount < ZIP_MIN_FILES || zv.size < ZIP_MIN_BYTES) {
    fatal(`package 产物疑似退化空包：${zv.fileCount} 条 / ${zv.size}B（阈值 ≥${ZIP_MIN_FILES} 条 / ≥${ZIP_MIN_BYTES}B；非 git 管理面 22 字节空 zip 实锤形态）`);
  }
  if (zv.missingRoot.length > 0) fatal(`package 产物缺根级件：${zv.missingRoot.join(", ")}（T5 验收四件）`);
  process.stdout.write(`release_preflight: package ✓ ${zv.fileCount} 条 / ${Math.round(zv.size / 1024)}KB · 根级四件在位\n`);

  // ── 版本状态探针（不判红）：moon.mod vs 本地 registry index 尾行 ──
  const idx = path.join(os.homedir(), ".moon", "registry", "index", "user", "vitro", "engine.index");
  if (fs.existsSync(idx)) {
    const pub = latestPublishedVersion(fs.readFileSync(idx, "utf8"));
    if (pub === null) {
      process.stdout.write("release_preflight: 版本探针 · index 尾行不可解析（moon update 后重试）\n");
    } else if (pub === modVer) {
      process.stdout.write(`release_preflight: 版本探针 · ${modVer} == 在架 ${pub}（未 bump——发版前预期态，release 档 dry-run 将 409）\n`);
    } else {
      process.stdout.write(`release_preflight: 版本探针 · ${modVer} ≠ 在架 ${pub}（已 bump 形态——release 档可验 registry 冲突）\n`);
    }
  } else {
    process.stdout.write("release_preflight: 版本探针 · 本地 index 缺席（先 moon update；探针跳过不判红）\n");
  }

  process.stdout.write(
    release
      ? "release_preflight: PASS（release 档）——干净消费验收（moon add + 双目标 build，真实 zip GET）按 playbook 人工执行，不进 CI（反刷量约束）\n"
      : "release_preflight: PASS（日常档）\n",
  );
}

// 直接执行时跑 main；被 import（node:test）时不跑。
if (process.argv[1] !== undefined && import.meta.filename === path.resolve(process.argv[1])) {
  main();
}
