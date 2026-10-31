#!/usr/bin/env node
// serve_smoke —— `serve`（JSON-lines 会话模式）端到端冒烟 + 协议断言
// （Go→.mts 重写，refs #273；原 main.go 1274 行，D5 后续批次第一站）。
//
// 防线定位：出口 3 的协议契约验证——id 关联 / 错误帧同构 / session.reset /
// 与 capi 共用入口语义（StepPayload 字段、隔离预算默认值等）。
//
// 迁移中锚定的口径：
//   - `断言数: N  (PASS x / FAIL y)` 自报行是 scripts/facts 的采集锚点
//     （serve_smoke_assertions 真值），格式不得改动；
//   - MoonBit 双臂由 freshness 新鲜度门禁守（mtime 触发 + 构建复核）；
//   - RSS 护栏证红通道：`VITRO_RSS_BUDGET_MB=5`（预算压到 5MB 必红）；
//   - 响应解析走 json.Number 等价面（Go `UseNumber`）：本版以 JSON.parse 取值 +
//     原始字面量文本处理（step_index 的整性判定用字面量，见 isIntStr）；
//   - **RSS 采样口径替换**（#292 批，唯一有意差异）：Go 走 `probeutil` 的 Windows
//     psapi（`GetProcessMemoryInfo.PeakPagefileUsage`）；Node 无该 API，改用 CIM
//     `Win32_Process.PeakPageFileUsage`（**同一底层计数器**，单位同为字节）。
//     采样时刻仍在每次远距 seek 返回后，故判定行（预算内/超预算）可比；4 行
//     「seek(…) 后提交峰值 ≈ N MB」的数值属测得值不可逐字比 → parity 用 maskLines 屏蔽。
//
// 用法（仓库根）：
//
//	node scripts/serve_smoke/main.mts -moonbit          # native cmd/serve exe
//	node scripts/serve_smoke/main.mts --backend-wasm    # 统一入口壳（node 消费 gateway wasm.wasm）
//	  [--audit-exemptions]                              # D19 僵尸审计（豁免全失效真跑一轮）
//	  VITRO_CLI=<exe>                                   # 显式注入通道（J9 埋雷用）
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { ensureFresh } from "../internal/freshness.mts";
import { projectRoot, truncateRunes } from "../internal/capi.mts";

// ── 全局状态（与 Go 版同名）──────────────────────────────────────
let failures: string[] = [];
let assertions = 0;
let exempted = 0;
let mbMode = false;
let backendWasm = false;
let injectedMB = false;
let auditAll = false;
let auditVerdict: Map<string, string> | null = null;
let auditNames: string[] = [];
let auditSet = new Set<string>();
let mbExempt = new Map<string, string>();
let mbBatches = new Map<string, string>();
let expectMemoryGlobalRegionLimit = 0;

const DEFAULT_QUARANTINE_BUDGET = 256 * 1024;

const PROGRAM =
  "#include <stdio.h>\n" + "int main(){ int a = 1; int b = 2; printf(\"%d\", a + b); return 0; }\n";

interface Request {
  id: number;
  method: string;
  params?: Record<string, unknown>;
}

const REQUESTS: Request[] = [
  { id: 1, method: "ping" },
  { id: 2, method: "compile", params: { source: PROGRAM } },
  { id: 3, method: "run" },
  { id: 4, method: "output.delta", params: { cursor: 0 } },
  { id: 5, method: "step.begin" },
  { id: 6, method: "step.next" },
  { id: 7, method: "step.next" },
  { id: 8, method: "payload.get", params: { start: 0, end: 50 } },
  { id: 9, method: "breakpoints.set", params: { lines: [3] } },
  { id: 10, method: "seek", params: { step: 1 } },
  { id: 11, method: "memory.regions" },
  { id: 12, method: "config.set", params: { quarantine_budget: 0 } },
  { id: 13, method: "compile", params: { source: "int main(){ int x = ; }" } },
  { id: 14, method: "no.such.method" },
  { id: 15, method: "session.reset" },
  { id: 16, method: "capabilities" },
  { id: 17, method: "semantic_labels" },
  { id: 18, method: "contracts" },
  { id: 19, method: "session.create" },
  { id: 20, method: "diagnostics_probe", params: { source: "int x = 1" } },
  {
    id: 21,
    method: "diagnostics_probe",
    params: {
      source: "int binary_search(int* a, int n){ return a[0]; }\nint main(){ return 0; }",
      records: [
        { ts: 0, ok: false, codes: [3051] },
        { ts: 1, ok: false, codes: [3021] },
        { ts: 2, ok: false, codes: [3051] },
        { ts: 3, ok: true, codes: [] },
      ],
    },
  },
  {
    id: 23,
    method: "compile",
    params: {
      source:
        'long time(long*); long clock();\nint main(){ long t = time((long*)0); long c = clock();\n  printf("t=%d c=%d\\n", (int)t, (int)(c/1000)); return 0; }',
    },
  },
  { id: 24, method: "run" },
  { id: 25, method: "output.delta", params: { cursor: 0, stream: "stdout" } },
  { id: 22, method: "shutdown" },
];

// ── JSON 访问 helper ────────────────────────────────────────────

type Obj = Record<string, unknown>;

const asObj = (v: unknown): Obj | null =>
  typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Obj) : null;
const asArr = (v: unknown): unknown[] | null => (Array.isArray(v) ? v : null);
const isBool = (v: unknown, want: boolean): boolean => typeof v === "boolean" && v === want;
const strOf = (v: unknown): string => (typeof v === "string" ? v : "");
const numEq = (v: unknown, want: number): boolean => typeof v === "number" && v === want;
const numFloat = (v: unknown): number => (typeof v === "number" ? v : -1);
const numGe1 = (v: unknown): boolean => typeof v === "number" && v >= 1;
const isIntStr = (s: string): boolean => /^-?\d+$/.test(s);
const containsStr = (list: string[], want: string): boolean => list.includes(want);
const min = (a: number, b: number): number => (a < b ? a : b);

/** FAIL detail：子对象序列化后按 rune 截断（Go tailMap 同形）。 */
function tailMap(m: Obj | null): string {
  if (m === null) return "null";
  return truncateRunes(JSON.stringify(m), 150);
}

