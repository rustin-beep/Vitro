// probes —— realcode_diff 的外部进程面（Clang/gcc 真值、Vitro serve 连发、运行对比）。
//
// 与 Go 版逐口径复刻：
//   - 诊断类调用（语法检查）合并捕获 stdout+stderr（诊断即目的）；
//   - 运行对比**分离捕获**且只取 stdout（#254：stderr 协议帧混入是假 mismatch 主源）；
//   - serve 走 `moon run --target native moonbit/cmd/serve`，JSON-lines 按 id 回填；
//   - 输出归一后按**字节**比较，详情里的长度文案走 Buffer.byteLength。
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawn } from "node:child_process";
import { StringDecoder } from "node:string_decoder";
import { fatal } from "../internal/capi.mts";
import { goTrimSpace } from "../internal/text.mts";
import { firstLine, normalize, vnEqualIgnoreDigits } from "./stmt_expr.mts";
import type { CompileFile, Diag, Project } from "./types.mts";

export const GCC_FALLBACK = "D:\\code\\mingw64\\bin\\gcc.exe";

export interface DiagnosticCounts {
  errs: number;
  warns: number;
  first: string;
}

/** Clang 诊断行计数（P3-3 抽纯函数：错误/警告/首错；警告按 Go 口径豁免两类）。 */
export function clangDiagnosticCounts(out: string): DiagnosticCounts {
  let errs = 0;
  let warns = 0;
  let first = "";
  for (const l of out.split("\n")) {
    if (l.includes("error:")) {
      errs++;
      if (first === "") first = goTrimSpace(l);
    } else if (l.includes("warning:") && !l.includes("_CRT_SECURE") && !l.includes("deprecated")) {
      warns++;
    }
  }
  return { errs, warns, first };
}

/** gcc 语法检查只数 error 行（与 gccCheck 口径一致）。 */
export function gccErrorCount(out: string): number {
  let errs = 0;
  for (const l of out.split("\n")) if (l.includes("error:")) errs++;
  return errs;
}

export interface GccResolution {
  gcc: string;
  source: "explicit" | "path" | "fallback" | "none";
  missingExplicit?: string | undefined;
}

/** gcc 探测序（P3-3 抽纯函数）：--gcc 显式 → PATH → mingw64 回退；显式缺失不回退。 */
export function resolveGcc(
  explicit: string,
  pathGcc: string | null,
  fallback: string,
  exists: (p: string) => boolean,
): GccResolution {
  if (explicit !== "") {
    if (exists(explicit)) return { gcc: explicit, source: "explicit" };
    return { gcc: "", source: "none", missingExplicit: explicit };
  }
  if (pathGcc !== null) return { gcc: pathGcc, source: "path" };
  if (exists(fallback)) return { gcc: fallback, source: "fallback" };
  return { gcc: "", source: "none" };
}

interface Finished {
  stdout: Buffer;
  stderr: Buffer;
  combined: Buffer;
  error: Error | null;
}

function spawnCollect(
  exe: string,
  args: readonly string[],
  opts: { cwd?: string; timeoutMs: number },
): Promise<Finished> {
  return new Promise((resolve) => {
    const child = spawn(exe, args, {
      cwd: opts.cwd,
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });
    const out: Buffer[] = [];
    const err: Buffer[] = [];
    const all: Buffer[] = [];
    let spawnError: Error | null = null;
    let timedOut = false;
    let settled = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, opts.timeoutMs);
    const finish = (): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const stdout = Buffer.concat(out);
      const stderr = Buffer.concat(err);
      let error: Error | null = spawnError;
      if (error === null && timedOut) error = new Error(`timeout ${opts.timeoutMs}ms`);
      else if (error === null && child.exitCode !== 0) error = new Error(`exit status ${child.exitCode}`);
      resolve({ stdout, stderr, combined: Buffer.concat(all), error });
    };
    child.stdout.on("data", (d: Buffer) => {
      out.push(d);
      all.push(d);
    });
    child.stderr.on("data", (d: Buffer) => {
      err.push(d);
      all.push(d);
    });
    child.on("error", (e) => {
      spawnError = e;
    });
    child.on("close", () => finish());
  });
}

