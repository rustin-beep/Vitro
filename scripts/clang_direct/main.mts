// clang_direct：§7.1 层 2 直拍防线（#273 存量 Go 重写批 2026-10-25；原
// main.go，行为锚 = 双跑对拍 + known 台账防腐化）。真值源 = Clang 本尊
// （非 Rust oracle）：编译并运行语料得 golden，与 MoonBit cmd/run 的
// stdout + 返回码比对。与 vm_diff 的分工——
//
//	vm_diff      = 引擎 vs Rust oracle（同构对拍，抓迁移偏差）；
//	clang_direct = 引擎 vs Clang（真值直拍，抓两侧共同偏差——oracle 本身
//	               错而 Clang 对的形态只有本防线能抓）。
//
// Clang 侧口径（照搬 shadow_verify）：
//   - 编译参数 clangCompileArgs 同款（-Wno-implicit-function-declaration +
//     非 Windows 加 -lm）；
//   - 编译失败/环境异常重试 3 次（指数退避 1s/2s/4s；程序自身 exit != 0
//     是确定性行为不重试）；瞬态异常（超时/启动失败）不落缓存；
//   - 编译产物 per-case 唯一命名 + 用例隔离目录（Windows 同名 exe 映像竞态）；
//   - 结果缓存 .clang_cache_cd/（key = 源码+stdin+clang 版本+参数，schema
//     前缀 cd3；stdout 走 base64 字节保真存储）。
//
// MoonBit 侧口径（照搬 vm_diff）：
//   - cmd/run exe 预编译直跑 + 新鲜度门禁（internal/freshness.mts 单源）；
//   - stdout 提取：剥 `// EXIT N` / `// TRAP` / `// COMPILE-ERROR` 等标记行；
//   - 两侧对称原样字节比对（latin1Fold 已随 #66 退役——落盘 UTF-8 直通）。
//
// verdict：SAME（含双侧编译失败等价）/ DIFF-known（known_direct.json，
// case+digest 锁定，digest 漂移降级红防白名单腐化；条目转绿即红逼移除）/
// DIFF（红）。
//
// 用法：node scripts/clang_direct/main.mts [--sample N | --corpus dir | --cases f1.c,...] [--jobs N]
//
//	（默认全量 8 语料目录；--jobs 默认 min(CPU,8)）
import { execFile, execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ensureFresh } from "../internal/freshness.mts";
import { byteSort } from "../internal/text.mts";

const runnerExe = "moonbit/_build/native/release/build/cmd/run/run.exe";

// #49 批二段三：被测物后端（"native" cmd/run exe | "wasm" 统一入口壳——
// 与 vm_diff 同款插座）。
const wasmShell = "moonbit/_build/js/release/build/cmd/vitro_wasm/vitro_wasm.js";

const wasmMod = "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm";

let backend = "native";

const clangCacheDir = ".clang_cache_cd";

// cd3（病 15 批 C，#61）：运行捕获 stderr 分离——golden = stdout only。
const cacheSchema = "cd3";

const clangPath = "clang";

const clangRetry = 3;

const clangRunTimeoutMs = 10_000;

// moonRunTimeout：MoonBit 侧（native exe / node 壳）单例运行杀钟；超时非
// 确定结果，不落缓存（比对层双证红）。
const moonRunTimeoutMs = 120_000;

// 语料集（元素为相对仓库根路径——含路径分隔符时原样使用，裸名仍拼 corpus/
// 前缀兼容 --corpus baseline 旧用法）。#237 工程模式（2026-10-21）：
// llm_multifile 目录走「子目录 = 一个工程」扫描。
const corporaDefault = [
  "corpus/baseline",
  "corpus/knr",
  "corpus/leetcode",
  "corpus/gap",
  "corpus/codegen_skeleton",
  "corpus/template_generated",
  "corpus/llm_multifile",
  // 千行单文件语料（#236 perf_budget 同名目录有 llm_scale 分档预算——
  // 两处目录名须一致，档位按该前缀匹配）
  "corpus/llm_scale",
];

// projectCorpusDirs：启用工程模式扫描的语料目录（裸目录名集合——一级
// 子目录含 ≥1 .c 即一个工程 case）。
const projectCorpusDirs = new Set(["llm_multifile"]);

// corpusPath：裸语料名 → corpus/ 前缀；含分隔符 → 原样。
function corpusPath(c: string): string {
  if (/[/\\]/.test(c)) return c;
  return "corpus/" + c;
}

// knownEntry：已归因差异（case + digest + reason；digest = 差异内容 sha256
// 前 8 位——漂移即降级 DIFF 逼重新归因）。**digests 多值集**：真值源是
// Clang 本尊，其编译产物行为随版本变——条目可登记跨环境 digest 集，
// 匹配 = 集合内；`digest` 单值字段向后兼容。
interface KnownEntry {
  case: string;
  digest?: string;
  digests?: string[];
  reason: string;
}

function digestSet(e: KnownEntry): string[] {
  const set = [...(e.digests ?? [])];
  if (e.digest !== undefined && e.digest !== "") set.push(e.digest);
  return set;
}

interface KnownList {
  entries: KnownEntry[];
  hit: Map<string, boolean>;
}

interface ClangResult {
  compileFail: boolean;
  abnormal: boolean; // 瞬态环境异常（不落缓存）
  stdout: string;
  exitCode: number;
}

interface MoonResult {
  compileFail: boolean;
  stdout: string;
  exitCode: number;
  memoryPath: string; // --dump-memory 产物（正向证据：恰 1MB）
  // #237 工程模式：api --batch 通道无 --dump-memory——跳过映像正向证据
  skipMemoryCheck: boolean;
}