function tailMaps(ms: Obj[]): string {
  return truncateRunes(JSON.stringify(ms), 150);
}

// ── 断言计数与豁免 ──────────────────────────────────────────────

function tally(): void {
  assertions++;
}

export function check(cond: boolean, label: string, detail: string): void {
  if (mbMode || backendWasm || injectedMB) {
    const reason = mbExempt.get(label);
    if (reason !== undefined) {
      exempted++;
      process.stdout.write(`  SKIP  ${label}（豁免：${reason}）\n`);
      return;
    }
  }
  if (auditVerdict !== null) {
    if (!auditVerdict.has(label)) auditVerdict.set(label, cond ? "PASS" : "FAIL");
  }
  tally();
  if (cond) {
    process.stdout.write(`  PASS  ${label}\n`);
  } else {
    process.stdout.write(`  FAIL  ${label}  ${detail}\n`);
    if (auditSet.has(label)) return; // 审计轮：原豁免名的 FAIL = 合法豁免
    failures.push(label);
  }
}

// ── serve 批执行 ────────────────────────────────────────────────

export interface BatchResult {
  stdout: string;
  stderr: string;
  exitCode: number;
  timedOut: boolean;
}

/** 一次性喂全部请求、收全部响应（主批/边界批/串帧批/超长行批共用）。 */
export function runServeBatch(exe: string, payload: string, timeoutMs: number): BatchResult {
  const [cmd, argv] = backendWasm
    ? [process.execPath, [exe, "serve"]]
    : mbMode
      ? [exe, []]
      : [exe, ["serve"]];
  const r = spawnSync(cmd as string, argv as string[], {
    input: payload,
    timeout: timeoutMs,
    maxBuffer: 64 * 1024 * 1024,
  });
  const stdout = (r.stdout ?? Buffer.alloc(0)).toString("utf8");
  const stderr = (r.stderr ?? Buffer.alloc(0)).toString("utf8");
  const timedOut = r.error !== undefined && (r.error as NodeJS.ErrnoException).code === "ETIMEDOUT";
  let exitCode = 0;
  if (timedOut) exitCode = -1;
  else if (r.error !== undefined) exitCode = -1;
  else exitCode = r.status ?? -1;
  return { stdout, stderr, exitCode, timedOut };
}

export function nonEmptyLines(stdout: string): string[] {
  return stdout.split("\n").filter((l) => l.trim() !== "");
}

/** Go `probeutil.Tail(s, n)`：取末尾 n 个 rune。 */
export function tailRunes(s: string, n: number): string {
  const chars = [...s];
  return chars.length <= n ? s : chars.slice(chars.length - n).join("");
}

// ── 期望值 / 豁免表 ─────────────────────────────────────────────

export function loadExpectations(): string | null {
  const p = path.join("scripts", "serve_smoke", "expectations.json");
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (e) {
    return `读期望值资产失败: ${(e as Error).message}`;
  }
  let doc: { memory_model?: { global_region_limit?: number } };
  try {
    doc = JSON.parse(raw) as typeof doc;
  } catch (e) {
    return `期望值资产非法 JSON: ${(e as Error).message}`;
  }
  const v = doc.memory_model?.global_region_limit ?? 0;
  if (!(v > 0)) return "期望值资产字段缺失: memory_model.global_region_limit";
  expectMemoryGlobalRegionLimit = v;
  return null;
}

export function loadMoonBitExemptions(): {
  assertions: Map<string, string>;
  batches: Map<string, string>;
  err: string | null;
} {
  const p = path.join("scripts", "serve_smoke", "moonbit_exemptions.json");
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (e) {
    return { assertions: new Map(), batches: new Map(), err: `读豁免表失败: ${(e as Error).message}` };
  }
  let doc: {
    assertions?: Record<string, string>;
    batches?: Record<string, string>;
    wasm_assertions?: Record<string, string>;
  };
  try {
    doc = JSON.parse(raw) as typeof doc;
  } catch (e) {
    return { assertions: new Map(), batches: new Map(), err: `豁免表非法 JSON: ${(e as Error).message}` };
  }
  const assertions = new Map(Object.entries(doc.assertions ?? {}));
  const batches = new Map(Object.entries(doc.batches ?? {}));
  const wasm = doc.wasm_assertions ?? {};
  if (Object.keys(wasm).length > 0 && backendWasm) {
    for (const [k, v] of Object.entries(wasm)) assertions.set(k, v);
  }
  return { assertions, batches, err: null };
}

export function resolveMoonBitExe(): string {
  const override = process.env["VITRO_SERVE_MB"];
  if (override !== undefined && override !== "") return override;
  // #359（2026-10-30）：MoonBit native 产物统一带 .exe（跨平台）——平台三元 Linux 断供
  return path.join(projectRoot(), "moonbit", "_build", "native", "debug", "build", "cmd", "serve", "serve.exe");
}

// ── 小工具 ──────────────────────────────────────────────────────

function idListOf(responses: Obj[]): string[] {
  return responses.map((r) => (typeof r["id"] === "number" ? String(r["id"]) : String(r["id"])));
}

function byIdMap(parsed: Obj[]): { byID: Map<number, Obj>; nullID: Obj[] } {
  const byID = new Map<number, Obj>();
  const nullID: Obj[] = [];
  for (const r of parsed) {
    const id = r["id"];
    if (typeof id === "number" && Number.isInteger(id)) byID.set(id, r);
    else nullID.push(r);
  }
  return { byID, nullID };
}

function frameComplete(r: Obj | undefined): boolean {
  if (r === undefined) return false;
  const hasR = "result" in r;
  const hasE = "error" in r;
  return hasR !== hasE;
}

export function parseFrame(line: string): Obj {
  const v = JSON.parse(line) as unknown;
  const o = asObj(v);
  if (o === null) throw new Error("顶层不是对象");
  return o;
}

// ── main ───────────────────────────────────────────────────────