/** Go `runWithTimeout`：合并捕获两流，超时/非零退出都返回 error。 */
export async function runWithTimeout(
  exe: string,
  args: readonly string[],
  timeoutMs: number,
  cwd?: string,
): Promise<{ out: string; error: Error | null }> {
  const r = await spawnCollect(exe, args, { cwd, timeoutMs });
  return { out: r.combined.toString("utf8"), error: r.error };
}

/** Go `runWithTimeoutSplit`：分离捕获两流（运行对拍只消费 stdout）。 */
export async function runWithTimeoutSplit(
  exe: string,
  args: readonly string[],
  timeoutMs: number,
  cwd?: string,
): Promise<{ stdout: Buffer; stderr: Buffer; error: Error | null }> {
  const r = await spawnCollect(exe, args, { cwd, timeoutMs });
  return { stdout: r.stdout, stderr: r.stderr, error: r.error };
}

// ---------- P2: Clang 真值 ----------
export async function clangCheck(
  file: string,
): Promise<{ ok: boolean; errs: number; warns: number; first: string }> {
  const { out, error } = await runWithTimeout(
    "clang",
    ["-std=c11", "-Wall", "-Wextra", "-Wno-incompatible-pointer-types", "-fsyntax-only", file],
    15_000,
  );
  if (error !== null && !out.includes("error") && !out.includes("warning")) {
    return { ok: false, errs: 1, warns: 0, first: "clang 执行失败: " + error.message };
  }
  let errs = 0;
  let warns = 0;
  let first = "";
  for (const l of out.split("\n")) {
    if (l.includes("error:")) {
      errs++;
      if (first === "") first = goTrimSpace(l);
    } else if (l.includes("warning:") && !l.includes("_CRT_SECURE") && !l.includes("deprecated")) {
      warns++;
    }
  }
  return { ok: errs === 0, errs, warns, first };
}

// ---------- P2.5: gcc 分桶裁判（分桶裁判，非第二真值） ----------
export function findGcc(explicit: string): string {
  if (explicit !== "") {
    if (fs.existsSync(explicit)) return explicit;
    fatal(`--gcc 指定的路径不存在: ${explicit}`);
  }
  const found = lookPath("gcc");
  if (found !== null) return found;
  const fallback = "D:\\code\\mingw64\\bin\\gcc.exe";
  if (fs.existsSync(fallback)) return fallback;
  return "";
}

function lookPath(name: string): string | null {
  const exts =
    process.platform === "win32"
      ? (process.env.PATHEXT ?? ".EXE;.CMD;.BAT;.COM").split(";").filter((x) => x !== "")
      : [""];
  for (const dir of (process.env.PATH ?? "").split(path.delimiter)) {
    if (dir === "") continue;
    for (const ext of exts) {
      const candidate = path.join(dir, name + ext.toLowerCase());
      try {
        if (fs.statSync(candidate).isFile()) return candidate;
      } catch {
        // 继续探测下一项
      }
    }
  }
  return null;
}

export async function gccCheck(gcc: string, file: string): Promise<{ ok: boolean; errs: number }> {
  const { out, error } = await runWithTimeout(gcc, ["-std=c11", "-fsyntax-only", file], 20_000);
  if (error !== null && !out.includes("error")) return { ok: false, errs: 1 };
  let errs = 0;
  for (const l of out.split("\n")) if (l.includes("error:")) errs++;
  return { ok: errs === 0, errs };
}