interface CaseRef {
  rel: string;
  path: string;
  // #237 工程模式：子目录 = 一个工程（files 含全部 .c 与 .h，排序）；
  // 单文件 case 两字段为零值（project=false 走原路径）
  project: boolean;
  files: string[];
}

// stdinFor：同名 .in 配对（x.c → x.in；无则空串）。
function stdinFor(p: string): string {
  const inPath = p.endsWith(".c") ? p.slice(0, -2) + ".in" : p + ".in";
  return fileExists(inPath) ? inPath : "";
}

function fatal(msg: string): never {
  process.stderr.write("clang_direct: " + msg + "\n");
  process.exit(2);
}

function fileExists(p: string): boolean {
  try {
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

function isDir(p: string): boolean {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

// ─── known 台账 ──

function loadKnown(): KnownList {
  const kl: KnownList = { entries: [], hit: new Map() };
  let data: string;
  try {
    data = fs.readFileSync(path.join("scripts", "clang_direct", "known_direct.json"), "utf8");
  } catch {
    return kl;
  }
  try {
    kl.entries = JSON.parse(data) as KnownEntry[];
  } catch {
    return kl;
  }
  return kl;
}

function lookup(k: KnownList, base: string): KnownEntry | undefined {
  for (const e of k.entries) {
    if (e.case === base) {
      k.hit.set(e.case, true);
      return e;
    }
  }
  return undefined;
}

const DIGEST_RE = /^[0-9a-f]{8}$/;

// fullCorpusRun：真·全量（默认语料、无 --cases/--sample）——白名单空转校验
// （静态与动态）只在此形态判，否则 `--corpus gap` 会误报（P3-6）。
function fullCorpusRun(corpora: string[], explicit: string[], sample: number): boolean {
  if (explicit.length !== 0 || sample !== 0) return false;
  if (corpora.length !== corporaDefault.length) return false;
  return corpora.every((c, i) => c === corporaDefault[i]!);
}

// checkKnown：known_direct.json 静态校验子命令（拆分前置——CI 可独立跑）。
// 只做免 runner/clang 的静态部分：①每条 case 在全语料集存在；②digest 为
// 8 位 hex；③台账非空。动态部分（转绿未命中即红）仍由全量运行承担。
function checkKnown(known: KnownEntry[]): boolean {
  if (known.length === 0) {
    console.log("clang_direct: --check-known: known 台账为空（空集不得绿）");
    return false;
  }
  let ok = true;
  for (const k of known) {
    let found = false;
    for (const corpus of corporaDefault) {
      const p = path.join(corpusPath(corpus), ...k.case.split("/"));
      // #237：工程模式条目是目录（corpus/llm_multifile/<工程名>）
      if (fileExists(p) || isDir(p)) {
        found = true;
        break;
      }
    }
    if (!found) {
      console.log(`clang_direct: --check-known: 条目 ${JSON.stringify(k.case)} 在全语料集无对应文件（用例改名/删除后悬空）`);
      ok = false;
    }
    for (const d of digestSet(k)) {
      if (!DIGEST_RE.test(d)) {
        console.log(`clang_direct: --check-known: 条目 ${JSON.stringify(k.case)} digest ${JSON.stringify(d)} 非 8 位 hex`);
        ok = false;
      }
    }
  }
  if (ok) {
    console.log(`clang_direct: --check-known: OK（${known.length} 条静态校验通过；动态转绿监控由全量运行承担）`);
  }
  return ok;
}

function collectCases(corpora: string[], sample: number, explicit: string[]): CaseRef[] {
  const out: CaseRef[] = [];
  if (explicit.length > 0) {
    for (const c of explicit) {
      let p = "";
      for (const corpus of corporaDefault) {
        const cand = path.join(corpusPath(corpus), ...c.split("/"));
        if (fileExists(cand)) {
          p = cand;
          break;
        }
      }
      if (p === "") p = c; // 允许全路径
      out.push({ rel: p, path: p, project: false, files: [] });
    }
    return out;
  }
  for (const c of corpora) {
    const dir = corpusPath(c);
    // #237 工程模式目录：一级子目录 = 一个工程 case（含 ≥1 .c 才收）
    if (projectCorpusDirs.has(path.basename(dir))) {
      let entries: fs.Dirent[];
      try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
      } catch {
        continue;
      }
      for (const e of entries) {
        if (!e.isDirectory()) continue;
        const pdir = path.join(dir, e.name);
        let sub: fs.Dirent[];
        try {
          sub = fs.readdirSync(pdir, { withFileTypes: true });
        } catch {
          continue;
        }
        const cs: string[] = [];
        const hs: string[] = [];
        for (const f of sub) {
          if (f.isDirectory()) continue;
          if (f.name.endsWith(".c")) cs.push(path.join(pdir, f.name));
          else if (f.name.endsWith(".h")) hs.push(path.join(pdir, f.name));
        }
        if (cs.length === 0) continue;
        const files = [...byteSort(cs), ...byteSort(hs)];
        out.push({
          rel: pdir.split(path.sep).join("/"), path: pdir,
          project: true, files,
        });
      }
      continue;
    }
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      if (e.isDirectory() || !e.name.endsWith(".c")) continue;
      const p = path.join(dir, e.name);
      out.push({ rel: p.split(path.sep).join("/"), path: p, project: false, files: [] });
    }
  }
  out.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
  if (sample > 0 && sample < out.length) {
    const step = out.length / sample;
    const sampled: CaseRef[] = [];
    for (let i = 0; i < sample; i++) {
      let idx = Math.trunc(i * step);
      if (idx >= out.length) idx = out.length - 1;
      sampled.push(out[idx]!);
    }
    return sampled;
  }
  return out;
}

// ─── Clang 侧（形态复刻 shadow_verify）──

function clangCompileArgs(cFile: string, exeFile: string): string[] {
  const args = [cFile, "-o", exeFile, "-Wno-implicit-function-declaration"];
  if (process.platform !== "win32") args.push("-lm");
  return args;
}

function clangVersionString(): string {
  try {
    const out = execFileSync(clangPath, ["--version"], { encoding: "utf8" });
    return out.trim();
  } catch {
    return "unknown";
  }
}

interface CachePayload {
  schema: string;
  stdout: string; // base64（Go []byte 的 JSON 形态——字节保真存储）
  exit_code: number;
  compile_fail: boolean;
}

function cacheKey(src: Buffer, clangVersion: string, stdinPath: string): string {
  const h = createHash("sha256");
  h.update(Buffer.from(cacheSchema, "utf8"));
  h.update(Buffer.from([0]));
  h.update(src);
  h.update(Buffer.from([0]));
  h.update(Buffer.from(clangVersion, "utf8"));
  h.update(Buffer.from([0]));
  // stdin 维度（2026-09-29 实写）：同源码不同输入必须分键。
  try {
    h.update(fs.readFileSync(stdinPath));
  } catch {
    h.update(Buffer.from("<no-stdin>", "utf8"));
  }
  h.update(Buffer.from([0]));
  const args = clangCompileArgs("<src>", "<exe>");
  h.update(Buffer.from(args.join(" "), "utf8"));
  return h.digest("hex").slice(0, 40);
}

// runProc：spawn 的 Promise 包装（字节面 stdout/stderr Buffer + 超时杀 +
// stdin 喂入）。timedOut 非确定结果，由调用方归入 abnormal。
interface ProcResult {
  stdout: Buffer;
  stderr: Buffer;
  code: number | null;
  timedOut: boolean;
  spawnErr: boolean;
}

function runProc(cmd: string, args: string[], opts: {
  cwd?: string;
  timeoutMs?: number;
  stdin?: Buffer | null;
  merge?: boolean; // stderr 并入 stdout（编译输出形态）
  discardStderr?: boolean; // stderr 丢弃（运行对拍口径）
}): Promise<ProcResult> {
  return new Promise((resolve) => {
    const child = execFile(cmd, args, {
      cwd: opts.cwd,
      maxBuffer: 256 * 1024 * 1024,
      encoding: "buffer", // 字节面 stdout/stderr（默认 utf8 会解码成 string——字节保真必须 buffer）
      timeout: 0, // 杀钟自管（Go time.AfterFunc 同款语义：区分 timedOut 与 exit）
      killSignal: "SIGKILL",
    }, () => { /* 回调空——收尾在 close 一并 resolve */ });
    const out: Buffer[] = [];
    const err: Buffer[] = [];
    let timedOut = false;
    let spawnErr = false;
    const timer = opts.timeoutMs !== undefined
      ? setTimeout(() => {
        timedOut = true;
        try {
          child.kill("SIGKILL");
        } catch { /* 已退出 */ }
      }, opts.timeoutMs)
      : null;
    child.stdout?.on("data", (d: Buffer) => out.push(d));
    if (opts.merge) {
      child.stderr?.on("data", (d: Buffer) => out.push(d));
    } else if (opts.discardStderr) {
      child.stderr?.resume();
    } else {
      child.stderr?.on("data", (d: Buffer) => err.push(d));
    }
    if (opts.stdin !== undefined && opts.stdin !== null) {
      child.stdin?.end(opts.stdin);
    } else {
      child.stdin?.end();
    }
    child.on("error", () => {
      spawnErr = true;
    });
    child.on("close", (code) => {
      if (timer !== null) clearTimeout(timer);
      resolve({
        stdout: Buffer.concat(out),
        stderr: Buffer.concat(err),
        code,
        timedOut,
        spawnErr,
      });
    });
  });
}

async function runClang(c: CaseRef, caseIdx: number, clangVersion: string): Promise<ClangResult> {
  // #237 工程模式：key = 全部源文件内容串联（含 .h——头文件变更即失效）
  const keyParts: Buffer[] = [];
  try {
    if (c.project) {
      for (const f of c.files) {
        keyParts.push(Buffer.from(f, "utf8"), fs.readFileSync(f));
      }
    } else {
      keyParts.push(fs.readFileSync(c.path));
    }
  } catch {
    return { compileFail: true, abnormal: true, stdout: "", exitCode: 0 };
  }
  const keySrc = Buffer.concat(keyParts);
  const key = cacheKey(keySrc, clangVersion, stdinFor(c.path));
  try {
    const data = JSON.parse(fs.readFileSync(path.join(clangCacheDir, key + ".json"), "utf8")) as CachePayload;
    if (data.schema === cacheSchema) {
      return {
        compileFail: data.compile_fail,
        stdout: Buffer.from(data.stdout, "base64").toString("latin1"),
        exitCode: data.exit_code,
        abnormal: false,
      };
    }
  } catch { /* miss → 现场编译 */ }
  // 重试判据（shadow_verify 同款）：「编译成功且非瞬态异常」才接受——
  // 编译失败也重试（Windows 并发下 Defender 实时扫描锁目标文件会让 clang
  // 以非零退出；重试 3 次仍失败才接受为结果）。
  let res: ClangResult | null = null;
  for (let attempt = 0; attempt < clangRetry; attempt++) {
    res = await runClangOnce(c, caseIdx);
    if (!res.compileFail && !res.abnormal) break;
    // 指数退避 1s/2s/4s（P1-1 收敛批：全量并发下邻居编译窗口 >1.5s）
    await new Promise((r) => setTimeout(r, 1000 << attempt));
  }
  // 编译失败恢复落缓存（目录唯一化后失败恢复确定性）；指数退避保留作纵深。
  if (res !== null && !res.abnormal) {
    storeCache(key, res);
  }
  return res!;
}

// runClangOnce：用例隔离目录内编译 + 运行（2026-09-26 竞态根因修复：目录
// 按「pid_用例序号」唯一——slot 复用形态下 defer RemoveAll 会删掉并发者
// 正在写的目录）。
async function runClangOnce(c: CaseRef, caseIdx: number): Promise<ClangResult> {
  const runDir = path.join(os.tmpdir(), `clang_direct_${process.pid}_${caseIdx}`);
  try {
    fs.mkdirSync(runDir, { recursive: true });
  } catch {
    return { compileFail: true, abnormal: true, stdout: "", exitCode: 0 };
  }
  try {
    const base = path.basename(c.path);
    const ext = process.platform === "win32" ? ".exe" : "";
    // #237 工程模式：全部 .c 一次编译链接（.h 只被 include 不上命令行）；
    // cwd = 工程目录，include 搜索靠 -I 指向工程目录
    let compileArgs: string[];
    let exeFile: string;
    if (c.project) {
      exeFile = path.join(runDir, "proj" + ext);
      const args = ["-w", "-I", c.path];
      for (const f of c.files) {
        if (f.endsWith(".c")) args.push(path.basename(f));
      }
      args.push("-o", exeFile);
      if (process.platform !== "win32") args.push("-lm");
      compileArgs = args;
    } else {
      exeFile = path.join(runDir, base.slice(0, -".c".length) + ext);
      compileArgs = clangCompileArgs(c.path, exeFile);
    }
    const compiled = await runProc(clangPath, compileArgs, {
      cwd: c.project ? c.path : undefined,
      merge: true,
    });
    if (compiled.spawnErr) {
      return { compileFail: true, abnormal: true, stdout: "", exitCode: 0 };
    }
    if (compiled.code !== 0 && !compiled.timedOut) {
      // 编译失败：确定性行为（源码不支持），落缓存
      return { compileFail: true, abnormal: false, stdout: compiled.stdout.toString("latin1"), exitCode: 0 };
    }
    if (compiled.timedOut) {
      return { compileFail: true, abnormal: true, stdout: "", exitCode: 0 };
    }
    // 运行（超时 = 环境异常可重试；exit != 0 = 确定性结果）。
    // **cwd = 隔离目录**（fopen("test.txt") 族用例真读写仓库根的竞态治理）。
    // .in 配对喂入（无 .in 保持空 stdin 原口径）。
    // 病 15 批 C（#61）：stderr 分离丢弃——对拍口径 = stdout only 双侧对称。
    // P2（2026-09-27）：超时结果**不得当确定性结果**——timedOut ⇒ abnormal
    //（不落缓存 + 重试）。
    let stdinBuf: Buffer | null = null;
    const inPath = stdinFor(c.path);
    if (inPath !== "") {
      try {
        stdinBuf = fs.readFileSync(inPath);
      } catch { /* 空 stdin */ }
    }
    const r = await runProc(exeFile, [], {
      cwd: runDir,
      timeoutMs: clangRunTimeoutMs,
      stdin: stdinBuf,
      discardStderr: true,
    });
    if (r.timedOut) {
      return { compileFail: false, abnormal: true, stdout: r.stdout.toString("latin1"), exitCode: 0 };
    }
    if (r.spawnErr) {
      return { compileFail: false, abnormal: true, stdout: r.stdout.toString("latin1"), exitCode: 0 };
    }
    return { compileFail: false, abnormal: false, stdout: r.stdout.toString("latin1"), exitCode: r.code ?? 0 };
  } finally {
    try {
      fs.rmSync(runDir, { recursive: true, force: true });
    } catch { /* 清理失败不影响判定 */ }
  }
}

function storeCache(key: string, r: ClangResult): void {
  try {
    fs.mkdirSync(clangCacheDir, { recursive: true });
  } catch {
    return;
  }
  const p: CachePayload = {
    schema: cacheSchema,
    stdout: Buffer.from(r.stdout, "latin1").toString("base64"),
    exit_code: r.exitCode,
    compile_fail: r.compileFail,
  };
  const tmp = path.join(clangCacheDir, key + ".tmp");
  const dst = path.join(clangCacheDir, key + ".json");
  try {
    fs.writeFileSync(tmp, JSON.stringify(p), { mode: 0o644 });
    fs.renameSync(tmp, dst);
  } catch { /* 缓存写失败不影响判定 */ }
}

// ─── MoonBit 侧（形态复刻 vm_diff）──

// vitroApiExe：工程模式的 api --batch 通道宿主（native 臂 = cmd/vitro 总
// 入口 exe；wasm 臂 = vitro_wasm 胶水 + gateway wasm 产物）。
const vitroApiExe = "moonbit/_build/native/release/build/cmd/vitro/vitro.exe";

async function runMoon(c: CaseRef): Promise<MoonResult> {
  // #237 工程模式：files 数组虚拟工程走 api --batch 三帧；无 --dump-memory
  // 通道 ⇒ skipMemoryCheck（正向证据由 compile ok + delta 非空形态承担）
  if (c.project) {
    return runMoonProject(c);
  }
  // P2-4：--dump-memory 正向证据通道——映像恰 1MB 是 runner 真跑了编译
  // 装载全链的充分证据；缺失/非 1MB 进 issues 红。
  let memPath: string;
  try {
    memPath = path.join(os.tmpdir(), `cdmem_${process.pid}_${Math.trunc(Math.random() * 1e9)}.bin`);
    fs.writeFileSync(memPath, Buffer.alloc(0));
  } catch {
    return { compileFail: true, stdout: "// TMPFAIL", exitCode: 0, memoryPath: "", skipMemoryCheck: false };
  }
  // 注意：不在此删除——compareDirect 消费映像在 runMoon 返回之后；
  // 清理由主循环 cleanup 承担。
  const args = [c.path];
  const inPath = stdinFor(c.path);
  if (inPath !== "") args.push("-i", inPath);
  args.push("--dump-memory", memPath);
  // 插座（#49 批二段三；#129 通道分立 2026-10-16 修正）：标记行（诊断/EXIT）
  // 走 stderr——两臂 stderr 都收集，提取面 = stdout+stderr 合并（backend
  // 标注行剥除）。
  const r = backend === "wasm"
    ? await runProc("node", [wasmShell, "run", ...args], { timeoutMs: moonRunTimeoutMs })
    : await runProc(runnerExe, args, { timeoutMs: moonRunTimeoutMs });
  if (r.timedOut) {
    // 运行期看门狗（2026-10-17 云端 wasm 臂挂死收口）：超时 → // RUN-TIMEOUT
    // 进 stdout（比对 DIFF 响亮红）+ memoryPath 空 → 「映像缺失」双证——
    // 闸继续跑完而非永等（fail loud 非 fail forever）。
    process.stderr.write(`clang_direct: Moon 侧运行超时（120s）：${c.rel}\n`);
    return { compileFail: false, stdout: "// RUN-TIMEOUT", exitCode: 0, memoryPath: "", skipMemoryCheck: false };
  }
  let s = r.stdout.toString("latin1");
  for (const l of r.stderr.toString("latin1").split("\n")) {
    if (!l.startsWith("[vitro] backend=")) {
      s += l + "\n";
    }
  }
  const res: MoonResult = { compileFail: false, stdout: s, exitCode: 0, memoryPath: memPath, skipMemoryCheck: false };
  if (s.includes("// COMPILE-ERROR")) {
    res.compileFail = true;
  }
  for (const line of s.split("\n")) {
    const t = line.replace(/\r+$/, "");
    if (t.startsWith("// EXIT ")) {
      const m = /^\/\/ EXIT (\d+)/.exec(t);
      if (m !== null) res.exitCode = Number.parseInt(m[1]!, 10);
    }
  }
  res.stdout = extractMoonStdout(s);
  return res;
}

// extractMoonStdout：剥协议标记行（// EXIT / // TRAP / // COMPILE-ERROR 族）
// + CRLF 归一（两侧对称原样字节比对——latin1Fold 已随 #66 退役）。
export function extractMoonStdout(s: string): string {
  const lines = s.split("\n");
  const kept: string[] = [];
  for (const l of lines) {
    const t = l.endsWith("\r") ? l.slice(0, -1) : l;
    if (
      t.startsWith("// TRAP ") || t.startsWith("// COMPILE-ERROR ") ||
      // DX ②（2026-10-11）：FIX 伴生行（诊断 fix_suggestion——vm_diff 同步）
      t.startsWith("// FIX ") ||
      t.startsWith("// COMPILE-WARNING ") || t.startsWith("// COMPILE-HINT ") ||
      t.startsWith("// NOTE ") ||
      // 病 15 批 C（#61）：stderr 标记行——stderr 不进 stdout 对拍 digest
      t.startsWith("// STDERR ")
    ) {
      continue;
    }
    kept.push(l);
  }
  // 尾部空行剥 → 末行 // EXIT 剥（Go 版主流程直译——EXIT 不进标记行剥除
  // 列表，只在尾部单剥）。
  while (kept.length > 0 && kept[kept.length - 1]!.replace(/\r+$/, "") === "") {
    kept.pop();
  }
  if (kept.length > 0 && kept[kept.length - 1]!.replace(/\r+$/, "").startsWith("// EXIT ")) {
    kept.pop();
  }
  return normalizeLines(kept);
}

// normalizeLines：CRLF 归一 + 首尾空行剥（vm_diff 同款；无尾换行 join）。
// TrimRight 复刻：剥**全部**尾部 \r（printf("\r\n") 经 Windows 文本模式
// 再翻译成 \r\r\n——剥一个残一个会把工程语料的 MF-HTTP 误判 DIFF）。
export function normalizeLines(lines: string[]): string {
  const out = lines.map((l) => l.replace(/\r+$/, ""));
  while (out.length > 0 && out[out.length - 1] === "") out.pop();
  while (out.length > 0 && out[0] === "") out.shift();
  return out.join("\n");
}

// normalizeClangStdout：clang golden 行级归一——Windows 下 Clang 编译的原生
// 程序 stdout 为文本模式（\n 伸缩为 \r\n），比对前剥 \r 对齐引擎侧字节口径；
// 不做其它清洗（比对读纯程序输出，驱动侧禁再动内容——E-P1-5）。
export function normalizeClangStdout(s: string): string {
  return normalizeLines(s.split("\n"));
}

// ─── 比对 ──

function compareDirect(o: ClangResult, m: MoonResult): string[] {
  const issues: string[] = [];
  if (o.compileFail !== m.compileFail) {
    const who = m.compileFail ? "moonbit" : "clang";
    let detail = "";
    if (o.compileFail) {
      // clang 错误首行入报文（诊断可达——并发一过性失败与真源码不支持靠它区分）
      for (const l of o.stdout.split("\n")) {
        if (l.trim() !== "") {
          detail = "；" + clip(l);
          break;
        }
      }
    }
    issues.push(`单侧编译失败（${who}${detail}）`);
    return issues;
  }
  if (o.compileFail) {
    return issues; // 双侧失败等价（调用方判）
  }
  // #237：工程模式 delta 通道的尾换行与 clang 管道形态有口径差——
  // moon 侧过同款 normalize 对称比对；单文件路径不动（known digest 面冻结）
  const moonNorm = m.skipMemoryCheck ? normalizeClangStdout(m.stdout) : m.stdout;
  if (normalizeClangStdout(o.stdout) !== moonNorm) {
    issues.push(summarizeStdout(normalizeClangStdout(o.stdout), moonNorm));
  }
  if (o.exitCode !== m.exitCode) {
    issues.push(`返回码 ${o.exitCode} != ${m.exitCode}`);
  }
  // P3（2026-09-27 审阅销项）：abnormal 入判定——重试耗尽的异常结果与
  // 「程序本无输出」不可区分，会假 SAME。通道直接入 issue 红比论证其
  // 不可达便宜。
  if (o.abnormal) {
    issues.push("clang 侧结果异常（重试耗尽）——不可采信，请复跑");
  }
  // 正向证据（P2-4）：runner 真跑了全链 ⇒ 映像恰 1MB。
  if (!m.compileFail && !m.skipMemoryCheck) {
    if (m.memoryPath === "") {
      issues.push("映像缺失（runner 未产出 dump）");
    } else {
      let md: Buffer | null = null;
      try {
        md = fs.readFileSync(m.memoryPath);
      } catch (e) {
        issues.push(`映像读取失败（${(e as Error).message}）`);
      }
      if (md !== null && md.length !== 1024 * 1024) {
        issues.push(`映像非 1MB（${md.length}）——runner 全链正向证据缺失`);
      }
    }
  }
  return issues;
}

function summarizeStdout(o: string, m: string): string {
  const ol = o.split("\n");
  const ml = m.split("\n");
  for (let i = 0; i < ol.length && i < ml.length; i++) {
    if (ol[i] !== ml[i]) {
      return `stdout 第 ${i + 1} 行不一致（clang ${goQuoteClip(ol[i]!)} vs moonbit ${goQuoteClip(ml[i]!)}）`;
    }
  }
  if (ol.length !== ml.length) {
    return `stdout 行数不一致（clang ${ol.length} vs moonbit ${ml.length}）`;
  }
  return `stdout 不一致（${o.length}/${m.length} 字节）`;
}

function clip(s: string): string {
  return s.length > 40 ? s.slice(0, 40) + "…" : s;
}

// goQuote：Go strconv.Quote 的字节级复刻（输入 latin1 字符串 = 字节串）。
// 关键差异面：moon 侧 UTF-8 中文输出（如教学 inspect 行）在 latin1 域是
// 离散字节，Go %q 会把**合法 UTF-8 序列还原成原字**（E5 BD 93 → 当）、
// 非法字节渲染 \xNN——报文呈现与 digest 由此与 Go 逐位对齐。
export function goQuote(s: string): string {
  return '"' + quoteBody(s) + '"';
}

// quoteBody：goQuote 的引号内体（clip 截断尾巴 "…" 由调用方在引号内补——
// U+2026 经 latin1 编码会截成 0x26（"&"），绝不能进 latin1 字节域）。
export function quoteBody(s: string): string {
  const bytes = Buffer.from(s, "latin1");
  let out = "";
  let i = 0;
  while (i < bytes.length) {
    const b = bytes[i]!;
    const len = b < 0x80 ? 1
      : b >= 0xc2 && b <= 0xdf ? 2
      : b >= 0xe0 && b <= 0xef ? 3
      : b >= 0xf0 && b <= 0xf4 ? 4
      : 0;
    let ok = len > 1 && i + len <= bytes.length;
    if (ok) {
      for (let k = 1; k < len; k++) {
        if ((bytes[i + k]! & 0xc0) !== 0x80) {
          ok = false;
          break;
        }
      }
    }
    if (len === 1) {
      if (b === 0x22) out += '\\"';
      else if (b === 0x5c) out += "\\\\";
      else if (b === 0x0a) out += "\\n";
      else if (b === 0x0d) out += "\\r";
      else if (b === 0x09) out += "\\t";
      else if (b === 0x07) out += "\\a";
      else if (b === 0x08) out += "\\b";
      else if (b === 0x0c) out += "\\f";
      else if (b === 0x0b) out += "\\v";
      else if (b < 0x20 || b === 0x7f) out += "\\x" + b.toString(16).padStart(2, "0");
      else out += String.fromCharCode(b);
      i++;
      continue;
    }
    if (ok) {
      out += bytes.subarray(i, i + len).toString("utf8");
      i += len;
      continue;
    }
    out += "\\x" + b.toString(16).padStart(2, "0");
    i++;
  }
  return out;
}

// goQuoteClip：Go %q(clip(s)) 的整链复刻——clip 40 字节截断体经 quoteBody
// 渲染，截断尾巴 "…"（U+2026，Go %q 对 IsPrint rune 原样保留）在引号内补。
export function goQuoteClip(s: string): string {
  const clipped = s.length > 40;
  return '"' + quoteBody(s.slice(0, 40)) + (clipped ? "…" : "") + '"';
}

function issueDigest(issues: string[]): string {
  return createHash("sha256").update(issues.join("‖"), "utf8").digest("hex").slice(0, 8);
}

// ─── #237 工程模式：files 数组虚拟工程的 vitro 侧通道 ──

// apiFrame：api --batch 响应帧的最小消费面。
interface ApiFrame {
  id: number;
  ok: boolean;
  result: {
    ok: boolean;
    diagnostics: { message: string }[];
    status: string;
    return_value: number;
    trap: string;
    delta: string;
  } | null;
}

// runMoonProject：compile{files} → run → output.delta 三帧经 api --batch；
// stdout = delta 拼接（单帧 cursor:0 全量），exitCode = run 帧 return_value
//（trap 帧记入 stdout 让 DIFF 响亮红——与单文件 trap 形态对齐由 digest 消化）。
async function runMoonProject(c: CaseRef): Promise<MoonResult> {
  const ents: { filename: string; source: string }[] = [];
  for (const f of c.files) {
    let b: string;
    try {
      b = fs.readFileSync(f, "latin1");
    } catch {
      return { compileFail: true, stdout: "// FILEREAD-FAIL", exitCode: 0, memoryPath: "", skipMemoryCheck: true };
    }
    ents.push({ filename: path.basename(f), source: b });
  }
  // Go json.Marshal 直译：HTML 转义 + 键序 filename/source。
  const cj = goJSONCompact({ files: ents });
  const frames =
    `{"id":1,"method":"compile","params":${cj}}\n` +
    `{"id":2,"method":"run","params":{}}\n` +
    `{"id":3,"method":"output.delta","params":{"cursor":0,"stream":"stdout"}}\n`;
  const r = backend === "wasm"
    ? await runProc("node", [wasmShell, "api", "--batch"], { timeoutMs: moonRunTimeoutMs, stdin: Buffer.from(frames, "utf8") })
    : await runProc(vitroApiExe, ["api", "--batch"], { timeoutMs: moonRunTimeoutMs, stdin: Buffer.from(frames, "utf8") });
  if (r.timedOut) {
    return { compileFail: false, stdout: "// RUN-TIMEOUT", exitCode: 0, memoryPath: "", skipMemoryCheck: true };
  }
  if (r.spawnErr) {
    return { compileFail: true, stdout: "// APIFAIL: " + clip(r.stderr.toString("latin1")), exitCode: 0, memoryPath: "", skipMemoryCheck: true };
  }
  let stdout = "";
  let exitCode = 0;
  let compileFail = false;
  for (const rawLine of r.stdout.toString("latin1").split("\n")) {
    const line = rawLine.trim();
    if (line === "") continue;
    let fr: ApiFrame;
    try {
      fr = JSON.parse(line) as ApiFrame;
    } catch {
      continue;
    }
    if (fr.result === null || fr.result === undefined) continue;
    switch (fr.id) {
      case 1:
        if (!fr.result.ok) {
          compileFail = true;
          for (const d of fr.result.diagnostics) {
            stdout += d.message + "\n";
            break; // 首条即可（与单文件编译失败诊断首行口径对齐）
          }
        }
        break;
      case 2:
        exitCode = fr.result.return_value;
        if (fr.result.trap !== "") {
          stdout += "// TRAP: " + fr.result.trap + "\n";
        }
        break;
      case 3:
        stdout += fr.result.delta;
        break;
    }
  }
  return { compileFail, stdout, exitCode, memoryPath: "", skipMemoryCheck: true };
}

// goJSONCompact：Go json.Marshal 的紧凑形态（SetEscapeHTML 默认 true——
// <>& 转义；map 键序：工程帧只有固定键序 files→filename/source，声明序即序）。
function goJSONCompact(v: unknown): string {
  return JSON.stringify(v)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/&/g, "\\u0026")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}

