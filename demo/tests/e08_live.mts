// E-08 引擎实产拉取（#324 治本批，2026-10-31）——同形性闸
// （e08-shape.test.mts）与导出器（e08-export.mts）的共用单源：以 demo
// 前端 worker 同款的方法序列（engine.worker.ts collect 通道口径）经
// `api --batch` 现场跑引擎，返回帧流与协议面真值。
//
// 臂选择（AGENTS 三臂纪律的批内验证通道）：缺省 js 臂（node 直跑
// vitro_js.js——CI demo job 的 build-products artifact 与本地 worktree 同
// 形态，零 shell 依赖）；`VITRO_E08_BACKEND=native` 切 native exe（防线
// 基线臂，双臂形态对拍用）。产物缺失 fail loud 并给重建指引。
//
// 方法序列与 cmd/lib/cli/cli_step.mbt 同口径（config deterministic /
// run argv[0] 语义 / step.next 批量 frames）；compile 走前端口径
// {source}（不带 filename——demo worker 单文件通道同形，code_file 实产
// 值为 null）。
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export interface LivePayload {
  /** step 流全量帧（StepPayload 形态，Record 视角做机判）。 */
  frames: Array<Record<string, unknown>>;
  /** stdout/stderr/note 三流聚合（output.delta cursor:0 全量拉取）。 */
  outputs: { stdout: string; stderr: string; note: string };
  /** memory.regions 会话末态（MemoryRegions 形态）。 */
  memory: Record<string, unknown>;
  /** capabilities 协议面对象（非数组——夹具旧形态是字符串数组，#324 断点）。 */
  capabilities: Record<string, unknown>;
  /** semantic_labels 词表（对象数组 {id,domain,status,template,...}）。 */
  semanticLabels: Array<Record<string, unknown>>;
  /** error_catalog 全量卡（115 条 {code,code_str,lang,category,...}）。 */
  catalog: Array<Record<string, unknown>>;
  /** run 终态（status/return_value/steps_executed/waiting_input）。 */
  run: { status: string; return_value: number; steps_executed: number; waiting_input: boolean };
  /** trap_message（无 trap 为 null）。 */
  trapMessage: string | null;
}

/** 采集选项：argv[0] 语义（code_file 实产值随它——前端口径见各真源注释）。 */
export interface LiveOptions {
  argv0: string;
}

export interface LiveShape extends LivePayload {
  /** 实产帧字段并集（字段集全等断言的右侧）。 */
  frameFields: string[];
  /** semantic_label 值域（中文渲染文本）。 */
  labelValues: string[];
  /** semantic_label_id 值域（受控词表 id）。 */
  labelIds: string[];
  /** algorithm_step.phase 值域（英文 id）。 */
  phases: string[];
}

const here = path.dirname(fileURLToPath(import.meta.url));
const demoRoot = path.resolve(here, "..");
const repoRoot = path.resolve(demoRoot, "..");

/** E-08 引擎输入真源（frames 唯一来源——改它须重导 core.json + 重冻 golden）。 */
export const BUBBLE_C: string = path.join(demoRoot, "e08", "bubble.c");
/** diagband-trap 用例输入真源（UAF 教学标准案）。 */
export const UAF_C: string = path.join(demoRoot, "e08", "uaf.c");

interface EngineTarget {
  cmd: string;
  baseArgs: string[];
}

function resolveEngine(): EngineTarget {
  const backend = process.env["VITRO_E08_BACKEND"] ?? "js";
  if (backend === "native") {
    const exe = path.join(
      repoRoot,
      "moonbit",
      "_build",
      "native",
      "release",
      "build",
      "cmd",
      "vitro",
      "vitro.exe",
    );
    if (!existsSync(exe)) {
      throw new Error(
        `[e08-live] native 臂产物缺失：${exe}\n重建（Windows 下 MOON_CC=clang 必需）：cd moonbit && MOON_CC=clang moon build --release --target native cmd/vitro`,
      );
    }
    return { cmd: exe, baseArgs: [] };
  }
  if (backend !== "js") {
    throw new Error(`[e08-live] VITRO_E08_BACKEND 未知值：${backend}（合法：js | native）`);
  }
  const js = path.join(
    repoRoot,
    "moonbit",
    "_build",
    "js",
    "release",
    "build",
    "cmd",
    "vitro_js",
    "vitro_js.js",
  );
  if (!existsSync(js)) {
    throw new Error(
      `[e08-live] js 臂产物缺失：${js}\n重建：cd moonbit && moon build --release --target js cmd/vitro_js`,
    );
  }
  return { cmd: process.execPath, baseArgs: [js] };
}

/** 响应信封帧（api --batch 出口形态——信封层 ok 才是协议成败位）。 */
interface Envelope {
  id: number;
  ok: boolean;
  result?: Record<string, unknown>;
}