export async function gccCheckProject(gcc: string, pr: Project): Promise<{ ok: boolean; errs: number }> {
  if (pr.files.length === 0) return { ok: false, errs: 1 };
  const { out, error } = await runWithTimeout(gcc, ["-std=c11", "-fsyntax-only", ...pr.files], 30_000, pr.dir);
  if (error !== null && !out.includes("error")) return { ok: false, errs: 1 };
  let errs = 0;
  for (const l of out.split("\n")) if (l.includes("error:")) errs++;
  return { ok: errs === 0, errs };
}

export async function clangCheckProject(
  pr: Project,
): Promise<{ ok: boolean; errs: number; first: string }> {
  if (pr.files.length === 0) return { ok: false, errs: 1, first: "工程内无 .c 文件" };
  const { out, error } = await runWithTimeout(
    "clang",
    ["-std=c11", "-Wall", "-Wextra", "-Wno-incompatible-pointer-types", "-fsyntax-only", ...pr.files],
    30_000,
    pr.dir,
  );
  if (error !== null && !out.includes("error") && !out.includes("warning")) {
    return { ok: false, errs: 1, first: "clang 执行失败: " + error.message };
  }
  let errs = 0;
  let first = "";
  for (const l of out.split("\n")) {
    if (l.includes("error:")) {
      errs++;
      if (first === "") first = goTrimSpace(l);
    }
  }
  return { ok: errs === 0, errs, first };
}

// ---------- P3: Vitro serve 连发 ----------
function goJSONString(s: string): string {
  return JSON.stringify(s)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/&/g, "\\u0026")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}

interface ServeResponse {
  id: number;
  result: { diagnostics: Diag[] | null };
}

async function serveBatch(vitroRoot: string, payload: string, keys: readonly string[]): Promise<Map<string, Diag[]>> {
  return new Promise((resolve, reject) => {
    const child = spawn("moon", ["run", "--target", "native", "moonbit/cmd/serve"], {
      cwd: vitroRoot,
      stdio: ["pipe", "pipe", "ignore"],
      windowsHide: true,
    });
    const res = new Map<string, Diag[]>();
    const decoder = new StringDecoder("utf8");
    let buf = "";
    let got = 0;
    let settled = false;
    let spawnError: Error | null = null;

    const settle = (): void => {
      if (settled) return;
      settled = true;
      if (got < keys.length) {
        reject(new Error(`serve 响应不足: ${got}/${keys.length}`));
      } else {
        resolve(res);
      }
    };

    const handleLine = (raw: string): void => {
      const line = raw.trim();
      if (!line.startsWith("{")) return;
      let resp: ServeResponse;
      try {
        resp = JSON.parse(line) as ServeResponse;
      } catch {
        return;
      }
      const idx = resp.id - 1;
      if (idx >= 0 && idx < keys.length) {
        const key = keys[idx] as string;
        res.set(key, resp.result.diagnostics ?? []);
        got++;
        if (got === keys.length) {
          child.kill();
          settle();
        }
      }
    };

    child.stdout.on("data", (chunk: Buffer) => {
      buf += decoder.write(chunk);
      let nl = buf.indexOf("\n");
      while (nl >= 0) {
        handleLine(buf.slice(0, nl));
        buf = buf.slice(nl + 1);
        nl = buf.indexOf("\n");
      }
    });
    child.on("error", (e) => {
      spawnError = e;
    });
    child.on("close", () => {
      if (settled) return;
      buf += decoder.end();
      if (buf !== "") handleLine(buf);
      if (spawnError !== null && got === 0) {
        settled = true;
        reject(new Error(`serve 启动失败(检查 moon/cwd): ${spawnError.message}`));
        return;
      }
      settle();
    });
    child.stdin.on("error", () => {
      // 子进程提前退出时 EPIPE——由 close 分支统一判红
    });
    child.stdin.end(payload);
  });
}