export async function runMain(argv: readonly string[]): Promise<number> {
  const opts: { audit: boolean } = { audit: false };
  for (const a of argv) {
    if (a === "-moonbit" || a === "--moonbit") mbMode = true;
    else if (a === "-backend-wasm" || a === "--backend-wasm") backendWasm = true;
    else if (a === "-audit-exemptions" || a === "--audit-exemptions") opts.audit = true;
    else {
      process.stdout.write(`flag provided but not defined: ${a}\n`);
      return 2;
    }
  }
  auditAll = opts.audit;
  if (auditAll && !mbMode && !backendWasm) {
    process.stdout.write("错误: --audit-exemptions 须与 --moonbit/--backend-wasm 同用（豁免面仅作用于 MoonBit 产物臂）\n");
    return 2;
  }
  const expErr = loadExpectations();
  if (expErr !== null) {
    process.stdout.write(`错误: ${expErr}\n`);
    return 2;
  }

  let exe: string;
  if (backendWasm) {
    const l = loadMoonBitExemptions();
    if (l.err !== null) {
      process.stdout.write(`错误: ${l.err}\n`);
      return 2;
    }
    mbExempt = l.assertions;
    mbBatches = l.batches;
    if (auditAll) startAuditRound();
    const shell = path.join(projectRoot(), "moonbit", "_build", "js", "release", "build", "cmd", "vitro_wasm", "vitro_wasm.js");
    const wasmMod = path.join(projectRoot(), "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm");
    if (!fs.existsSync(shell)) {
      process.stdout.write(`错误: wasm 臂产物缺失 ${shell}（统一入口壳）\n`);
      return 2;
    }
    ensureFresh("serve_smoke", wasmMod, ["build", "--release", "--target", "wasm-gc", "gateway/wasm"]);
    ensureFresh("serve_smoke_glue", shell, ["build", "--release", "--target", "js", "cmd/vitro_wasm"]);
    exe = shell;
    process.stdout.write(`wasm 臂 serve: node ${shell} serve（豁免 ${mbExempt.size} 断言 + ${mbBatches.size} 整批）\n`);
  } else if (mbMode) {
    const l = loadMoonBitExemptions();
    if (l.err !== null) {
      process.stdout.write(`错误: ${l.err}\n`);
      return 2;
    }
    mbExempt = l.assertions;
    mbBatches = l.batches;
    if (auditAll) startAuditRound();
    exe = resolveMoonBitExe();
    ensureFresh("serve_smoke", exe, ["build", "--target", "native", "cmd/serve"]);
    process.stdout.write(`MoonBit serve: ${exe}（豁免 ${mbExempt.size} 断言 + ${mbBatches.size} 整批）\n`);
  } else if ((process.env["VITRO_CLI"] ?? "") !== "") {
    exe = process.env["VITRO_CLI"] as string;
    if (!fs.existsSync(exe)) {
      process.stdout.write(`错误: VITRO_CLI 指定的 ${exe} 不存在\n`);
      return 2;
    }
    const ping = runServeBatch(exe, '{"id":0,"method":"session.create","params":{}}\n', 15_000);
    const firstLine = (ping.stdout.split("\n")[0] ?? "").trim();
    if (ping.timedOut || !firstLine.startsWith("{")) {
      process.stdout.write(`错误: VITRO_CLI 注入的 ${exe} 不是 serve 形态（首响应非 JSON 帧）\n`);
      process.stdout.write("  总入口 exe 的 serve 子命令已按 #37 B1 拒绝收拢——本通道期待 cmd/serve 产物（stdin JSONL 主程序）\n");
      process.stdout.write("  正道：node scripts/serve_smoke/main.mts -moonbit（自动寻址/构建 cmd/serve）\n");
      process.stdout.write("  注入：VITRO_CLI=moonbit/_build/native/debug/build/cmd/serve/serve.exe（或 VITRO_SERVE_MB 同路径）\n");
      return 2;
    }
    const l = loadMoonBitExemptions();
    if (l.err !== null) {
      process.stdout.write(`错误: ${l.err}\n`);
      return 2;
    }
    mbExempt = l.assertions;
    mbBatches = l.batches;
    injectedMB = true;
    process.stdout.write(`vitro_cli（注入）: ${exe}（豁免 ${mbExempt.size} 断言 + ${mbBatches.size} 整批）\n`);
  } else {
    process.stdout.write("错误: 未选被测物臂——rust 臂已退役（2026-10-05 删区）。现役两枝：\n");
    process.stdout.write("  node scripts/serve_smoke/main.mts -moonbit            # native cmd/serve exe\n");
    process.stdout.write("  node scripts/serve_smoke/main.mts --backend-wasm      # 统一入口壳（node 消费 gateway wasm.wasm）\n");
    process.stdout.write("（VITRO_CLI=<exe> 显式注入通道保留——J9 埋雷用）\n");
    return 2;
  }

  return await mainBatchAndBatches(exe);
}

function startAuditRound(): void {
  auditVerdict = new Map();
  auditSet = new Set();
  auditNames = [...mbExempt.keys()];
  for (const k of auditNames) auditSet.add(k);
  process.stdout.write(`审计轮：${auditNames.length} 条断言豁免全部失效真跑（PASS/未触达 = 僵尸）\n`);
  mbExempt = new Map();
}

