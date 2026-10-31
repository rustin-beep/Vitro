#!/usr/bin/env node
// protocol_frames —— serve 协议帧字段级冻结测试（Go→.mts 重写，refs #273；原 S7 批四 2026-10-04）。
//
// 形态：固定请求序列发往 MoonBit serve（native 臂或 --backend-wasm 统一入口壳），
// 每帧响应经 canonicalize（键排序归一）→ compact 单行 → 文本级 mask（规则外置
// rules.json）→ 与入库 baseline.jsonl 逐帧比对。
//
// 义务：
//   - 基线冻结（默认 --check）：帧与基线比对——防实现漂移；
//   - 基线刷新（--update-baseline，人工令）：以 MoonBit 臂真值重建；
//   - 退役形态：--diff-hosts（含 --audit-skips）依赖 rust 双宿主，删区后 fatal。
//
// 覆盖面边界：非 ASCII delta 值域不在本闸覆盖内（skip 为方法粒度）。
//
// 用法：node scripts/protocol_frames/main.mts [--backend-wasm] [--diff-hosts]
//       [--update-baseline] [--audit-skips] [--selftest]
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { spawn } from "node:child_process";
import type { ChildProcess } from "node:child_process";
import { pathToFileURL } from "node:url";
import { canonicalizeText } from "../internal/canonicalize.mts";
import { ensureFresh } from "../internal/freshness.mts";

export const RULES_PATH = "scripts/protocol_frames/rules.json";
export const BASE_PATH = "scripts/protocol_frames/baseline.jsonl";

export interface Req {
  id: number;
  method: string;
  /** JSON 文本（nil 参数留空） */
  params: string;
}

/** 固定请求序列——覆盖 serve 帧面方法族。序列变更 = 行为变更，显式改代码走评审。 */
export function requestTable(): Req[] {
  return [
    { id: 1, method: "compile", params: `{"source":"int main() { int a = 1; a = a + 1; return a; }"}` },
    { id: 2, method: "compile", params: `{"source":"int main() { int x = ; }"}` },
    { id: 3, method: "compile", params: `{"source":"#include <stdio.h>\\nint main() { printf(\\"你好 vitr\\\\u006f\\"); printf(\\"\\\\\\\\x41\\\\\\\\x42\\"); return 0; }"}` },
    { id: 4, method: "run", params: `{"deterministic":true}` },
    { id: 5, method: "compile", params: `{"source":"int main() { int a = 0; int b = 1 / a; return b; }"}` },
    { id: 6, method: "run", params: `{"deterministic":true}` },
    { id: 7, method: "output.delta", params: `{"cursor":0}` },
    { id: 8, method: "capabilities", params: `` },
    { id: 9, method: "error_catalog", params: `` },
    { id: 10, method: "semantic_labels", params: `` },
    { id: 11, method: "contracts", params: `` },
    { id: 12, method: "config.get", params: `` },
    { id: 13, method: "config.set", params: `{"max_steps":5000}` },
    { id: 14, method: "config.get", params: `` },
    { id: 15, method: "compile", params: `{"source":"int fib(int n) { if (n < 2) return n; return fib(n-1) + fib(n-2); }\\nint main() { return fib(4); }"}` },
    { id: 16, method: "step.begin", params: `` },
    { id: 17, method: "step.next", params: `` },
    { id: 18, method: "step.next", params: `` },
    { id: 19, method: "payload.get", params: `{"step":0}` },
    { id: 20, method: "seek", params: `{"step":3}` },
    { id: 21, method: "breakpoints.set", params: `{"lines":[2]}` },
    { id: 22, method: "step.next", params: `` },
    { id: 23, method: "ast.dump", params: `{"source":"int main() { return 42; }"}` },
    { id: 24, method: "memory.regions", params: `` },
    { id: 25, method: "no.such.method", params: `` },
    { id: 26, method: "compile", params: `` },
    { id: 27, method: "session.reset", params: `` },
    { id: 28, method: "compile", params: `{"source":"int main() { return 7; }"}` },
    { id: 29, method: "run", params: `{"deterministic":true}` },
    { id: 30, method: "compile", params: `{"source":"#include <stdlib.h>\\n#include <stdio.h>\\nint main() { printf(\\"leak test\\"); int* a = malloc(4); int* b = malloc(8); return 0; }"}` },
    { id: 31, method: "run", params: `{"deterministic":true}` },
    { id: 32, method: "output.delta", params: `{"cursor":0}` },
    { id: 33, method: "icons.get", params: `` },
    { id: 34, method: "icons.get", params: `{"ids":["uaf","timeline"]}` },
    { id: 35, method: "compile", params: `{"source":"int main() { int a = 0; return 1 / a; }"}` },
    ...Array.from({ length: 1 }, () => ({ id: 36, method: "step.begin", params: `` })),
    ...Array.from({ length: 12 }, (_, i) => ({ id: 37 + i, method: "step.next", params: `` })),
  ];
}

