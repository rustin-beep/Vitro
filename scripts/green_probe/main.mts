#!/usr/bin/env node
// green_probe —— vitro-green 棘轮分支三臂 compile 对拍（判定型闸，2026-11-14 建）。
//
// 消费方：CI green_probe job（clone rustin-beep/C@vitro-green 分支 → 本脚本三臂断言）。
// 断言锚 = 分支内容本身（零白名单零签名文件）：
//   ① 每文件每臂（js/native/wasm）compile 诊断零 error（vitro 统一入口
//      scripts/bin/vitro --backend <arm> compile --json，纪律 12 单源壳）
//   ② 三臂诊断签名逐文件一致（任两臂分叉 = arm_divergence 红，纪律 14）
// 棘轮规则见 fork 分支 README（只增不减；分支文件变红或臂间分叉即本闸红）。
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { fatal } from "../internal/capi.mts";
import { byteCompare, byteSort } from "../internal/text.mts";

export interface Diag {
  severity: string;
  code: string;
  line: number;
  column: number;
  message: string;
}

export interface ArmResult {
  ok: boolean;
  detail: string;
  signature: string;
}

// ---------- vitro CLI 出口解析（stdout 纯 JSON、backend 提示行走 stderr——实测分离） ----------
export function parseDiagLine(stdout: string): { ok: boolean; diagnostics: Diag[] } | null {
  for (const raw of stdout.split("\n")) {
    const line = raw.trim();
    if (!line.startsWith('{"type":"diag"')) continue;
    let parsed: { frame?: { result?: { ok?: boolean; diagnostics?: Diag[] } } };
    try {
      parsed = JSON.parse(line) as typeof parsed;
    } catch {
      return null;
    }
    const result = parsed.frame?.result;
    if (result === undefined) return null;
    return { ok: result.ok === true, diagnostics: result.diagnostics ?? [] };
  }
  return null;
}

// 诊断签名：码/行列/严重度/消息字节字典序排序后拼接（臂间可比语义投影——
// 不比 file_ranges 等含路径字段）
export function signatureOf(diags: readonly Diag[]): string {
  const parts = diags.map((d) => `${d.code}|${d.severity}|${d.line}|${d.column}|${d.message}`);
  return byteSort(parts).join("\n");
}

export function errorCount(diags: readonly Diag[]): number {
  return diags.filter((d) => d.severity === "error").length;
}

// 三臂一致性：返回分叉描述（null = 一致）
export function armDivergence(arms: ReadonlyMap<string, ArmResult>): string | null {
  const sigs = new Map<string, string[]>();
  for (const [arm, r] of arms) {
    const list = sigs.get(r.signature) ?? [];
    list.push(arm);
    sigs.set(r.signature, list);
  }
  if (sigs.size <= 1) return null;
  const byArm = [...sigs.entries()].map(([sig, as]) => `${as.join("+")}: ${sig === "" ? "(零诊断)" : sig.slice(0, 60)}`);
  return byArm.join(" || ");
}

// ---------- vivo CLI 单文件单臂执行 ----------
async function runOneArm(
  repoRoot: string,
  arm: string,
  cfile: string,
  timeoutMs: number,
): Promise<ArmResult> {
  const { spawn, spawnSync } = await import("node:child_process");
  const vitroSh = path.join(repoRoot, "scripts", "bin", "vitro");
  return new Promise<ArmResult>((resolve) => {
    const child = spawn("sh", [vitroSh, "--backend", arm, "compile", "--json", cfile], {
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });
    let out = "";
    let errOut = ""; // PR #513 审阅 P2-2：stderr 尾部入 detail——产物缺失/崩溃/超时
    // 在日志里原本长得一样（stdout 空时 detail 全空），判因须靠 stderr。
    let settled = false;
    // PR #513 审阅 P3：sh → node 孙进程在 Windows 无进程组，child.kill() 只杀
    // sh 本身——超时路径走 taskkill /T 杀整树（POSIX 无此问题，直接 kill）。
    const killTree = (): void => {
      if (process.platform === "win32" && child.pid !== undefined) {
        spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"]);
      } else {
        child.kill();
      }
    };
    const errTail = (): string => errOut.trim().slice(-400);
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        killTree();
        resolve({
          ok: false,
          detail: `timeout(${arm} ${timeoutMs}ms) stderr: ${errTail()}`,
          signature: "!TIMEOUT!",
        });
      }
    }, timeoutMs);
    child.stdout.on("data", (c: Buffer) => {
      out += c.toString("utf8");
    });
    child.stderr.on("data", (c: Buffer) => {
      errOut += c.toString("utf8");
    });
    child.on("error", (e: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ ok: false, detail: `spawn失败: ${e.message} stderr: ${errTail()}`, signature: "!SPAWN!" });
    });
    child.on("close", (code: number | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const parsed = parseDiagLine(out);
      if (parsed === null) {
        resolve({
          ok: false,
          detail: `出口不可解析(rc=${code}): ${out.trim().slice(0, 120)} stderr: ${errTail()}`,
          signature: "!PARSE!",
        });
        return;
      }
      const errs = errorCount(parsed.diagnostics);
      // PR #513 审阅 P3：口径补强——rc!=0 或 frame.ok=false 同判红（历史 #64→#70
      // 正是「ok:false 但 diagnostics 无 error 级」形态；现路径读码判定不可达，
      // 防的是未来 ok 语义演进时静默漏网）。
      if (errs > 0 || code !== 0 || !parsed.ok) {
        const first = parsed.diagnostics.find((d) => d.severity === "error");
        const head = first !== undefined ? `${first.code} ${first.line}:${first.column} ${first.message.slice(0, 60)}` : `ok=${parsed.ok} rc=${code}`;
        resolve({ ok: false, detail: `${errs} error: ${head} stderr: ${errTail()}`, signature: signatureOf(parsed.diagnostics) });
        return;
      }
      resolve({ ok: true, detail: "", signature: signatureOf(parsed.diagnostics) });
    });
  });
}