async function mainBatchAndBatches(exe: string): Promise<number> {
  // ── 主批：25 请求协议契约 ──
  const payload = REQUESTS.map((r) => JSON.stringify(normalizeReq(r))).join("\n") + "\n";
  const main = runServeBatch(exe, payload, 120_000);
  if (main.timedOut) {
    process.stdout.write("  FAIL  主批超时（疑似挂起）\n");
    return 1;
  }
  process.stdout.write(`exit=${main.exitCode}\n`);
  const lines = nonEmptyLines(main.stdout);
  process.stdout.write(`responses=${lines.length} (requests=${REQUESTS.length})\n`);
  check(main.exitCode === 0, "进程正常退出", truncateRunes(main.stderr, 300));
  check(lines.length === REQUESTS.length, "每个请求一行响应", "");

  const responses: Obj[] = [];
  for (let i = 0; i < lines.length; i++) {
    try {
      responses.push(parseFrame(lines[i] as string));
    } catch (e) {
      check(false, `响应 ${i} 是合法 JSON`, `${(e as Error).message}: ${truncateRunes(lines[i] as string, 120)}`);
      return 1;
    }
  }

  // id 关联 + 帧同构
  let idsOK = responses.length === REQUESTS.length;
  if (idsOK) {
    for (let i = 0; i < responses.length; i++) {
      if (!numEq((responses[i] as Obj)["id"], (REQUESTS[i] as Request).id)) {
        idsOK = false;
        break;
      }
    }
  }
  check(idsOK, "响应 id 与请求一一对应", JSON.stringify(idListOf(responses)));

  let xorOK = true;
  for (const r of responses) {
    const hasR = "result" in r;
    const hasE = "error" in r;
    if (hasR === hasE) {
      xorOK = false;
      break;
    }
  }
  check(xorOK, "帧同构：result / error 二选一", "");

  let okConsistent = true;
  for (const r of responses) {
    const hasR = "result" in r;
    if (isBool(r["ok"], true) !== hasR) {
      okConsistent = false;
      break;
    }
  }
  check(okConsistent, "ok 与 result/error 一致", "");

  const { byID } = byIdMap(responses);
  const res = (id: number): Obj => asObj(byID.get(id)?.["result"]) ?? {};
  const r1 = res(1);
  check(isBool(r1["pong"], true), "ping 回应 pong", "");
  check(strOf(r1["abi"]) !== "", "ping 携带 ABI 版本", "");

  const r2 = res(2);
  check(isBool(byID.get(2)?.["ok"], true) && isBool(r2["ok"], true), "compile 成功", "");
  check(asArr(r2["diagnostics"]) !== null, "compile 返回 diagnostics 数组", "");

  const r3 = res(3);
  check(strOf(r3["status"]) === "finished", "run 正常结束", tailMap(byID.get(3) ?? null));
  const r4 = res(4);
  const delta = strOf(r4["delta"]);
  check(delta.includes("3"), "output.delta 含程序输出", JSON.stringify(truncateRunes(delta, 80)));
  check(numEq(r4["cursor"], numFloat(r4["total"])), "游标推进到末尾", "");

  // step.next 合并序列（一帧发布缓冲：首调空，其后逐帧）
  let frames: Obj[] = [];
  for (const rid of [6, 7]) {
    const r = res(rid);
    const pl = asArr(r["payloads"]);
    check(pl !== null, `step.next(id=${rid}) 返回 payloads 数组`, "");
    for (const p of pl ?? []) {
      const m = asObj(p);
      if (m !== null) frames = frames.concat([m]);
    }
  }
  check(frames.length > 0, "step.next 帧序列非空（首调空 + 后续逐帧的合并序列）", "");
  const idxSeq = frames.map((p) => (typeof p["step_index"] === "number" ? String(p["step_index"]) : "<非数>"));
  let strictIncr = idxSeq.length > 0;
  for (const s of idxSeq) {
    if (!isIntStr(s)) {
      strictIncr = false;
      break;
    }
  }
  if (strictIncr) {
    for (let i = 1; i < idxSeq.length; i++) {
      const a = Number.parseInt(idxSeq[i - 1] as string, 10);
      const b = Number.parseInt(idxSeq[i] as string, 10);
      if (b !== a + 1) {
        strictIncr = false;
        break;
      }
    }
  }
  check(strictIncr, "step_index 严格递增且无重复投递（spec 附录 A）", JSON.stringify(idxSeq));

  const schemaFields = ["step_index", "code_line", "func_name", "local_vars", "pointer_snapshots"];
  let hasAll = frames.length > 0;
  if (hasAll) {
    const f0 = frames[0] as Obj;
    for (const f of schemaFields) {
      if (!(f in f0)) {
        hasAll = false;
        break;
      }
    }
  }
  check(hasAll, "StepPayload 含 schema 字段", "");

  const pg = res(8);
  check("cache_start_step" in pg && "max_collected_step" in pg, "payload.get 携带窗口字段", "");

  const r9 = res(9);
  const lines3 = asArr(r9["lines"]) ?? [];
  check(lines3.length === 1 && numEq(lines3[0], 3), "breakpoints.set 回显行号", "");

  const r10 = res(10);
  check(isBool(r10["success"], true), "seek 成功", tailMap(byID.get(10) ?? null));

  const regions = res(11);
  check("regions" in regions && "quarantine" in regions, "memory.regions 结构完整", "");
  const quarantine = asObj(regions["quarantine"]) ?? {};
  check(numEq(quarantine["budget"], DEFAULT_QUARANTINE_BUDGET), "默认隔离预算 256KB（与 capi 一致）", tailMap(quarantine));

  // C2：三段式内存地图
  const counts = asObj(regions["region_counts"]) ?? {};
  let countOK = true;
  for (const k of ["global", "stack", "heap"]) if (!(k in counts)) countOK = false;
  check(countOK, "memory.regions 三段式计数（C2）", "");

  const regionList = asArr(regions["regions"]) ?? [];
  let allKinded = true;
  for (const rr of regionList) if (typeof (asObj(rr) ?? {})["kind"] !== "string") allKinded = false;
  check(allKinded, "每个 region 都带 kind 段标识（C2）", "");

  const stackRegions: Obj[] = [];
  for (const rr of regionList) {
    const m = asObj(rr);
    if (m !== null && strOf(m["kind"]) === "stack") stackRegions.push(m);
  }
  const namedMain = stackRegions.some((m) => strOf(m["name"]) === "main");
  check(numGe1(counts["stack"]) && namedMain, "栈帧区域带函数名（C2）", tailMaps(stackRegions.slice(0, min(2, stackRegions.length))));

  let stackMetaOK = true;
  for (const m of stackRegions) {
    if (strOf(m["alloc_by"]) !== "call" || m["alloc_line"] === null || m["alloc_line"] === undefined) {
      stackMetaOK = false;
      break;
    }
  }
  check(stackMetaOK, "栈帧区域带 alloc_by=call / alloc_line（C2）", tailMaps(stackRegions.slice(0, min(2, stackRegions.length))));

  const r12 = res(12);
  check(numEq(r12["quarantine_budget"], 0), "config.set 生效（预算可调）", "");

  const diagBad = res(13);
  const diags = asArr(diagBad["diagnostics"]) ?? [];
  check(isBool(diagBad["ok"], false) && diags.length > 0, "非法程序编译失败并给诊断", "");

  const err14 = asObj(byID.get(14)?.["error"]) ?? {};
  check(strOf(err14["kind"]) === "protocol" && strOf(err14["message"]).includes("未知方法"), "未知方法 → protocol 错误帧", "");

  const r15 = res(15);
  check(isBool(r15["reset"], true), "session.reset 成功", "");
  const cfg15 = asObj(r15["config"]) ?? {};
  check(isBool(cfg15["compiled"], false), "reset 后 compiled=false", "");
  check(numEq(cfg15["quarantine_budget"], 0), "reset 保留会话级配置（隔离预算）", "");

  check(isBool(byID.get(16)?.["ok"], true), "capabilities 可用", "");
  const caps = res(16);
  const langs = asObj(caps["languages"]) ?? {};
  const langC = asObj(langs["c"]) ?? {};
  check(strOf(langC["stdc_version_macro_nominal"]) === "202311L", "capabilities 版本宏名义锚点", "");
  const memModel = asObj(caps["memory_model"]) ?? {};
  check(
    numEq(memModel["global_region_limit"], expectMemoryGlobalRegionLimit),
    "capabilities 内存模型常量（单源 vitro_runtime）",
    "",
  );

  // B2：schema 轨道与行为契约
  const schema = asObj(caps["schema"]) ?? {};
  const reserved = asArr(schema["reserved_fields_v0_2"]) ?? [];
  const reservedWant = ["handler_depth", "unwinding", "unwind_frames_left", "current_exception"];
  let reservedEq = strOf(schema["version"]) === "v0.2" && reserved.length === reservedWant.length;
  if (reservedEq) {
    for (let i = 0; i < reservedWant.length; i++) {
      if (strOf(reserved[i]) !== reservedWant[i]) {
        reservedEq = false;
        break;
      }
    }
  }
  check(reservedEq, "capabilities 携带 schema 轨道与预留位（B2）", tailMap(schema));

  const schemaLedger = asArr(schema["v0_2_field_ledger"]) ?? [];
  let codeFileActive = false;
  for (const e of schemaLedger) {
    const eo = asObj(e) ?? {};
    if (strOf(eo["field"]) === "code_file" && strOf(eo["status"]) === "active") codeFileActive = true;
  }
  check(codeFileActive, "v0.2 激活台账含 code_file(active)（#90）", JSON.stringify(schemaLedger));

  const contractsList = asArr(caps["behavior_contracts"]) ?? [];
  let hasUnwindContract = false;
  for (const c of contractsList) if (strOf((asObj(c) ?? {})["id"]) === "unwinding_step_granularity") hasUnwindContract = true;
  check(hasUnwindContract, "capabilities 携带行为契约（B2：UNWINDING 不合并单步）", "");

  const ev = strOf(caps["engine_version"]);
  check(ev !== "" && ev.split("(").length - 1 === 1, "capabilities 携带 engine_version（产物自检用）", ev);

  const labels = res(17);
  const labelList = asArr(labels["labels"]) ?? [];
  const labelIDs = labelList.map((l) => strOf((asObj(l) ?? {})["id"]));
  check(containsStr(labelIDs, "swap") && containsStr(labelIDs, "loop"), "semantic_labels 导出 C 域词汇（B2）", JSON.stringify(labelIDs));
  const reservedIDs = new Set<string>();
  for (const l of labelList) {
    const m = asObj(l) ?? {};
    if (strOf(m["status"]) === "reserved") reservedIDs.add(strOf(m["id"]));
  }
  let reservedAll = true;
  for (const id of ["throw", "unwind", "catch_enter", "finally"]) if (!reservedIDs.has(id)) reservedAll = false;
  check(reservedAll, "semantic_labels 预登记异常域词汇（reserved，B2）", "");

  const contracts = res(18);
  const actList = asArr(contracts["v0_2_activation_checklist"]) ?? [];
  const ledger = asArr(contracts["v0_2_field_ledger"]) ?? [];
  let hasCodeFile = false;
  for (const f of ledger) if (strOf((asObj(f) ?? {})["field"]) === "code_file") hasCodeFile = true;
  check(actList.length >= 4 && hasCodeFile, "contracts 导出激活清单与 v0.2 台账（B2）", "");

  const created = res(19);
  const sess = asObj(created["session"]) ?? {};
  check(
    isBool(created["created"], true) &&
      strOf(sess["model"]) === "single-active-session" &&
      numEq(sess["active_sessions"], 1) &&
      isBool(sess["concurrent_sessions"], false),
    "session.create 显式回带单会话语义（D2）",
    tailMap(sess),
  );

  // diagnostics_probe
  const r20 = res(20);
  check(isBool(byID.get(20)?.["ok"], true) && !isBool(r20["ok"], true), "probe: ok=false（error 级诊断在）", tailMap(byID.get(20) ?? null));
  const probeDiags = asArr(r20["diagnostics"]) ?? [];
  check(
    probeDiags.length === 1 &&
      strOf((asObj(probeDiags[0]) ?? {})["code"]) === "E2005" &&
      numEq((asObj(probeDiags[0]) ?? {})["fix_kind"], 2),
    "probe: E2005 诊断 + fix_kind=2（分叉②接线）",
    tailMap(r20),
  );
  const probeFixes = asArr(r20["auto_fixes"]) ?? [];
  check(
    probeFixes.length === 1 && strOf((asObj(probeFixes[0]) ?? {})["fixed_source"]) === "int x = 1;",
    "probe: auto_fixes 行末补分号（fixed_source 全文对拍）",
    tailMap(r20),
  );
  const r21 = res(21);
  check(isBool(byID.get(21)?.["ok"], true) && isBool(r21["ok"], true), "probe: 合法源 ok=true", tailMap(byID.get(21) ?? null));
  const probeMiscon = asArr(r21["misconceptions"]) ?? [];
  check(
    probeMiscon.length === 1 &&
      strOf((asObj(probeMiscon[0]) ?? {})["pattern_id"]) === "M01" &&
      numEq((asObj(probeMiscon[0]) ?? {})["confidence"], 0.75),
    "probe: misconceptions M01 检出（confidence 3/4）",
    tailMap(r21),
  );
  const probePaths = asArr(r21["learning_paths"]) ?? [];
  const probeSteps = asArr((asObj(probePaths[0]) ?? {})["steps"]) ?? [];
  check(probePaths.length === 1 && probeSteps.length === 3, "probe: learning_paths M01 三步", tailMap(r21));
  const probeKG = asObj(r21["knowledge_graph"]) ?? {};
  check(numEq(probeKG["concepts_total"], 25) && numEq(probeKG["edges_total"], 25), "probe: 概念图基线 25/25", tailMap(probeKG));
  const intentsOK = asArr(r21["intents"]) !== null;
  const completionArr = asArr(r21["completion"]);
  check(intentsOK && completionArr !== null && completionArr.length === 0, "probe: intents/completion 段数组形态（未传参 completion 空）", tailMap(r21));

  // time/clock 墙钟
  const d25 = res(25);
  const deltaTxt = strOf(d25["delta"]);
  check(
    deltaTxt.includes("t=1") && !deltaTxt.includes("t=0 "),
    "time 墙钟真值（非零——deterministic 销分叉；clock 同源不断言，差值 0 合法）",
    tailMap(d25),
  );

  const r22 = res(22);
  check(isBool(r22["shutdown"], true), "shutdown 回应", "");

  // ── 追加批（MB/wasm 臂按豁免表整批跳过）──
  const batches: Array<{ key: string; fn: (exe: string) => string[] | Promise<string[]> }> = [
    { key: "edge", fn: runEdgeBatch },
    { key: "pending_leak", fn: runPendingLeakBatch },
    { key: "rss_guard", fn: runRSSGuardBatch },
    { key: "long_line", fn: runLongLineBatch },
  ];
  for (const batch of batches) {
    if (mbMode || backendWasm) {
      const reason = mbBatches.get(batch.key);
      if (reason !== undefined) {
        process.stdout.write(`\n== ${batch.key} 批：SKIP（豁免：${reason}）==\n`);
        continue;
      }
    }
    failures = failures.concat(await batch.fn(exe));
  }

  process.stdout.write("\n");
  // 审计判定（D19）
  if (auditAll) {
    const zombies: string[] = [];
    process.stdout.write("── 豁免审计判定 ──\n");
    for (const name of auditNames) {
      const v = auditVerdict?.get(name);
      if (v === undefined) {
        zombies.push(name);
        process.stdout.write(`  ZOMBIE(未触达)  ${name}\n`);
      } else if (v === "PASS") {
        zombies.push(name);
        process.stdout.write(`  ZOMBIE(PASS)    ${name}\n`);
      } else {
        process.stdout.write(`  LEGIT(FAIL)     ${name}\n`);
      }
    }
    if (zombies.length > 0) {
      process.stdout.write(`豁免审计：发现 ${zombies.length} 条僵尸（断言真跑即绿/永不触达——请删除条目）\n`);
      return 1;
    }
    process.stdout.write("豁免审计：无僵尸（全部豁免经真跑证伪为合法）\n");
    return 0;
  }
  // 自报口径（facts 台账采集锚点，格式稳定）
  if (mbMode || backendWasm) {
    process.stdout.write(
      `MoonBit 臂断言数: ${assertions + exempted}  (PASS ${assertions - failures.length} / FAIL ${failures.length} / 豁免 ${exempted})\n`,
    );
  } else {
    process.stdout.write(`断言数: ${assertions}  (PASS ${assertions - failures.length} / FAIL ${failures.length})\n`);
  }
  if (failures.length > 0) {
    process.stdout.write(`FAILED: ${failures.length} 项 -> ${JSON.stringify(failures)}\n`);
    return 1;
  }
  process.stdout.write("serve 冒烟全部通过\n");
  return 0;
}

