// E-08 引擎实产拉取（#324 治本批，2026-10-31；审阅处置批 2026-10-31 二修
// 口径声称）——同形性闸（e08-shape.test.mts）与导出器（e08-export.mts）
// 的共用单源：经 `api --batch` 现场跑引擎，返回帧流与协议面真值。
//
// **口径声明（与前端 worker 的已知差异，2026-10-31 审阅 P2-1/P1 定谳）**：
// 本模块的 step 推进 = `step.next {frames:N}` 单批（CLI step 子命令同款），
// **不是** demo worker 的 `step.next {}` 逐帧循环。两口径在引擎缺陷
// 「algorithm_step 行末不变量在批=1 下崩塌」（独立立案，见 PR #396 审阅）
// 修复前**不同构**：单批 = 行末语义正确形态（1041 帧仅 36 标注帧、零行
// 中间帧）；逐帧 = 标注过密形态（832 标注帧、796 行中间帧带标注）。
// 夹具锚定**正确形态**（与协议契约「跨批拼接与单帧流同构」的承诺一致），
// 待该缺陷修复后两口径同构、本声明随之退役。其余差异已对齐或实测等价：
// config（deterministic true/false 帧流全等、max_steps 两值均远未触顶）；
// output.delta（serve 侧单次即全量 all[cursor:total]，worker 的循环拉与
// 本模块单次拉等价；stdout/stderr 的 Latin-1 折回还原同款复刻，note 直传）。
//
// 臂选择（AGENTS 三臂纪律的批内验证通道）：缺省 js 臂（node 直跑
// vitro_js.js——CI demo job 的 build-products artifact 与本地 worktree 同
// 形态，零 shell 依赖）；`VITRO_E08_BACKEND=native` 切 native exe（防线
// 基线臂，双臂形态对拍用；审阅补充实测 wasm 臂两口径亦逐字节一致——
// 批量形状分叉非臂分叉）。产物缺失 fail loud 并给重建指引。
//
// compile 走前端单文件通道口径 {source}（不带 filename——code_file 实产
// 值为 null）；run argv[0] 语义与 cmd/lib/cli/cli_step.mbt 同款。
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
  // delta 消费（worker 同款分域解码）：stdout/stderr = Latin-1 折回形态，
  // 逐码元 &0xff 还原字节再 UTF-8 解码（demo/js/util.ts latin1ToUtf8 同源
  // 复刻——putchar(200) 单字节保真口径）；note = 引擎文本域真 UTF-8 直传。
  // serve 侧单次 delta = all[cursor:total] 全量（无分页）——cursor!==total
  // 或环形丢弃计数非零即 fail loud（防未来分页/预算触顶静默截断）。
  const latin1ToUtf8 = (s: string): string => {
    const bytes = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) bytes[i] = s.charCodeAt(i) & 0xff;
    return new TextDecoder("utf-8").decode(bytes);
  };
  const delta = (stream: string): string => {
    const id = stream === "stdout" ? 7 : stream === "stderr" ? 8 : 9;
    const r = byId.get(id) as { delta?: unknown; cursor?: unknown; total?: unknown; truncated_bytes?: unknown } | undefined;
    if (r === undefined) return "";
    if (r.cursor !== r.total) {
      throw new Error(`[e08-live] output.delta ${stream} 单次未拉全（cursor=${String(r.cursor)} total=${String(r.total)}）——serve 分页语义变更，消费侧须改循环拉`);
    }
    if (r.truncated_bytes !== undefined && r.truncated_bytes !== 0) {
      throw new Error(`[e08-live] output.delta ${stream} truncated_bytes=${String(r.truncated_bytes)}——输出预算触顶环形丢弃，payload 不完整`);
    }
    const d = typeof r.delta === "string" ? r.delta : "";
    return stream === "note" ? d : latin1ToUtf8(d);
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
