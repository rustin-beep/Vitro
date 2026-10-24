#!/usr/bin/env node
// wasmopt —— wasm-gc 产物构建后置优化驱动（Go→.mts 重写，refs #273；原 229 行，#120 批①）。
//
// 形态：本驱动（供给管理/校验/确定性自检/fail loud）+ node 执行器
// （wasmopt.mts——binaryen JS API；供给 = npm tarball 钉版本下载到
// tools/cache，sha256 校验，解包零三方依赖）。
// 特征位组合与等价性背书见 wasmopt.mts 头注；体积收益 = lean 产物
// 实测 -19.3% raw / -20.4% gzip（1872 帧逐字节一致在案）。
//
// 用法（仓库根）：
//
//	node scripts/wasmopt/main.mts <file.wasm>        # 原地优化（两次运行 digest 一致才落盘）
//	node scripts/wasmopt/main.mts -check <file.wasm> # 新鲜度校验：产物 digest == sidecar 标记
//
// fail loud：下载失败 / sha256 不符 / 解包缺件 / 优化产物非法（wasm magic 头）/
// 二次运行不确定（binaryen 确定性破坏）/ -check digest 失配或 sidecar 为空
// （-check 语义 = 指纹比对非 fixpoint——binaryen 非 fixpoint 在案）。
// 缓存：tools/cache/binaryen-<ver>/（gitignore——本地与 CI 同版本钉死，
// 冷缓存自动下载 ~23MB 一次）。
//
// 迁移口径（#292 批）：
//   - `-check` 路径与 Go 版**逐字同形**（含无 sidecar / 空 sidecar / digest 失配
//     三条 fail loud 文案），是 parity 的对拍面；
//   - 优化路径的收尾行含**耗时**（非确定），故不进对拍——等价性由「同输入两侧
//     各优化一次、产物 digest 与字节逐位比对」的单次证据背书；
//   - tar 解包用 zlib.gunzipSync + 手写 512 字节头解析（Go archive/tar 等价子集：
//     dir / reg / symlink(跳过) / GNU long name 'L'），解包后校验 package/index.js
//     存在——解析器漏形态即 fail loud，不静默半成品；
//   - 下载用全局 fetch（Node ≥ 18）替代 Go http.Get；错误文案按 .mts 习惯重写。
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const BINARYEN_VERSION = "132.0.0";
const BINARYEN_URL = `https://registry.npmjs.org/binaryen/-/binaryen-${BINARYEN_VERSION}.tgz`;
/** 钉死校验（2026-10-17 实下载取得；npm dist shasum1 互证）。 */
const BINARYEN_SHA256 = "6543555fb29bb92548f325c7dc18e9ab7dbb1215edda25993d1e3f71d85b8618";
const CACHE_ROOT = "tools/cache";

class ExitErr extends Error {
  readonly code: number;
  constructor(code: number) {
    super("exit");
    this.name = "ExitErr";
    this.code = code;
  }
}

/** Go `die`：stderr 前缀 `[wasmopt] FAIL: `，退出码 1。 */
export function die(msg: string): never {
  process.stderr.write("[wasmopt] FAIL: " + msg + "\n");
  throw new ExitErr(1);
}

const errText = (e: unknown): string => (e instanceof Error ? e.message : String(e));

const sha256Hex = (b: Uint8Array): string => crypto.createHash("sha256").update(b).digest("hex");

/** 读文件 → (sha256 hex, bytes)；读不到即 die。 */
export function fileSHA256(p: string): { digest: string; data: Buffer } {
  let data: Buffer;
  try {
    data = fs.readFileSync(p);
  } catch (e) {
    die(`读文件失败 ${p}: ${errText(e)}`);
  }
  return { digest: sha256Hex(data), data };
}

/** tar 头里的 NUL 结尾字符串字段。 */
function cstr(buf: Buffer, start: number, len: number): string {
  const slice = buf.subarray(start, start + len);
  const nul = slice.indexOf(0);
  return (nul >= 0 ? slice.subarray(0, nul) : slice).toString("utf8");
}

/**
 * tar.gz 解包（Go `archive/tar` 的等价子集）：目录 / 普通文件 / 符号链接（跳过）/
 * GNU long name（'L' 覆盖下一条目的名字）。路径穿越即拒（钉版本包形态固定，
 * 越界=供给异常 fail loud）。
 */