/** 请求对象按 Go struct 字段序序列化（id/method/params）。 */
function normalizeReq(r: Request): Obj {
  const o: Obj = { id: r.id, method: r.method };
  if (r.params !== undefined) o["params"] = r.params;
  return o;
}

// ── 边界/负值/极值批 ────────────────────────────────────────────

const EDGE_LINES = [
  '{"id": 101, "method": "compile", "params": {"source": "int main(){ int s=0; for(int i=0;i<3;i++) s+=i; return s; }"}}',
  '{"id": 102, "method": "step.begin"}',
  '{"id": 1021, "method": "step.next"}',
  '{"id": 1022, "method": "step.next"}',
  '{"id": 1023, "method": "step.next"}',
  '{"id": 1024, "method": "step.next"}',
  '{"id": 1025, "method": "step.next"}',
  '{"id": 103, "method": "seek", "params": {"step": 50000}}',
  '{"id": 104, "method": "seek", "params": {"step": -7}}',
  '{"id": 105, "method": "payload.get", "params": {"start": 0, "end": -1}}',
  '{"id": 106, "method": "payload.get", "params": {"start": -5, "end": 3}}',
  '{"id": 107, "method": "step.next"}',
  '{"id": 108, "method": "no.such.method"}',
  '{"id": 109, "method": "seek"}',
  '{"id": 110, "method": "ping"}',
  "{ this is not json",
  '{"id": 111, "method": "ping"}',
];