// ---------- 主流程 ----------
function walkCFiles(dir: string, out: string[]): void {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === ".git") continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walkCFiles(full, out);
    else if (e.name.endsWith(".c")) out.push(full);
  }
}

export async function main(argv: readonly string[]): Promise<number> {
  let repoDir = "";
  let arms = "js,native,wasm";
  let timeoutMs = 60_000;
  for (let i = 0; i < argv.length; i++) {
    const tok = argv[i] as string;
    if (!tok.startsWith("-")) fatal(`意外的位置参数: ${tok}`);
    const name = tok.replace(/^-+/, "");
    const val = argv[i + 1] as string;
    if (val === undefined) fatal(`-${name} 缺值`);
    i++;
    if (name === "repo") repoDir = path.resolve(val);
    else if (name === "arms") arms = val;
    else if (name === "timeout") {
      timeoutMs = Number(val);
      if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) fatal(`-timeout 非法: ${val}`);
    } else fatal(`未知旗标: -${name}`);
  }
  if (repoDir === "") fatal("必填 -repo <dir>（vitro-green 分支检出目录）");
  if (!fs.existsSync(repoDir) || !fs.statSync(repoDir).isDirectory()) fatal(`目录不存在: ${repoDir}`);
  const armList = arms.split(",").map((a) => a.trim()).filter((a) => a !== "");
  if (armList.length === 0) fatal("-arms 为空");

  const repoRoot = path.resolve(import.meta.dirname, "..", "..");
  const files: string[] = [];
  walkCFiles(repoDir, files);
  files.sort((a, b) => byteCompare(a.split(path.sep).join("/"), b.split(path.sep).join("/")));
  if (files.length === 0) fatal(`${repoDir} 内无 .c 文件`);
  // PR #513 审阅 P3：棘轮机械下限——分支零签名文件（GPL 取舍）意味着「文件被
  // 删/替换仍全绿」的结构性缺口。**等值断言**（非下限——处置批实测下限形态
  // 被误指 407 全集目录轻松滑过〔本地 checkout 停在 fix2 态工作区的乌龙〕，
  // CI 免疫但本地复验无信号）：vitro-green 分支检出必须恰为 MIN_FILES 份；
  // 晋升新文件时同步上调（2026-11-14 建支态 = 166）。
  const MIN_FILES = 166;
  if (files.length !== MIN_FILES) {
    fatal(`语料面漂移: ${files.length} != MIN_FILES ${MIN_FILES}（vitro-green 分支检出应恰为 ${MIN_FILES} 份——多了=repo 误指他分支/目录〔棘轮分支外还有 fix2 态 407 全集〕，少了=语料缩水；晋升新文件须同步上调常量）`);
  }
  process.stderr.write(`green_probe: ${files.length} 文件 × ${armList.length} 臂 (${armList.join("/")})\n`);

  const failures: string[] = [];
  const divergences: string[] = [];
  let done = 0;
  for (const f of files) {
    const rel = path.relative(repoDir, f).split(path.sep).join("/");
    const armRes = new Map<string, ArmResult>();
    for (const arm of armList) {
      const r = await runOneArm(repoRoot, arm, f, timeoutMs);
      armRes.set(arm, r);
      if (!r.ok) failures.push(`${rel} [${arm}] ${r.detail}`);
    }
    const div = armDivergence(armRes);
    if (div !== null) divergences.push(`${rel} 臂间分叉: ${div}`);
    done++;
    if (done % 25 === 0 || done === files.length) process.stderr.write(`  ${done}/${files.length}\n`);
  }

  const summary = {
    files: files.length,
    arms: armList,
    failures: failures.length,
    divergences: divergences.length,
  };
  process.stdout.write(`${JSON.stringify(summary)}\n`);
  if (failures.length > 0) {
    process.stdout.write(`FAILURES:\n${failures.join("\n")}\n`);
  }
  if (divergences.length > 0) {
    process.stdout.write(`ARM_DIVERGENCE:\n${divergences.join("\n")}\n`);
  }
  if (failures.length > 0 || divergences.length > 0) {
    process.stderr.write(`green_probe 红: ${failures.length} 失败 + ${divergences.length} 臂间分叉\n`);
    return 1;
  }
  process.stderr.write(`green_probe 绿: ${files.length} 文件三臂全绿一致\n`);
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e: unknown) => fatal(e instanceof Error ? e.message : String(e)),
  );
}