export function extractTarGz(data: Uint8Array, dest: string): void {
  const tar = zlib.gunzipSync(data);
  let off = 0;
  let longName: string | null = null;
  while (off + 512 <= tar.length) {
    const hdr = tar.subarray(off, off + 512);
    if (hdr.every((b) => b === 0)) break; // 全零块 = 归档结束
    const nameRaw = cstr(hdr, 0, 100);
    const size = Number.parseInt(cstr(hdr, 124, 12).trim() || "0", 8);
    const typeflag = String.fromCharCode(hdr[156] ?? 0);
    off += 512;
    const body = tar.subarray(off, off + size);
    off += Math.ceil(size / 512) * 512;

    if (typeflag === "L") {
      // GNU long name：本条目的 body 即下一条目的完整名字
      longName = body.toString("utf8").replace(/\0+$/, "");
      continue;
    }
    const name = longName ?? nameRaw;
    longName = null;
    if (typeflag === "x" || typeflag === "g") continue; // pax 元数据：本包不用，跳过
    if (name === "") continue;

    if (typeflag === "5") {
      fs.mkdirSync(path.join(dest, name.split("/").join(path.sep)), { recursive: true, mode: 0o755 });
      continue;
    }
    if (typeflag === "2") continue; // 符号链接（bin/ 脚本族）——执行器只用 index.js
    if (typeflag === "0" || typeflag === "\0" || typeflag === "7") {
      const p = path.join(dest, name.split("/").join(path.sep));
      // 路径穿越防护
      const rel = path.relative(dest, p);
      if (rel.startsWith("..") || path.isAbsolute(rel)) throw new Error(`tar 条目路径越界: ${name}`);
      fs.mkdirSync(path.dirname(p), { recursive: true, mode: 0o755 });
      fs.writeFileSync(p, body, { mode: 0o644 });
      continue;
    }
    // 其余类型（hardlink 等）本包形态不用——静默跳过与 Go 版默认分支等价
  }
}

/** 本地缓存就位（缺则下载 + sha256 + 解包）；返回 `.../package` 目录。 */
export async function ensureSupply(): Promise<string> {
  const dir = path.join(CACHE_ROOT, `binaryen-${BINARYEN_VERSION}`, "package");
  const entry = path.join(dir, "index.js");
  if (fs.existsSync(entry)) return dir;
  process.stdout.write(`[wasmopt] 冷缓存：下载 ${BINARYEN_URL}（钉版本 + sha256 校验）…\n`);
  let body: Buffer;
  try {
    const resp = await fetch(BINARYEN_URL);
    if (!resp.ok) die(`下载失败: HTTP ${resp.status}`);
    body = Buffer.from(await resp.arrayBuffer());
  } catch (e) {
    if (e instanceof ExitErr) throw e;
    die(`下载失败: ${errText(e)}`);
  }
  const got = sha256Hex(body);
  if (got !== BINARYEN_SHA256) {
    die(`sha256 不符：期望 ${BINARYEN_SHA256} 实得 ${got}（供给被篡改或 registry 漂移——更新须人工改钉值）`);
  }
  try {
    fs.mkdirSync(path.dirname(entry), { recursive: true, mode: 0o755 });
    extractTarGz(body, path.dirname(dir));
  } catch (e) {
    die(`解包失败: ${errText(e)}`);
  }
  if (!fs.existsSync(entry)) die(`解包后缺 ${entry}（包形态漂移）`);
  return dir;
}

/** 跑一次优化到临时产物，返回其 sha256。 */
export function runOnce(executor: string, supply: string, inPath: string, outPath: string): string {
  const r = spawnSync(process.execPath, [executor, inPath, outPath, supply], { stdio: ["ignore", "inherit", "inherit"] });
  if (r.error !== undefined) die(`优化执行失败: ${r.error.message}`);
  if ((r.status ?? -1) !== 0) die(`优化执行失败: exit status ${r.status}`);
  const { digest, data } = fileSHA256(outPath);
  // 产物 sanity：wasm magic（\0asm）——非法产物禁回写
  if (data.length < 4 || data[0] !== 0x00 || data[1] !== 0x61 || data[2] !== 0x73 || data[3] !== 0x6d) {
    die(`优化产物非法（非 wasm magic）：${outPath}`);
  }
  return digest;
}

/** Go `gzipSize`：zlib level 9 的压缩长度（同一实现口径）。 */
export function gzipSize(b: Uint8Array): number {
  return zlib.gzipSync(Buffer.from(b), { level: 9 }).length;
}