const EDGE_EXPECTED_IDS = [101, 102, 1021, 1022, 1023, 1024, 1025, 103, 104, 105, 106, 107, 108, 109, 110, 111];

export function runEdgeBatch(exe: string): string[] {
  process.stdout.write("\n== 边界/负值/极值批（panic 回归即红）==\n");
  const fails: string[] = [];
  const batch = runServeBatch(exe, EDGE_LINES.join("\n") + "\n", 120_000);
  if (batch.timedOut) {
    process.stdout.write("  FAIL  边界批超时（疑似挂起）\n");
    return ["edge-batch-timeout"];
  }
  const lines = nonEmptyLines(batch.stdout);
  check(batch.exitCode === 0, "边界批进程正常退出", `exit=${batch.exitCode} stderr=${tailRunes(batch.stderr, 300)}`);
  check(
    lines.length === EDGE_LINES.length,
    "边界批逐行响应（panic 死亡即缺行）",
    `responses=${lines.length} expected=${EDGE_LINES.length}`,
  );

  const parsed: Obj[] = [];
  for (let i = 0; i < lines.length; i++) {
    try {
      parsed.push(parseFrame(lines[i] as string));
    } catch (e) {
      check(false, `边界批响应 ${i} 是合法 JSON`, `${(e as Error).message}: ${truncateRunes(lines[i] as string, 120)}`);
      return fails;
    }
  }

  const { byID, nullID } = byIdMap(parsed);

  const missing = EDGE_EXPECTED_IDS.filter((id) => !byID.has(id));
  check(missing.length === 0, "合法边界请求 id 全部关联（进程存活）", JSON.stringify(missing));

  for (const rid of [103, 104]) {
    check(frameComplete(byID.get(rid)), `seek 边界(${rid}) 返回完整帧`, tailMap(byID.get(rid) ?? null));
  }
  for (const rid of [105, 106]) {
    check(frameComplete(byID.get(rid)), `payload.get 负参(${rid}) 返回完整帧`, tailMap(byID.get(rid) ?? null));
  }
  check(frameComplete(byID.get(107)), "越界 seek 后 step.next 仍可用", tailMap(byID.get(107) ?? null));

  let nullOK = nullID.length >= 1;
  for (const f of nullID) {
    if (strOf((asObj(f["error"]) ?? {})["kind"]) !== "protocol") {
      nullOK = false;
      break;
    }
  }
  check(nullOK, "非法 JSON 行 → protocol 错误帧", tailMap(nullID[0] ?? null));
  check(isBool((asObj(byID.get(111)?.["result"]) ?? {})["pong"], true), "畸形行之后 ping 仍 pong（进程存活）", "");
  return fails;
}

