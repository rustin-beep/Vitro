#!/usr/bin/env node
// release_preflight —— 发布前置闸（ds 报告 2026-10-31 §4.1.1 七项缺口的机判化批③）。
//
// 用法（仓库根）：
//   node scripts/release_preflight/main.mts                          # 日常档（快：零网络零解压）
//   node scripts/release_preflight/main.mts --unzip-check            # 日常档 + 解压树 check（CI 跑——下游视角）
//   node scripts/release_preflight/main.mts --release                # 发版彩排档（人工/发版本机；隐含 --unzip-check）
//
// 背景：0.9.0 在架包被工具链升级打死（moonc ≥0.10.18 删 core/abort，包内
// time_travel 仍 import ⇒ 下游 moon add 后 build 必红）且发布物零工具链声明
// ——该缺陷形态在发布彩排里**没有任何闸能抓**（彩排只验 registry 投放与包
// 自身 check，没验「publish 视角健康」与「发布件非退化」）。本闸两档补面：
//
//  日常档（默认，CI 跑——**本闸进程零网络零 login**：不触 mooncakes API；
//  CI job 前置的 registry 刷新 `moon update` 属 job 依赖面而非本闸行为，
//  版本探针只读其落地的本地 index 文件。CI 无 moon login，dry-run 会 login
//  拦截〔2026-10-31 CI 实锤：Registry login is required〕；import 断供防线
//  由 moon check/moon test 的 Hygiene job 承担，本档增量 = 发布件面）：
//   1. `moon package` 产物非退化：zip >100KB 且 >400 文件——**模块目录被
//      .gitignore 忽略规则覆盖时** `moon package` 出 22 字节空 zip 且 rc=0
//      静默成功（报告 §4.1.1-3；审阅批 2026-10-31 勘正归因：与「是否 git
//      仓库」无关——仓库外无 git 目录打包正常〔实测 1.5MB 正常包〕，仓库内
//      未跟踪文件也入包，唯一致空因素是忽略覆盖。CI 恒在 checkout git 树
//      里跑，本闸在 CI 的可达形态 = 忽略规则误伤 moonbit/〔如误加 .gitignore
//      条目〕；发版机从被忽略目录打包的形态由 release 档同一闸段覆盖）；
//   2. 根级四件在位：LICENSE / README.md / README.mbt.md / moon.mod
//      （T5 发布验收四件，mooncakes 模块页渲染依赖）；
//   3. 版本状态探针（不判红）：moon.mod version vs 本地 registry index 尾行
//      （`~/.moon/registry/index/user/vitro/engine.index`，moon update 后在场）
//      ——同号 = 未 bump（发版前预期态）/ 异号 = 已 bump。
//
//  --release 档（发版彩排，发版本机跑——本机有 moon login）：
//   1. `moon publish --dry-run` 须 rc=0（版本已 bump 且 registry 无冲突
//      ——409 版本重复即红「先 bump」；Check passed 断言兜底）；
//   2. 日常档全部三件（package 非退化 + 根级四件 + 版本探针）；
//   3. **tag 指向校验**（审阅 v2 A8 批 refs #438，官方 x 仓 publish.yml 三段校验的
//      Vitro 对位）：tag 名由 moon.mod 派生 = `vitro-engine-<version>`（历史形态
//      vitro-engine-0.9.0/0.9.1 保持）；version 须 semver 三段；tag 不存在 = 绿
//      （playbook 后续人工打）；**tag 已存在则必须指向恰为 HEAD**，否则红——重发
//      同版本 tag 到别的 commit 会静默覆盖下游按 tag 溯源的语义（"never move it
//      to another commit"）；
//   4. 隐含 --unzip-check（见下）。
//
//  --unzip-check 档（CI 跑；审阅 v2 A8 批 refs #438，官方 x 仓 package.yml /
//  check.yml 双处布防的「moon package → 解压 → 对解压产物再 check」）：
//   零依赖手写解压（central directory + local header + zlib inflateRaw）到临时目录，
//   在解压树上 `moon check`——这是**下游消费者视角**（zip 内容 + registry 依赖解析），
//   与 Hygiene 的 workspace 视角 moon check 本质不同：0.9.0 断供形态（zip 清单完全
//   正常、坏的是内容——time_travel import 已删的 core/abort）只有这一层能拦。
//   实测（2026-11-02 worktree 5233ad65）：解压树裸 `moon check` 一次绿（112 tasks，
//   零旗标——R5d 预判的 MOON_IGNORE_PREBUILD/--no-mbti 在 Vitro 不需要，_gen.mbt 已
//   入包无 prebuild）；证红 = 删解压树 time_travel/checkpoint.mbt → Error [4024]×3 rc=1。
//   deny-warn 不开（包内 39 warnings 面未标定——先求红绿基线稳）。
//   **诚实登记（R5d 件③适配点 3）**：解压树 check 由 moon 解析 moon.mod deps
//   （moonbitlang/core 族）——缓存缺席时会拉**依赖包**，不触 vitro/engine 自身的
//   zip GET（反刷量约束的计数面是 vitro/engine 下载量，依赖包不计）；故本档不再
//   是「零网络」，与 CI job 前置的 moon update 同属 job 依赖面。裸日常档照旧零网络。
//
// 反刷量设计约束（用户拍板 2026-10-31，refs riantr 家 CI 刷量实锤）：本闸
// 全程**零 mooncakes zip GET**——日常档完全零网络（package 本地打包 + 本地
// index 探针），release 档的 dry-run 只打 publish 查重 API；「干净消费工程
// moon add + build」会产生真实 zip GET（下载计数 +1），**不自动化进 CI**
// ——人工步骤落在 vitro-release-playbook skill 的发版 checklist（发版当日
// 一次，真实语义下载）。
//
// 纪律：零第三方依赖；fail loud；禁静默 default；rc=0 绿 / 1 判红（闸判定
// 失败：退化/缺件/版本冲突/无 Check passed——可修复后重跑）/ 2 致命（环境
// 破坏：moon.mod 缺失、产物路径异常、moon package 自身失败——审阅批
// 2026-10-31 P3-2 落地：旧头注写 1/2 分流但实现全走 fatal(2)，rc=1 不可达）。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
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