interface MaskRule {
  name: string;
  pattern: string;
  replace: string;
  reason: string;
}

export interface RulesDoc {
  skip_methods: Record<string, string>;
  masks: MaskRule[];
}

const compiled: Array<{ re: RegExp; replace: string; name: string }> = [];
let skipMethods: Record<string, string> = {};
let backendWasm = false;

function fatal(msg: string): never {
  process.stderr.write(`错误: ${msg}\n`);
  process.exit(2);
}

/** 项目根：VITRO_ROOT 优先，否则按 go.mod 上溯（与 Go 版同口径）。 */
export function projectRoot(): string {
  const env = process.env["VITRO_ROOT"];
  if (env !== undefined && env !== "") return env;
  let dir = process.cwd();
  for (;;) {
    if (fs.existsSync(path.join(dir, "go.mod"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) fatal("未找到项目根（go.mod）——从仓库根运行或设 VITRO_ROOT");
    dir = parent;
  }
}

export function loadRules(root: string): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(path.join(root, RULES_PATH), "utf8");
  } catch (e) {
    fatal(`读 mask 规则失败（${RULES_PATH}）: ${e instanceof Error ? e.message : String(e)}`);
  }
  let r: RulesDoc;
  try {
    r = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`mask 规则非法 JSON: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (Object.keys(r.skip_methods ?? {}).length === 0 && (r.masks ?? []).length === 0) {
    fatal("规则为空集（空集不得绿——已知分叉面须显式登记）");
  }
  skipMethods = r.skip_methods ?? {};
  for (const m of r.masks ?? []) {
    let re: RegExp;
    try {
      re = new RegExp(m.pattern, "g");
    } catch (e) {
      fatal(`mask 规则 ${m.name} 正则非法: ${e instanceof Error ? e.message : String(e)}`);
    }
    compiled.push({ re, replace: m.replace, name: m.name });
  }
  return r;
}

/** 帧处理管线：raw → canonicalize（键排序/转义归一）→ compact 单行 → mask。 */
export function frameLine(raw: string): string {
  // canonicalizeText 的产出可能是带空白的形态；Go 版还过一道 json.Compact，
  // 这里用 parse→stringify 复刻"压缩为单行"（JSON.parse 保留键序，不破坏归一结果）
  const s0 = JSON.stringify(JSON.parse(canonicalizeText(raw)));
  let s = s0;
  for (const m of compiled) s = s.replace(m.re, m.replace);
  return s;
}

class Host {
  readonly name: string;
  private readonly proc: ChildProcess;
  private readonly queue: string[] = [];
  private waiter: ((line: string) => void) | null = null;
  private closed = false;

  constructor(name: string, exe: string, args: string[]) {
    // 不用参数属性（readonly x: T 在 constructor 里）：node strip-only 模式不支持
    this.name = name;
    const isWasmShell = exe.endsWith(".js");
    this.proc = spawn(isWasmShell ? "node" : exe, isWasmShell ? [exe, "serve"] : args, {
      stdio: ["pipe", "pipe", "ignore"],
    });
    const rl = readline.createInterface({ input: this.proc.stdout! });
    rl.on("line", (line) => {
      if (this.waiter !== null) {
        const w = this.waiter;
        this.waiter = null;
        w(line);
      } else {
        this.queue.push(line);
      }
    });
    this.proc.on("exit", () => {
      this.closed = true;
    });
    this.proc.on("error", (e) => fatal(`启动 ${name} 失败（${exe}）: ${e.message}`));
  }

  request(r: Req): Promise<string> {
    const line = r.params === "" ? `{"id":${r.id},"method":"${r.method}"}` : `{"id":${r.id},"method":"${r.method}","params":${r.params}}`;
    this.proc.stdin!.write(line + "\n");
    const queued = this.queue.shift();
    if (queued !== undefined) return Promise.resolve(queued);
    return new Promise<string>((resolve) => {
      this.waiter = resolve;
    });
  }

  async stop(): Promise<void> {
    this.proc.stdin!.end();
    await new Promise<void>((resolve) => {
      const t = setTimeout(() => {
        this.proc.kill();
        resolve();
      }, 10_000);
      this.proc.on("exit", () => {
        clearTimeout(t);
        resolve();
      });
      if (this.closed) {
        clearTimeout(t);
        resolve();
      }
    });
  }
}

/** 单臂帧收集：逐请求发、逐帧处理。 */
async function collectFrames(name: string, exe: string, args: string[], table: Req[]): Promise<string[]> {
  const host = new Host(name, exe, args);
  const frames: string[] = [];
  try {
    for (const r of table) {
      const raw = await host.request(r);
      try {
        frames.push(frameLine(raw));
      } catch (e) {
        fatal(`${name} 臂帧处理失败（id=${r.id} ${r.method}）: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
  } finally {
    await host.stop();
  }
  return frames;
}