// ── 二次运行不串帧批（P0-A）─────────────────────────────────────

const P0A_A =
  "#include <stdio.h>\n" + "int f(int x){ return x * 2; }\n" + "int main(){ int a = 3; printf(\"%d\", f(a)); return 0; }\n";
const P0A_B = "#include <stdio.h>\n" + "int main(){ int b = 7; printf(\"%d\", b); return 0; }\n";

export function runPendingLeakBatch(exe: string): string[] {
  process.stdout.write("\n== 二次运行不串帧批（P0-A：pending 泄漏即红）==\n");
  const fails: string[] = [];
  const reqs: Request[] = [
    { id: 1, method: "compile", params: { source: P0A_A } },
    { id: 2, method: "step.begin" },
    { id: 3, method: "step.next" },
    { id: 3, method: "step.next" },
    { id: 3, method: "step.next" },
    { id: 3, method: "step.next" },
    { id: 3, method: "step.next" },
    { id: 4, method: "compile", params: { source: P0A_B } },
    { id: 5, method: "step.begin" },
    { id: 6, method: "step.next" },
    { id: 7, method: "step.next" },
  ];
  const payload = reqs.map((r) => JSON.stringify(normalizeReq(r))).join("\n") + "\n";
  const batch = runServeBatch(exe, payload, 60_000);
  if (batch.timedOut) {
    process.stdout.write("  FAIL  二次运行批超时\n");
    return ["pending-batch-timeout"];
  }

  const bFrames: Obj[] = [];
  for (const line of nonEmptyLines(batch.stdout)) {
    let d: Obj;
    try {
      d = parseFrame(line);
    } catch {
      continue;
    }
    const id = d["id"];
    if (typeof id !== "number" || !Number.isInteger(id)) continue;
    if ((id === 6 || id === 7) && isBool(d["ok"], true)) {
      for (const p of asArr((asObj(d["result"]) ?? {})["payloads"]) ?? []) {
        const m = asObj(p);
        if (m !== null) bFrames.push(m);
      }
    }
  }

  check(bFrames.length > 0, "二次运行有帧返回", `responses=${bFrames.length}`);
  if (bFrames.length > 0) {
    const first = bFrames[0] as Obj;
    check(numEq(first["step_index"], 0), "B 程序首帧 step_index=0（无 A 程序滞留帧）", `step_index=${String(first["step_index"])}（串帧时为 A 的递增步号）`);
    let noALeak = true;
    const nameList: string[] = [];
    for (const v of asArr(first["local_vars"]) ?? []) {
      const name = strOf((asObj(v) ?? {})["name"]);
      nameList.push(name);
      if (name === "a") noALeak = false;
    }
    check(noALeak, "B 程序首帧不携带 A 的局部变量", JSON.stringify(nameList));
  }
  return fails;
}

// ── RSS 护栏批（远距 seek 压力形状，超预算即红）──────────────────

const RSS_PROGRAM =
  "int main(){ int s=0; for(int i=0;i<60;i++) for(int j=0;j<60;j++) " + "for(int k=0;k<60;k++) s+=1; return s; }";

/**
 * 子进程**峰值提交**（MB）——Go 侧走 psapi `GetProcessMemoryInfo.PeakPagefileUsage`
 * （字节）；Node 无该 API，改读同一计数器的 CIM 面 `Win32_Process.PeakPageFileUsage`。
 * **量纲实测**：CIM 该字段是 **KB**（同进程 WorkingSetSize 是字节，二者差约 2048×；
 * 本机实测 PeakPageFileUsage=29656 / WorkingSetSize=62152704）——故此处 /1024。
 * 失败返回 -1（与 Go 版 psapi 失败同口径 → 「采样可用」断言红）。
 */
export function peakCommitMB(pid: number): number {
  const r = spawnSync(
    "powershell",
    [
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      `$p = Get-CimInstance Win32_Process -Filter "ProcessId=${pid}"; if ($p) { $p.PeakPageFileUsage }`,
    ],
    { encoding: "utf8", timeout: 20_000 },
  );
  if (r.error !== undefined || (r.status ?? -1) !== 0) return -1;
  const txt = (r.stdout ?? "").trim();
  if (txt === "") return -1;
  const kb = Number.parseInt(txt, 10);
  if (!Number.isFinite(kb) || kb < 0) return -1;
  return Math.floor(kb / 1024);
}