function apiBatch(requests: Array<Record<string, unknown>>): Array<Envelope> {
  const engine = resolveEngine();
  const stdin = requests.map((r) => JSON.stringify(r)).join("\n") + "\n";
  const r = spawnSync(engine.cmd, [...engine.baseArgs, "api", "--batch"], {
    input: stdin,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  const backend = process.env["VITRO_E08_BACKEND"] ?? "js";
  if (r.error) throw new Error(`[e08-live] 引擎启动失败（backend=${backend}）：${r.error.message}`);
  // rc 判定注意：CLI 的 batch rc=1 是「响应文本含 "ok":false 子串」的宽判定
  // ——run 帧 trap 时 result 内嵌 ok:false（信封层 ok:true，协议帧本身成
  // 功）也会 rc=1。此处按**信封层** ok 判定（唯一权威），rc 只兜底用法错
  // （rc=4）与进程级失败（rc 非 0/1）。
  if (r.status !== null && r.status !== 0 && r.status !== 1) {
    throw new Error(`[e08-live] api --batch rc=${r.status}（backend=${backend}）\nstderr 尾部：${(r.stderr ?? "").slice(-400)}`);
  }
  const out: Array<Envelope> = [];
  for (const line of r.stdout.split("\n")) {
    if (line.trim() === "") continue;
    const j = JSON.parse(line) as Envelope;
    if (j.ok === false) {
      throw new Error(`[e08-live] api 帧 ok:false：${JSON.stringify(j).slice(0, 300)}`);
    }
    out.push(j);
  }
  if (out.length !== requests.length) {
    throw new Error(`[e08-live] 响应帧数不符：请求 ${requests.length} / 响应 ${out.length}`);
  }
  return out;
}

/** 拉引擎实产（帧流 + 三流输出 + 内存态 + 三协议面）。缺省输入 bubble.c。 */
export function engineLive(sourcePath: string = BUBBLE_C, opts: LiveOptions = { argv0: "bubble.c" }): LivePayload {
  const source = readFileSync(sourcePath, "utf8");
  const reqs: Array<Record<string, unknown>> = [
    { id: 1, method: "session.create", params: {} },
    {
      id: 2,
      method: "config.set",
      params: { max_steps: 100000, call_depth_limit: 10000, deterministic: true, quarantine_budget: 262144 },
    },
    { id: 3, method: "compile", params: { source } },
    { id: 4, method: "run", params: { argv: [opts.argv0] } },
    { id: 5, method: "step.begin", params: {} },
    { id: 6, method: "step.next", params: { frames: 100000 } },
    { id: 7, method: "output.delta", params: { cursor: 0, stream: "stdout" } },
    { id: 8, method: "output.delta", params: { cursor: 0, stream: "stderr" } },
    { id: 9, method: "output.delta", params: { cursor: 0, stream: "note" } },
    { id: 10, method: "memory.regions", params: {} },
    { id: 11, method: "capabilities", params: {} },
    { id: 12, method: "semantic_labels", params: {} },
    { id: 13, method: "error_catalog", params: {} },
  ];
  const res = apiBatch(reqs);
  const byId = new Map<number, Record<string, unknown>>();
  for (const frame of res) {
    if (byId.has(frame.id)) throw new Error(`[e08-live] 响应 id 重复：${frame.id}`);
    byId.set(frame.id, frame.result ?? {});
  }
  const step = byId.get(6);
  if (!step) throw new Error("[e08-live] step.next 响应缺失（id=6）");
  const finished = step["finished"] === true;
  const trapped = step["trapped"] === true;
  if (!finished && !trapped) {
    throw new Error(`[e08-live] step 流未到终态：finished=${String(step["finished"])} trapped=${String(step["trapped"])}`);
  }
  const frames = (step["payloads"] as Array<Record<string, unknown>>) ?? [];
  if (frames.length === 0) throw new Error("[e08-live] 实产帧流为空——闸失去对照基准");
  const delta = (stream: string): string => {
    const id = stream === "stdout" ? 7 : stream === "stderr" ? 8 : 9;
    const r = byId.get(id) as { delta?: unknown } | undefined;
    return typeof r?.delta === "string" ? r.delta : "";
  };
  const need = (id: number, what: string): Record<string, unknown> => {
    const r = byId.get(id);
    if (r === undefined) throw new Error(`[e08-live] ${what} 响应缺失（id=${id}）`);
    return r;
  };
  const run4 = byId.get(4);
  const run = {
    status: typeof run4?.["status"] === "string" ? (run4["status"] as string) : "unknown",
    return_value: typeof run4?.["return_value"] === "number" ? (run4["return_value"] as number) : 0,
    steps_executed: typeof run4?.["steps_executed"] === "number" ? (run4["steps_executed"] as number) : frames.length,
    waiting_input: run4?.["waiting_input"] === true,
  };
  return {
    frames,
    outputs: { stdout: delta("stdout"), stderr: delta("stderr"), note: delta("note") },
    memory: need(10, "memory.regions"),
    capabilities: need(11, "capabilities"),
    semanticLabels: (need(12, "semantic_labels")["labels"] as Array<Record<string, unknown>>) ?? [],
    catalog: (need(13, "error_catalog")["catalog"] as Array<Record<string, unknown>>) ?? [],
    run,
    trapMessage: typeof step["trap_message"] === "string" ? (step["trap_message"] as string) : null,
  };
}

/** 形态摘要（值域/字段并集——同形性断言的右侧与导出器报告共用）。 */
export function liveShape(live: LivePayload): LiveShape {
  const fieldSet = new Set<string>();
  for (const f of live.frames) for (const k of Object.keys(f)) fieldSet.add(k);
  const labels = new Set<string>();
  const labelIds = new Set<string>();
  const phases = new Set<string>();
  for (const f of live.frames) {
    const label = f["semantic_label"];
    if (typeof label === "string") labels.add(label);
    const labelId = f["semantic_label_id"];
    if (typeof labelId === "string") labelIds.add(labelId);
    const as = f["algorithm_step"] as { phase?: unknown } | null | undefined;
    if (as && typeof as.phase === "string") phases.add(as.phase);
  }
  return { ...live, frameFields: [...fieldSet].sort(), labelValues: [...labels], labelIds: [...labelIds], phases: [...phases] };
}
