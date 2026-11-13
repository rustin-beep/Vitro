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
  const { spawn } = await import("node:child_process");
  const vitroSh = path.join(repoRoot, "scripts", "bin", "vitro");
  return new Promise<ArmResult>((resolve) => {
    const child = spawn("sh", [vitroSh, "--backend", arm, "compile", "--json", cfile], {
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });
    let out = "";
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        child.kill();
        resolve({ ok: false, detail: `timeout(${arm} ${timeoutMs}ms)`, signature: "\0timeout" });
      }
    }, timeoutMs);
    child.stdout.on("data", (c: Buffer) => {
      out += c.toString("utf8");
    });
    child.on("error", (e: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ ok: false, detail: `spawn失败: ${e.message}`, signature: "\0spawn" });
    });
    child.on("close", (code: number | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const parsed = parseDiagLine(out);
      if (parsed === null) {
        resolve({ ok: false, detail: `出口不可解析(rc=${code}): ${out.trim().slice(0, 120)}`, signature: "\0parse" });
        return;
      }
      const errs = errorCount(parsed.diagnostics);
      if (errs > 0) {
        const first = parsed.diagnostics.find((d) => d.severity === "error") as Diag;
        resolve({ ok: false, detail: `${errs} error: ${first.code} ${first.line}:${first.column} ${first.message.slice(0, 60)}`, signature: signatureOf(parsed.diagnostics) });
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