/** Go `time.Duration.Round(time.Millisecond)` 的近似文本形（优化路径收尾行用）。 */
function fmtDuration(ms: number): string {
  const rounded = Math.round(ms);
  if (rounded < 1000) return `${rounded}ms`;
  const s = rounded / 1000;
  return `${Number.isInteger(s) ? s.toFixed(0) : s.toFixed(3)}s`;
}

interface Opts {
  check: boolean;
  target: string;
}

export function parseArgs(argv: readonly string[]): Opts {
  let check = false;
  const positional: string[] = [];
  for (const a of argv) {
    if (a === "-check" || a === "--check") check = true;
    else if (a.startsWith("-")) die(`flag provided but not defined: ${a}`);
    else positional.push(a);
  }
  if (positional.length !== 1) die("用法: node scripts/wasmopt/main.mts [-check] <file.wasm>");
  return { check, target: positional[0] as string };
}

export async function runMain(argv: readonly string[]): Promise<number> {
  try {
    return await mainFlow(argv);
  } catch (e) {
    if (e instanceof ExitErr) return e.code;
    throw e;
  }
}

async function mainFlow(argv: readonly string[]): Promise<number> {
  const opts = parseArgs(argv);
  const target = path.resolve(opts.target);
  const supply = await ensureSupply();
  const executor = path.resolve("scripts/wasmopt/wasmopt.mts");

  const tmp1 = target + ".opt1.tmp";
  const tmp2 = target + ".opt2.tmp";

  const sidecar = target + ".wasmopt.sha256";
  if (opts.check) {
    let wantS: string;
    try {
      wantS = fs.readFileSync(sidecar, "utf8").replace(/\n+$/, "");
    } catch {
      die(`-check 无 sidecar（${sidecar}）——产物从未经本驱动优化`);
    }
    const got = fileSHA256(target).digest;
    // 空 sidecar 走 slice(0,12) 会得到空串——fail loud
    if (wantS === "") die(`-check sidecar 为空（${sidecar}）——先跑优化生成标记`);
    if (wantS !== got) {
      die(
        `-check digest 失配：现产物 ${got.slice(0, 12)} ≠ 标记 ${wantS.slice(0, 12)}——moon 重建已覆盖优化产物，重跑 node scripts/wasmopt/main.mts`,
      );
    }
    process.stdout.write(`[wasmopt] check OK：产物为优化终态（${got.slice(0, 12)}）\n`);
    return 0;
  }

  const orig = fileSHA256(target);
  if (fs.existsSync(sidecar) && fs.readFileSync(sidecar, "utf8").replace(/\n+$/, "") === orig.digest) {
    process.stdout.write(`[wasmopt] 产物已是优化终态（${orig.digest.slice(0, 12)}），跳过\n`);
    return 0;
  }
  const t0 = performance.now();
  try {
    const d1 = runOnce(executor, supply, target, tmp1);
    const d2 = runOnce(executor, supply, target, tmp2);
    if (d1 !== d2) {
      die(`确定性破坏：两次优化 digest 不一致（${d1.slice(0, 12)} ≠ ${d2.slice(0, 12)}）——binaryen 非确定或环境异常，拒落盘`);
    }
    // 落盘（Go 用 os.Rename(tmp1, target)：rename 即移动，tmp1 随之消失）
    fs.renameSync(tmp1, target);
    try {
      fs.writeFileSync(sidecar, d1 + "\n", "utf8");
    } catch (e) {
      die(`写 sidecar 失败: ${errText(e)}`);
    }
    const newData = fileSHA256(target).data;
    const elapsed = performance.now() - t0;
    process.stdout.write(
      `[wasmopt] ${path.basename(target)}: ${orig.data.length} -> ${newData.length} B（gzip ${gzipSize(orig.data)} -> ${gzipSize(newData)} B，-${(100 * (1 - newData.length / orig.data.length)).toFixed(1)}%）耗时 ${fmtDuration(elapsed)}\n`,
    );
    return 0;
  } finally {
    // Go 版 defer 语义：临时产物无论成败都清
    fs.rmSync(tmp1, { force: true });
    fs.rmSync(tmp2, { force: true });
  }
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  runMain(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e: unknown) => {
      process.stderr.write(`${e instanceof Error ? (e.stack ?? e.message) : String(e)}\n`);
      process.exit(1);
    },
  );
}