export async function runRSSGuardBatch(exe: string): Promise<string[]> {
  process.stdout.write("\n== RSS 护栏批（远距 seek 压力形状，超预算即红）==\n");
  let budgetMB = 64;
  const envBudget = process.env["VITRO_RSS_BUDGET_MB"];
  if (envBudget !== undefined && envBudget !== "") {
    const n = Number.parseInt(envBudget, 10);
    if (Number.isFinite(n)) budgetMB = n;
  }
  if (process.platform !== "win32") {
    process.stdout.write("  SKIP  非 Windows 平台（CI runner 为 windows-latest；采样走 psapi）\n");
    return [];
  }

  const [cmd, argv] = backendWasm
    ? [process.execPath, [exe, "serve"]]
    : mbMode
      ? [exe, []]
      : [exe, ["serve"]];
  const proc = spawn(cmd as string, argv as string[], { stdio: ["pipe", "pipe", "ignore"] });
  const lines = new AsyncLineReader(proc.stdout as NodeJS.ReadableStream, 30_000);
  const sendAndRead = async (obj: Obj): Promise<Obj | null> => {
    proc.stdin?.write(JSON.stringify(obj) + "\n");
    const line = await lines.readLine();
    if (line === null || line.trim() === "") return null;
    try {
      return parseFrame(line);
    } catch {
      return null;
    }
  };

  const pid = proc.pid as number;
  let peakMB = -1;
  let compileFailed = false;
  try {
    const resp = await sendAndRead({ id: 1, method: "compile", params: { source: RSS_PROGRAM } });
    if (!isBool(resp?.["ok"], true)) {
      compileFailed = true;
    } else {
      await sendAndRead({ id: 2, method: "step.begin" });
      // 前进到程序中段（产生跨检查点分布的帧），随后多轮远距 seek 制造重放尖峰
      for (let i = 0; i < 30; i++) await sendAndRead({ id: 10 + i, method: "step.next" });
      const targets = [8000, 20000, 5000, 20000];
      for (let roundNo = 0; roundNo < targets.length; roundNo++) {
        await sendAndRead({ id: 100 + roundNo, method: "seek", params: { step: targets[roundNo] } });
        const peak = peakCommitMB(pid);
        if (peak >= 0) {
          peakMB = peak;
          // 采样值属测得值：parity 用 maskLines 屏蔽本行，判定行（预算内/超）仍可比
          process.stdout.write(
            `  seek(${String(targets[roundNo]).padStart(5, " ")}) 后提交峰值 ≈ ${peak} MB（预算 ${budgetMB} MB）\n`,
          );
        }
      }
      await sendAndRead({ id: 999, method: "shutdown" });
    }
  } finally {
    try {
      proc.stdin?.end();
    } catch {
      // 已关闭
    }
  }

  await waitExit(proc, 30_000);

  if (compileFailed) return ["rss-batch-compile"];
  if (peakMB >= 0) {
    check(
      peakMB <= budgetMB,
      "RSS 护栏：提交峰值在预算内",
      `peak=${peakMB}MB budget=${budgetMB}MB（J5 已收紧至 64MB：U2#1 后实测 23MB；证红：VITRO_RSS_BUDGET_MB=5）`,
    );
  } else {
    check(false, "RSS 护栏：采样可用", "psapi 采样失败");
  }
  return [];
}

/** 等待子进程退出（Go `cmd.Wait()` 语义）；超时强杀。 */
function waitExit(proc: ReturnType<typeof spawn>, timeoutMs: number): Promise<void> {
  return new Promise((resolve) => {
    if (proc.exitCode !== null || proc.signalCode !== null) {
      resolve();
      return;
    }
    const timer = setTimeout(() => {
      proc.kill();
      resolve();
    }, timeoutMs);
    proc.on("close", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

/** 异步行读取器（NDJSON 管道；超时返 null）。 */
export class AsyncLineReader {
  private buf = "";
  private closed = false;
  private waiter: { resolve: (v: string | null) => void; timer: NodeJS.Timeout } | null = null;
  // 注意：node strip-only 不支持参数属性（constructor(private readonly x)）——显式字段
  private readonly timeoutMs: number;
  constructor(stream: NodeJS.ReadableStream, timeoutMs = 30_000) {
    this.timeoutMs = timeoutMs;
    stream.setEncoding("utf8");
    stream.on("data", (chunk: string) => {
      this.buf += chunk;
      this.pump();
    });
    stream.on("close", () => {
      this.closed = true;
      if (this.waiter !== null) {
        clearTimeout(this.waiter.timer);
        const w = this.waiter;
        this.waiter = null;
        w.resolve(this.buf === "" ? null : this.buf);
      }
    });
  }
  private pump(): void {
    if (this.waiter === null) return;
    const nl = this.buf.indexOf("\n");
    if (nl < 0) return;
    const line = this.buf.slice(0, nl + 1);
    this.buf = this.buf.slice(nl + 1);
    clearTimeout(this.waiter.timer);
    const w = this.waiter;
    this.waiter = null;
    w.resolve(line);
  }
  readLine(): Promise<string | null> {
    const nl = this.buf.indexOf("\n");
    if (nl >= 0) {
      const line = this.buf.slice(0, nl + 1);
      this.buf = this.buf.slice(nl + 1);
      return Promise.resolve(line);
    }
    if (this.closed) return Promise.resolve(this.buf === "" ? null : this.buf);
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.waiter = null;
        resolve(null);
      }, this.timeoutMs);
      this.waiter = { resolve, timer };
    });
  }
}

// ── 超长行批 ────────────────────────────────────────────────────

export function runLongLineBatch(exe: string): string[] {
  process.stdout.write("\n== 超长行批（静默丢弃回归即红）==\n");
  const fails: string[] = [];
  const pad = " ".repeat(70000 - 28);
  const line = '{"id": 1, "method": "ping"}' + pad + "\n";
  const batch = runServeBatch(exe, line, 60_000);
  if (batch.timedOut) {
    process.stdout.write("  FAIL  超长行批超时（疑似挂起）\n");
    return ["long-line-timeout"];
  }
  const lines = nonEmptyLines(batch.stdout);
  check(
    lines.length >= 1,
    "超长行非静默（≥1 响应行）",
    `responses=${lines.length} exit=${batch.exitCode} stderr=${truncateRunes(batch.stderr, 200)}`,
  );
  if (lines.length >= 1) {
    const first = lines[0] as string;
    let frame: Obj | null = null;
    try {
      frame = parseFrame(first);
    } catch {
      frame = null;
    }
    if (frame !== null) {
      check("ok" in frame, "超长行响应是帧（含 ok 字段）", truncateRunes(first, 120));
    } else {
      check(false, "超长行响应是合法 JSON", truncateRunes(first, 120));
    }
  }
  return fails;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  runMain(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e: unknown) => {
      process.stderr.write(`${e instanceof Error ? (e.stack ?? e.message) : String(e)}\n`);
      process.exit(2);
    },
  );
}