export function diffAgainstBase(arm: string, base: string[], actual: string[], table: Req[]): string[] {
  if (base.length !== actual.length) {
    return [`[DRIFT] ${arm} 帧数不等：基线 ${base.length} ≠ 实际 ${actual.length}`];
  }
  const out: string[] = [];
  actual.forEach((f, i) => {
    if (f !== base[i]) {
      out.push(`[DRIFT] ${arm} 帧 ${table[i]!.id}（${table[i]!.method}）\n  基线: ${base[i]}\n  实际: ${f}`);
    }
  });
  return out;
}

export function readBaseline(root: string): string[] {
  let raw: string;
  try {
    raw = fs.readFileSync(path.join(root, BASE_PATH), "utf8");
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code === "ENOENT") fatal(`读基线失败: 基线不存在（${BASE_PATH}）——先 --update-baseline 生成并入库`);
    fatal(`读基线失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  return raw.replace(/\n+$/, "").split("\n").filter((l) => l !== "");
}

export function writeBaseline(root: string, frames: string[]): void {
  const body = frames.map((f) => f + "\n").join("");
  try {
    fs.writeFileSync(path.join(root, BASE_PATH), body, "utf8");
  } catch (e) {
    fatal(`写基线失败: ${e instanceof Error ? e.message : String(e)}`);
  }
}

/** J9 三锚：mask 生效 / 非法 JSON 拒绝 / 基线比对判定必红。 */
export function selfTest(): number {
  const raw = `{"result":{"engine_version":"0.1.0 (abc1234)","note":"x"},"id":1}`;
  const line = frameLine(raw);
  if (line.includes("abc1234")) {
    process.stdout.write("selftest: FAIL——engine_version mask 未生效（假绿面）\n");
    process.stdout.write(`  管线输出: ${line}\n`);
    return 2;
  }
  let rejected = false;
  try {
    frameLine(`{"broken":`);
  } catch {
    rejected = true;
  }
  if (!rejected) {
    process.stdout.write("selftest: FAIL——非法 JSON 未被拒绝（fail loud 透传断裂）\n");
    return 2;
  }
  const tbl = requestTable().slice(0, 3);
  const base = [`{"a":1}`, `{"b":2}`, `{"c":3}`];
  const tampered = [`{"a":1}`, `{"b":99}`, `{"c":3}`];
  const drifts = diffAgainstBase("selftest", base, tampered, tbl);
  if (drifts.length !== 1 || !drifts[0]!.includes("[DRIFT]")) {
    process.stdout.write("selftest: FAIL——基线比对判定对篡改帧不红（比对逻辑未被验证）\n");
    return 2;
  }
  if (diffAgainstBase("selftest", base, base, tbl).length !== 0) {
    process.stdout.write("selftest: FAIL——一致帧产出伪 DRIFT\n");
    return 2;
  }
  process.stdout.write("selftest：mask 生效锚 + 非法 JSON 拒绝锚 + 基线比对红锚 通过\n");
  return 0;
}

export async function main(argv: string[]): Promise<number> {
  let diffHosts = false;
  let update = false;
  let auditSkips = false;
  let selftest = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    const eq = a.indexOf("=");
    const flag = eq >= 0 ? a.slice(0, eq) : a;
    switch (flag) {
      case "-diff-hosts":
      case "--diff-hosts":
        diffHosts = true;
        break;
      case "-backend-wasm":
      case "--backend-wasm":
        backendWasm = true;
        break;
      case "-update-baseline":
      case "--update-baseline":
        update = true;
        break;
      case "-audit-skips":
      case "--audit-skips":
        auditSkips = true;
        break;
      case "-selftest":
      case "--selftest":
        selftest = true;
        break;
      default:
        fatal(`未知参数: ${a}（可用：--diff-hosts / --backend-wasm / --update-baseline / --audit-skips / --selftest）`);
    }
  }
  const root = projectRoot();
  // #392 审阅 P2-1（2026-10-31）：MoonBit native 产物统一带 .exe（跨平台）——
  // 平台三元 Linux 指向不存在的 serve 断供（#359 同 root cause，且本闸无
  // VITRO_SERVE_MB override → Linux 完全跑不了）
  let mbServe = path.join(root, "moonbit/_build/native/debug/build/cmd/serve", "serve.exe");
  if (backendWasm) {
    const shell = path.join(root, "moonbit/_build/js/release/build/cmd/vitro_wasm/vitro_wasm.js");
    const wasmMod = path.join(root, "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm");
    if (!fs.existsSync(shell)) fatal(`wasm 臂产物缺失 ${shell}（统一入口壳）`);
    ensureFresh("protocol_frames", wasmMod, ["build", "--release", "--target", "wasm-gc", "gateway/wasm"]);
    ensureFresh("protocol_frames_glue", shell, ["build", "--release", "--target", "js", "cmd/vitro_wasm"]);
    mbServe = shell;
  } else {
    ensureFresh("protocol_frames", mbServe, ["build", "--target", "native", "cmd/serve"]);
  }

  loadRules(root);
  if (selftest) return selfTest();
  if (auditSkips) diffHosts = true;

  let table = requestTable();
  if (!auditSkips) {
    const kept: Req[] = [];
    for (const r of table) {
      const reason = skipMethods[r.method];
      if (reason !== undefined) {
        process.stdout.write(`[SKIP] ${r.method}（${reason}）\n`);
        continue;
      }
      kept.push(r);
    }
    table = kept;
  }

  // rust 臂（退役形态）：不存在 = oracle 已删区退役 → MoonBit 单臂基线比
  const rustCli = path.join(root, "native/target/release/vitro_cli.exe");
  const useRust = fs.existsSync(rustCli);
  if (!useRust) process.stderr.write("[retired] rust 臂不可用（oracle 已删区退役）——MoonBit 单臂基线比\n");
  const rustFrames = useRust ? await collectFrames("rust", rustCli, ["serve"], table) : [];

  if (update) {
    const frames = await collectFrames("moonbit", mbServe, backendWasm ? ["serve"] : [], table);
    writeBaseline(root, frames);
    process.stdout.write(`基线已刷新（moonbit 臂，${frames.length} 帧）→ ${BASE_PATH}\n`);
    return 0;
  }

  const mbFrames = await collectFrames("moonbit", mbServe, backendWasm ? ["serve"] : [], table);
  let exitCode = 0;

  if (diffHosts) {
    if (!useRust) {
      fatal("--diff-hosts（含 --audit-skips 强制互比）需双宿主；rust 臂已随删区退役——skip 帧审计改走 MoonBit 单臂基线比 + skip_methods 清单人工复核");
    }
    if (rustFrames.length !== mbFrames.length) fatal(`两臂帧数不等：rust=${rustFrames.length} moonbit=${mbFrames.length}`);
    rustFrames.forEach((rf, i) => {
      if (rf !== mbFrames[i]) {
        exitCode = 1;
        process.stdout.write(`[DIFF] 帧 ${table[i]!.id}（${table[i]!.method}）\n  rust:   ${rf}\n  moonbit: ${mbFrames[i]}\n`);
      }
    });
    if (exitCode === 0) process.stdout.write(`双宿主互比：${rustFrames.length} 帧全部一致\n`);
    return exitCode;
  }

  const base = readBaseline(root);
  if (base.length !== mbFrames.length) {
    fatal(`基线帧数 ${base.length} ≠ 序列帧数 ${mbFrames.length}——序列已变更，须 --update-baseline 重建（人工评审令）`);
  }
  const arms: Array<{ name: string; frames: string[] }> = useRust
    ? [{ name: "rust", frames: rustFrames }, { name: "moonbit", frames: mbFrames }]
    : [{ name: "moonbit", frames: mbFrames }];
  for (const arm of arms) {
    const drifts = diffAgainstBase(arm.name, base, arm.frames, table);
    if (drifts.length > 0) {
      exitCode = 1;
      for (const d of drifts) process.stdout.write(d + "\n");
    }
  }
  if (exitCode === 0) process.stdout.write(`基线冻结比对：${arms.length} 臂 × ${mbFrames.length} 帧全部一致\n`);
  return exitCode;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  void main(process.argv.slice(2)).then((rc) => process.exit(rc));
}