// ─── 主流程 ──

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  let corpora = corporaDefault;
  let sample = 0;
  let jobs = 0;
  let checkKnownFlag = false;
  const explicit: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === "--corpus" && i + 1 < args.length) {
      corpora = [args[++i]!];
    } else if (a === "--sample" && i + 1 < args.length) {
      // fail loud（#307 P3-10）：非数值/负数不得静默回落 0（=全量跑）——
      // Go 版 fmt.Sscanf 同病（回退面不追），现役 .mts 修：用法错 exit 2。
      const v = Number.parseInt(args[++i]!, 10);
      if (!Number.isFinite(v) || v < 0) {
        process.stderr.write(`clang_direct: --sample 须为非负整数，得到 ${JSON.stringify(args[i]!)}\n`);
        process.exit(2);
      }
      sample = v;
    } else if (a === "--cases" && i + 1 < args.length) {
      explicit.push(...args[++i]!.split(","));
    } else if (a === "--jobs" && i + 1 < args.length) {
      // fail loud（#307 P3-10）：同 --sample——非数值静默回落 0（自动档）
      // 等于吞掉调用方的并发意图。
      const v = Number.parseInt(args[++i]!, 10);
      if (!Number.isFinite(v) || v <= 0) {
        process.stderr.write(`clang_direct: --jobs 须为正整数，得到 ${JSON.stringify(args[i]!)}\n`);
        process.exit(2);
      }
      jobs = v;
    } else if (a === "--check-known") {
      checkKnownFlag = true;
    } else if (a === "--backend" && i + 1 < args.length) {
      const b = args[++i]!;
      if (b !== "native" && b !== "wasm") {
        process.stderr.write(`clang_direct: --backend 取值 native|wasm，得到 ${JSON.stringify(b)}\n`);
        process.exit(2);
      }
      backend = b;
    } else {
      process.stderr.write(`clang_direct: 未知参数 ${JSON.stringify(a)}\n`);
      process.exit(2);
    }
  }

  // --check-known：静态校验免 runner/clang（拆分前置——CI 可独立跑）
  if (checkKnownFlag) {
    const k = loadKnown();
    if (!checkKnown(k.entries)) {
      process.exit(2);
    }
    return;
  }

  // 前置：runner 存在 + 新鲜度门禁（mtime 触发 + 构建复核单源）
  if (backend === "wasm") {
    if (!fileExists(wasmShell)) {
      fatal(`${wasmShell} 不存在（统一入口壳）`);
    }
    ensureFresh("clang_direct", wasmMod,
      ["build", "--release", "--target", "wasm-gc", "gateway/wasm"]);
    ensureFresh("clang_direct_wasm_glue", wasmShell,
      ["build", "--release", "--target", "js", "cmd/vitro_wasm"]);
  } else {
    ensureFresh("clang_direct", runnerExe,
      ["build", "--release", "--target", "native", "cmd/run"]);
    // #237 工程模式宿主：api --batch 走 cmd/vitro 总入口（工程语料目录
    // 存在才要求——空目录不强制构建）
    if (fileExists("corpus/llm_multifile")) {
      ensureFresh("clang_direct_project", vitroApiExe,
        ["build", "--release", "--target", "native", "cmd/vitro"]);
    }
  }

  // clang 可用性 fail fast（缺失即 exit 2，不静默跳过）
  try {
    execFileSync(clangPath, ["--version"], { stdio: "ignore" });
  } catch {
    fatal(`未找到 ${clangPath}——Clang 是本防线真值源，缺失即红（安装或修正 PATH）`);
  }
  const clangVersion = clangVersionString();

  const cases = collectCases(corpora, sample, explicit);
  if (cases.length === 0) {
    process.stderr.write("clang_direct: 无用例\n");
    process.exit(1);
  }

  const known = loadKnown();
  // 白名单防腐化（静态部分）：known 条目名不在用例集合即红（全量模式才判）
  if (fullCorpusRun(corpora, explicit, sample)) {
    const names = new Set(cases.map((c) => path.basename(c.rel)));
    for (const e of known.entries) {
      if (!names.has(e.case)) {
        process.stderr.write(`clang_direct: known 白名单空转条目 ${e.case}——语料中不存在（删除或修正）\n`);
        process.exit(1);
      }
    }
  }

  if (jobs <= 0) {
    jobs = Math.min(os.cpus().length, 8);
  }

  // ── 双侧执行 ──
  // Clang 侧并发（用例隔离目录）；MoonBit 侧主线程串行（VM exe 单实例
  // 保守口径与 vm_diff 同前提）。两结果数组分离，避免并发写竞争。
  const clangRes: (ClangResult | null)[] = cases.map(() => null);
  const moonRes: (MoonResult | null)[] = cases.map(() => null);
  let next = 0;
  const worker = async (): Promise<void> => {
    for (;;) {
      const k = next++;
      if (k >= cases.length) return;
      clangRes[k] = await runClang(cases[k]!, k, clangVersion);
    }
  };
  const clangPool = Array.from({ length: jobs }, () => worker());
  for (let k = 0; k < cases.length; k++) {
    moonRes[k] = await runMoon(cases[k]!);
  }
  await Promise.all(clangPool);

  let same = 0;
  let knownN = 0;
  let diff = 0;
  for (let k = 0; k < cases.length; k++) {
    const c = cases[k]!;
    const base = path.basename(c.rel);
    const o = clangRes[k]!;
    const m = moonRes[k]!;
    if (o.compileFail && m.compileFail) {
      console.log(`SAME  ${c.rel}（双侧编译失败——等价）`);
      same++;
      continue;
    }
    const issues = compareDirect(o, m);
    cleanupMoon(m);
    if (issues.length === 0) {
      console.log(`SAME  ${c.rel}`);
      same++;
      continue;
    }
    // P3-7（2026-09-26 审阅）：digest 混入 case 名——白名单豁免必须钉到
    // 「这一例的这种差异」而非「任何一例的这种差异」。
    const digest = issueDigest([base, ...issues]);
    const e = lookup(known, base);
    if (e !== undefined) {
      if (digestSet(e).some((d) => d === digest)) {
        console.log(`DIFF-KNOWN ${c.rel}（${e.reason}；digest=${digest}）`);
        knownN++;
        continue;
      }
      console.log(`DIFF  ${c.rel}：已知差异形状已变（登记 [${digestSet(e).join(" ")}] 实测 ${digest}）——重新归因更新 known_direct.json：${issues.join("；")}`);
      diff++;
      continue;
    }
    console.log(`DIFF  ${c.rel} [${digest}]：${issues.join("；")}`);
    diff++;
  }
  console.log(`\nclang_direct: SAME=${same} DIFF-KNOWN=${knownN} DIFF=${diff}（共 ${same + knownN + diff}）`);

  // 白名单防腐化（动态部分）：known 条目未命中即红（转绿逼移除）
  if (fullCorpusRun(corpora, explicit, sample)) {
    let bad = false;
    for (const e of known.entries) {
      if (!known.hit.get(e.case)) {
        process.stderr.write(`clang_direct: known 白名单空转条目 ${e.case}——本轮未产生差额（用例已转绿则删除，双向监控纪律）\n`);
        bad = true;
      }
    }
    if (bad) {
      process.exit(1);
    }
  }
  if (diff > 0) {
    process.exit(1);
  }
}

// cleanupMoon：runMoon 映像文件清理（compare 消费后）。
function cleanupMoon(m: MoonResult): void {
  if (m.memoryPath !== "") {
    try {
      fs.rmSync(m.memoryPath, { force: true });
    } catch { /* 清理失败不影响判定 */ }
  }
}

// 主模块守卫：TS 直跑没有 Go 的 main 包隔离——被 node:test import 时不得
// 执行主流程（ensureFresh 会触发构建/fatal）。wasmopt 同款先例。
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main();
}