/** -repo 模式：每个文件一个 `source + filename` 请求。 */
export async function serveBatchKeys(
  vitroRoot: string,
  keys: readonly string[],
  paths: readonly string[],
): Promise<Map<string, Diag[]>> {
  let payload = "";
  for (let i = 0; i < paths.length; i++) {
    const p = paths[i] as string;
    let src: string;
    try {
      src = fs.readFileSync(p, "utf8");
    } catch (e) {
      throw new Error(`读取失败 ${p}: ${e instanceof Error ? e.message : String(e)}`);
    }
    payload += `{"id":${i + 1},"method":"compile","params":{"source":${goJSONString(src)},"filename":${goJSONString(p)}}}\n`;
  }
  return serveBatch(vitroRoot, payload, keys);
}

/**
 * -corpus 模式：files+filename 形态（base_dir 取 filename 目录 → 同目录
 * quote-include 可解析）。单文件批逐文件一请求；工程批一个请求装全部单元。
 */
export async function serveBatchFiles(
  vitroRoot: string,
  keys: readonly string[],
  files: readonly CompileFile[],
): Promise<Map<string, Diag[]>> {
  let payload = "";
  if (files.length === keys.length && keys.length > 0) {
    for (let i = 0; i < files.length; i++) {
      const f = files[i] as CompileFile;
      const src = fs.readFileSync(f.path, "utf8");
      const unit = `{"filename":${goJSONString(f.path)},"source":${goJSONString(src)}}`;
      payload += `{"id":${i + 1},"method":"compile","params":{"files":[${unit}]}}\n`;
    }
  } else {
    const units: string[] = [];
    for (const f of files) {
      const src = fs.readFileSync(f.path, "utf8");
      units.push(`{"filename":${goJSONString(f.path)},"source":${goJSONString(src)}}`);
    }
    payload = `{"id":1,"method":"compile","params":{"files":[${units.join(",")}]}}\n`;
  }
  return serveBatch(vitroRoot, payload, keys);
}

// ---------- P5: 运行对比 ----------
export async function runCompare(
  vitroRoot: string,
  cfile: string,
  tmpDir: string,
  skipNet: boolean,
  hasRand: boolean,
): Promise<{ verdict: string; detail: string }> {
  if (skipNet) return { verdict: "skip_net", detail: "网络程序跳过运行" };
  const exe = path.join(tmpDir, "a.exe");
  const build = await runWithTimeout("clang", ["-std=c11", "-O2", "-o", exe, cfile], 30_000);
  if (build.error !== null) {
    return { verdict: "clang_build_fail", detail: firstLine(build.out + " | err=" + build.error.message) };
  }
  const cr = await runWithTimeoutSplit(path.resolve(exe), [], 10_000, tmpDir);
  if (cr.error !== null) {
    if (cr.error.message.includes("timeout")) return { verdict: "clang_timeout", detail: "" };
    return {
      verdict: "clang_run_fail",
      detail: `${cr.error.message} | out=${firstLine(cr.stdout.toString("utf8"))}`,
    };
  }
  const vr = await runWithTimeoutSplit(
    "moon",
    ["run", "--target", "native", "moonbit/cmd/run", "--", cfile],
    120_000,
    vitroRoot,
  );
  if (vr.error !== null) {
    if (vr.error.message.includes("timeout")) return { verdict: "vitro_timeout", detail: "" };
    return { verdict: "vitro_run_fail", detail: firstLine(vr.stdout.toString("utf8")) };
  }
  const vn = normalize(vr.stdout);
  const cn = normalize(cr.stdout);
  if (hasRand) {
    if (vnEqualIgnoreDigits(vn, cn)) return { verdict: "rand_diff_match", detail: "rand 驱动行外一致" };
    return { verdict: "rand_diff", detail: `rand 序列差异(允许): V ${vn.length}B / C ${cn.length}B` };
  }
  if (vn.equals(cn)) return { verdict: "match", detail: `输出逐字节一致(${cn.length}B)` };
  return { verdict: "mismatch", detail: `输出不一致: V ${vn.length}B / C ${cn.length}B` };
}