/** zip 条目下限（实测 515 条〔2026-10-31 审阅批口径，不同树 515~520〕——
 * 阈值=绝对下限，余量约 22%：正当瘦身（拆包/文档出仓）越过即假红，调整须
 * 连坐 main.test.mts 阈值锚与本注释；环比口径（对拍跟踪条目数）挂账未做） */
export const ZIP_MIN_FILES = 400;
/** zip 字节下限（实测 ~1.5MB——阈值余量约 93%，同上连坐义务；退化 22 字节） */
export const ZIP_MIN_BYTES = 100 * 1024;

export function fatal(msg: string): never {
  process.stderr.write("release_preflight: " + msg + "\n");
  process.exit(2);
}

/** 判红出口（rc=1）：闸判定失败——可修复后重跑（bump/补件/治退化）。
 *  与 fatal（rc=2，环境破坏）分流——审阅批 2026-10-31 P3-2：旧实现全走
 *  fatal 致 rc=1 不可达，头注表失真。 */
export function fail(msg: string): never {
  process.stderr.write("release_preflight: " + msg + "\n");
  process.exit(1);
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

// ── tag 指向校验（件②，refs #438）──
export const TAG_PREFIX = "vitro-engine-";
const RE_SEMVER3 = /^\d+\.\d+\.\d+$/;

/** moon.mod version → 发布 tag 名；非 semver 三段 → null（版本号形态破坏，调用方 fatal）。 */
export function tagNameOf(version: string): string | null {
  return RE_SEMVER3.test(version) ? TAG_PREFIX + version : null;
}

export type TagVerdict = { ok: true; note: string } | { ok: false; reason: string };

/**
 * tag 指向判定（纯函数，git 查询在调用方）：
 *   tagCommit=null（tag 不存在）→ 绿（playbook 后续人工打）；
 *   tagCommit===head → 绿（重跑彩排，tag 未动）；
 *   否则红——tag 已存在且指向别的 commit，禁止移动。
 */
export function judgeTag(tag: string, tagCommit: string | null, head: string): TagVerdict {
  if (tagCommit === null) return { ok: true, note: `tag ${tag} 尚不存在（发版流程后续人工打，指向本 HEAD ${head.slice(0, 8)}）` };
  if (tagCommit === head) return { ok: true, note: `tag ${tag} 已存在且指向本 HEAD ${head.slice(0, 8)} ✓` };
  return {
    ok: false,
    reason: `tag ${tag} 已存在但指向 ${tagCommit.slice(0, 8)} ≠ HEAD ${head.slice(0, 8)}——禁止移动已发布 tag（下游按 tag 溯源）；同版本重发须先 bump version，或确认 HEAD 就是该 tag 所指`,
  };
}

// zip central directory 解析（零依赖替代 tar——Git Bash GNU tar 不读 zip、
// bsdtar 路径跨环境不可控；moon package 产物 <2MB 无 ZIP64 顾虑）。
const EOCD_SIG = 0x06054b50;
const CDE_SIG = 0x02014b50;

/** zip 字节 → 条目名数组（EOCD 反向扫描 + central directory 逐条读名）。 */
export function zipEntries(buf: Buffer): string[] {
  return zipRecords(buf).map((r) => r.name);
}

export interface ZipRecord {
  name: string;
  /** 0 = store / 8 = deflate（moon package 产物只见这两种） */
  method: number;
  compSize: number;
  uncompSize: number;
  crc32: number;
  localOffset: number;
}

const LFH_SIG = 0x04034b50;

/** zip 字节 → central directory 全记录（解压所需：方法/尺寸/本地头偏移）。 */
export function zipRecords(buf: Buffer): ZipRecord[] {
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
  const out: ZipRecord[] = [];
  for (let i = 0; i < count; i++) {
    if (off + 46 > buf.length || buf.readUInt32LE(off) !== CDE_SIG) {
      throw new Error(`zipEntries: central directory 条目 ${i} 签名错位（损坏？）`);
    }
    const nameLen = buf.readUInt16LE(off + 28);
    const extraLen = buf.readUInt16LE(off + 30);
    const commentLen = buf.readUInt16LE(off + 32);
    out.push({
      name: buf.subarray(off + 46, off + 46 + nameLen).toString("utf8"),
      method: buf.readUInt16LE(off + 10),
      crc32: buf.readUInt32LE(off + 16),
      compSize: buf.readUInt32LE(off + 20),
      uncompSize: buf.readUInt32LE(off + 24),
      localOffset: buf.readUInt32LE(off + 42),
    });
    off += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

/** 条目名安全判定（zip slip）：`..` 段 / 绝对路径 / 盘符 / 反斜杠 → 拒绝。 */
export function unsafeEntryName(name: string): boolean {
  if (name.includes("\\")) return true;
  if (path.posix.isAbsolute(name) || /^[A-Za-z]:/.test(name)) return true;
  return name.split("/").some((seg) => seg === "..");
}

/**
 * 零依赖解压到 dir（件③——外部 tar/unzip 跨环境不可控：Git Bash GNU tar 不读 zip、pwsh
 * Expand-Archive 只在 Windows 臂）。尺寸由 central directory 取（data descriptor 形态下
 * local header 的尺寸字段为 0）；解压后长度与 uncompSize 不等即 throw（fail loud）。
 * 返回写出的文件数（目录条目不计）。
 */
export function unzipTo(buf: Buffer, dir: string): number {
  let files = 0;
  for (const r of zipRecords(buf)) {
    if (unsafeEntryName(r.name)) throw new Error(`unzipTo: 拒绝不安全条目名 ${JSON.stringify(r.name)}`);
    const dest = path.join(dir, r.name);
    if (r.name.endsWith("/")) {
      fs.mkdirSync(dest, { recursive: true });
      continue;
    }
    const lh = r.localOffset;
    if (lh + 30 > buf.length || buf.readUInt32LE(lh) !== LFH_SIG) throw new Error(`unzipTo: ${r.name} local header 签名错位`);
    const dataStart = lh + 30 + buf.readUInt16LE(lh + 26) + buf.readUInt16LE(lh + 28);
    const comp = buf.subarray(dataStart, dataStart + r.compSize);
    let data: Buffer;
    if (r.method === 0) data = comp;
    else if (r.method === 8) data = zlib.inflateRawSync(comp);
    else throw new Error(`unzipTo: ${r.name} 压缩方法 ${r.method} 不支持（只认 store/deflate）`);
    if (data.length !== r.uncompSize) throw new Error(`unzipTo: ${r.name} 解压长度 ${data.length} ≠ 声明 ${r.uncompSize}`);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, data);
    files++;
  }
  return files;
}

/** zip 清单 → 非空闸判定（大小由调用方 stat）。 */
export function verdictFromListing(entries: readonly string[], size: number): ZipVerdict {
  const roots = new Set(entries.map((e) => e.split("/")[0] ?? ""));
  const missingRoot = ROOT_FILES.filter((f) => !roots.has(f));
  return { size, fileCount: entries.length, missingRoot: [...missingRoot] };
}

/** package 闸判定（审阅批 2026-10-31 P2-3 抽取——主流程判红分支零自动锚，
 *  纯函数化供 node:test 三档锚）。判红优先序：退化（条数/字节双阈值，附
 *  缺件清单辅助定位——退化常伴根级件全缺，P3-4：3 条小包报「退化且缺
 *  X,Y」比单报缺件归因准）→ 缺件（条数/字节正常但根级件缺）。 */
export type PkgGateFailure = { kind: "degenerate" | "missing-root"; reason: string };

export function judgePackage(zv: ZipVerdict): PkgGateFailure | null {
  if (zv.fileCount < ZIP_MIN_FILES || zv.size < ZIP_MIN_BYTES) {
    const extra = zv.missingRoot.length > 0 ? `；且缺根级件 ${zv.missingRoot.join(", ")}（退化形态常伴根级件全缺——先治退化）` : "";
    return {
      kind: "degenerate",
      reason: `package 产物疑似退化空包：${zv.fileCount} 条 / ${zv.size}B（阈值 ≥${ZIP_MIN_FILES} 条 / ≥${ZIP_MIN_BYTES}B；模块目录被 .gitignore 覆盖时 22 字节空 zip rc=0 静默成功实锤形态${extra}）`,
    };
  }
  if (zv.missingRoot.length > 0) {
    return {
      kind: "missing-root",
      reason: `package 产物缺根级件：${zv.missingRoot.join(", ")}（T5 验收四件）`,
    };
  }
  return null;
}

function run(name: string, args: readonly string[], cwd?: string): { code: number; out: string } {
  const r = spawnSync(name, args, { cwd, encoding: "buffer", maxBuffer: 64 * 1024 * 1024 });
  const out = Buffer.concat([r.stdout ?? Buffer.alloc(0), r.stderr ?? Buffer.alloc(0)]).toString("utf8");
  return { code: r.status ?? -1, out };
}

function main(): void {
  const release = process.argv.includes("--release") || process.argv.includes("-release");
  const unzipCheck = release || process.argv.includes("--unzip-check");
  const root = path.resolve(import.meta.dirname, "..", "..");
  const moonbit = path.join(root, "moonbit");

  if (!fs.existsSync(path.join(moonbit, "moon.mod"))) fatal(`moonbit/moon.mod 不存在（cwd 语义破坏）`);
  const modVer = moonModVersion(fs.readFileSync(path.join(moonbit, "moon.mod"), "utf8"));
  if (modVer === null) fatal("moon.mod 无 version 字段——无法对拍 bump 状态");

  process.stdout.write(`release_preflight: 档位=${release ? "release（发版彩排）" : unzipCheck ? "daily+unzip-check（CI·下游视角）" : "daily（快·零网络）"} · 待发版本=${modVer}\n`);

  // ── release 档前置①：dry-run 须 rc=0（本机有 moon login；CI 无登录会
  //    「Registry login is required」拦——故 dry-run 只进 release 档）──
  if (release) {
    const dry = run("moon", ["publish", "--dry-run"], moonbit);
    const v = parseDryRun(dry.out);
    if (dry.code !== 0) {
      if (v.versionConflict !== null) {
        fail(`版本 ${v.version} 与在架重复——先 bump moon.mod version（发布流程 T5：修复发布 patch / 新增面 minor）`);
      }
      fatal(`dry-run rc=${dry.code}（login/网络/构建失败——发版本机须 moon login 后重跑）：\n${dry.out.slice(-1200)}`);
    }
    if (!v.checkPassed) fail(`dry-run rc=0 但无 "Check passed"（异常形态）：\n${dry.out.slice(-600)}`);
    process.stdout.write(`release_preflight: dry-run rc=0 · Check passed ✓（registry 无冲突）\n`);

    // ── release 档前置②：tag 指向校验（件②，refs #438）──
    const tag = tagNameOf(modVer);
    if (tag === null) fatal(`moon.mod version "${modVer}" 非 semver 三段——tag 派生形态破坏`);
    const head = run("git", ["rev-parse", "HEAD"], root);
    if (head.code !== 0) fatal(`git rev-parse HEAD rc=${head.code}：${head.out.slice(-300)}`);
    const tc = run("git", ["rev-parse", "--verify", "-q", `refs/tags/${tag}^{commit}`], root);
    const tv = judgeTag(tag, tc.code === 0 ? tc.out.trim() : null, head.out.trim());
    if (!tv.ok) fail(tv.reason);
    process.stdout.write(`release_preflight: ${tv.note}\n`);
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
  const gate = judgePackage(zv);
  if (gate !== null) fail(gate.reason);
  process.stdout.write(`release_preflight: package ✓ ${zv.fileCount} 条 / ${Math.round(zv.size / 1024)}KB · 根级四件在位\n`);

  // ── 解压树 check（件③，refs #438——下游消费者视角；--unzip-check / --release 档）──
  if (unzipCheck) {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-pkgcheck-"));
    let written: number;
    try {
      written = unzipTo(fs.readFileSync(zipPath), tmpDir);
    } catch (e) {
      fatal(`package 产物解压失败（${(e as Error).message}）：${zipPath}`);
    }
    if (!fs.existsSync(path.join(tmpDir, "moon.mod"))) fatal(`解压树无 moon.mod（${written} 文件写出）——zip 布局与预期（平铺根）不符`);
    const t0 = Date.now();
    const chk = run("moon", ["check"], tmpDir);
    const secs = ((Date.now() - t0) / 1000).toFixed(1);
    fs.rmSync(tmpDir, { recursive: true, force: true });
    if (chk.code !== 0) {
      fail(`解压树 moon check rc=${chk.code}（下游 moon add 后 build 必红的 0.9.0 断供同族形态——zip 内容/依赖面坏）：\n${chk.out.slice(-1500)}`);
    }
    process.stdout.write(`release_preflight: 解压树 check ✓ ${written} 文件 · moon check rc=0（${secs}s，下游视角）\n`);
  }

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
      : unzipCheck
        ? "release_preflight: PASS（日常档 + 解压树 check：清单面 + 构建面 + 版本探针三面齐）\n"
        : "release_preflight: PASS（日常档·快）\n",
  );
}

// 直接执行时跑 main；被 import（node:test）时不跑。
if (process.argv[1] !== undefined && import.meta.filename === path.resolve(process.argv[1])) {
  main();
}
