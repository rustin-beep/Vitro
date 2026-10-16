// Vitro 试点 · session 层雏形（F1，#119 迁移设计的 lib/session 落点）——
// gateway 调用 / 帧数组 / seek / 播放状态的单点。组件只读本层，不直接
// 摸 Worker 与 DOM。
//
// 响应式分界（best practices：$state 只给需要响应式的量；大数据走 raw）：
//   - session 标量/文案字段：UI 响应面——索引/播放态/状态文案/预算参数；
//   - session.frames（$state.raw）：帧大数据**引用替换响应、内容不代理**。
//     $derived 经 frameAt() 读它时依赖跟踪照常生效。
"use strict";

import type { StepPayload } from "../js/types.ts";
import { KEYS, storeGet, storeSet } from "./persisted.svelte.ts";
import { toast } from "./toasts.svelte.ts";
import { buildCallTree } from "../js/calltree.ts";
import { annotateGroups } from "../js/util.ts";

// 共享状态 = 官方推荐形态（best practices：classes with $state fields）——
// $state.raw 只能作声明初始化器/类字段，不可嵌在 $state({}) 字面量里
// （state_invalid_placement，2026-10-15 编译器实测）。
export interface CatalogCard {
  lang: string;
  category: string;
  code_str: string;
  title: string;
  explanation: string;
  icon: string;
  common_causes?: string[];
  [k: string]: unknown;
}

class SessionState {
  booted = $state(false);
  collecting = $state(false);
  epoch = $state(0); // 采集代号：切课/重置 = invalidate() 递增，在途采集回传即弃（防迟到覆写——旧栈 P0 竞态的 Worker 化放大形态，审阅 A-P0）
  playing = $state(false);
  batching = $state(false); // 批量推进中（bench/scrub）——FLIP 等交互动画此态关闭
  fps = $state(initFps()); // 播放帧率（档位见 ReplayBar；持久化=playback-fps 键）
  cap = $state(initCap()); // 采集帧预算（持久化=collect-cap 键；原 demo 硬上限 4000 → 可配）
  /** 帧大数据：引用替换响应、内容不深代理（采完只读）。⚠️ 帧源不可放
   * 模块级普通变量——非响应源不被 $derived 跟踪，首算后永不重算
   * （2026-10-15 浏览器实测踩坑：柱与变量表恒空即此因）。 */
  frames = $state.raw([] as StepPayload[]);
  idx = $state(0);
  status = $state("未采集——编辑源码后点「采集帧流」");
  stopped = $state("");
  versions = $state({ engine: "", protocol: "" });
  perf = $state({ collectMs: 0, replayPerFrameUs: 0 });
  outputs = $state({ stdout: "", stderr: "", note: "" }); // 四通道输出（采集时一次性拉齐）
  gran = $state<"stmt" | "insn">(initGran()); // 粒度：insn=指令级（帧全集）/ stmt=语句级（按行合并组尾帧）
  /** 播放帧序列（粒度派生——审阅 A-P2-12 处方：派生生成不 mutate 真源）。
   *  语句级 = 按行合并组尾帧（coalesceStmt 物理保留 util.ts，tests 锚零改动）。 */
  /** 当前帧的 vis_events 行集（编辑器左缘事件标记装饰消费）。 */
  visLines = $derived.by(() => {
    const s = new Set<number>();
    for (const ev of this.viewFrames[session.idx]?.vis_events ?? []) s.add(ev.line);
    return s;
  });
  viewFrames = $derived.by(() => {
    const raw = this.frames;
    if (this.gran === "stmt") return annotateGroups(raw).filter((g) => g.m === g.k).map((g) => g.f);
    return raw;
  });
  capabilities = $state.raw<Record<string, unknown> | null>(null);
  contracts = $state.raw<Record<string, unknown> | null>(null);
  labels = $state.raw<string[]>([]);
  /** 诊断目录（error_catalog 协议数据归 session 层；组件纯展示）。
   *  不代理——加载后只读。 */
  catalog = $state.raw([] as CatalogCard[]);
  /** 调用树（帧全集 buildCallTree 产物 + frameNode 帧→节点映射；采集完成时构建）。
   *  树模型含 parent 互相引用——raw 不代理防循环引用代理开销。 */
  tree = $state.raw<import("../js/calltree.ts").CallTree | null>(null);
  /** 内存地图（memory.regions = 会话当前态快照，非帧级——旧栈同语义；
   *  采集完成时拉取，UAF/泄漏教学看结束态 freed 块与隔离区）。 */
  memory = $state.raw<import("../js/types.ts").MemoryRegions | null>(null);
  /** 断点行集合（SvelteSet 响应式；编辑器行号点击 toggle、采集时下发给
   *  breakpoints.set——旧栈模块级单例跨用例渗入的病在会话单点关死）。 */
  breakpoints = $state<number[]>([]); // 断点行数组（普通 $state 深响应——SvelteSet 在此链三轮异常后弃用）
}

// ── 持久化初值（读有兜底，写有兜底——persisted 层统一）────────────────
// ⚠️ 必须先于 new SessionState()：类字段初始化器立即调用 initFps/initCap，
// const 声明不提升（TDZ，2026-10-15 浏览器实测抓过 TypeError）。
const FPS_STEPS = [8, 30, 60, 240];
function initFps(): number {
  const v = Number(storeGet(KEYS.playbackFps));
  return FPS_STEPS.includes(v) ? v : 30;
}
function initGran(): "stmt" | "insn" {
  const v = storeGet(KEYS.stepGran);
  return v === "stmt" ? "stmt" : "insn";
}
function initCap(): number {
  const v = Number(storeGet(KEYS.cap));
  return v >= 100 && v <= 200000 ? Math.round(v) : 20000;
}

export const session = new SessionState();

export function frameAt(i: number): StepPayload | undefined {
  return session.frames[i];
}

/** 作废在途采集（切用例/切课时调用）：epoch 递增，迟到的采集回传整体丢弃。 */
export function toggleBreakpoint(line: number): void {
  const i = session.breakpoints.indexOf(line);
  if (i >= 0) session.breakpoints.splice(i, 1);
  else session.breakpoints.push(line);
}

export function invalidate(): void {
  session.epoch += 1;
}

// ── Worker RPC ───────────────────────────────────────────────
let worker: Worker | null = null;
let rpcId = 0;
const pending = new Map<number, { resolve: (v: never) => void; reject: (e: Error) => void }>();

function getWorker(): Worker {
  if (!worker) {
    worker = new Worker(new URL("./protocol/engine.worker.ts", import.meta.url), { type: "module" });
    worker.onmessage = (e: MessageEvent) => {
      const { id, ok, data, error } = e.data as { id: number; ok: boolean; data?: never; error?: string };
      const p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      if (ok) p.resolve(data as never);
      else p.reject(new Error(error ?? "worker 无错误信息"));
    };
  }
  return worker;
}

function rpc<T>(msg: Record<string, unknown>): Promise<T> {
  const id = ++rpcId;
  return new Promise<T>((resolve, reject) => {
    pending.set(id, { resolve: resolve as never, reject });
    getWorker().postMessage({ id, ...msg });
  });
}

export class RpcError extends Error {
  readonly frame: Record<string, unknown>;
  constructor(frame: Record<string, unknown>) {
    super(String(frame.error ?? "协议错误帧（无错误文本）"));
    this.frame = frame;
  }
}

/** 通用方法调用（catalog/协议面等模块数据通道）：错误帧不折叠——顶层
 *  ok:false 抛 RpcError（帧原样挂 frame 供细读），成功回 result。 */
export async function call<T>(method: string, params: Record<string, unknown> = {}): Promise<T> {
  const resp = await rpc<Record<string, unknown>>({ op: "invoke", method, params });
  if (resp.ok === false) throw new RpcError(resp);
  return (resp.result ?? resp) as T;
}

// ── 对外动作 ────────────────────────────────────────────────
export async function boot(): Promise<void> {
  session.versions = await rpc<{ engine: string; protocol: string }>({ op: "boot" });
  session.booted = true;
}

/** 诊断目录拉取（引擎就绪后调一次；失败留空不阻塞页面，错误走 toast）。 */
export async function loadProto(): Promise<void> {
  try {
    const [cap, contracts, labels] = await Promise.all([
      call<Record<string, unknown>>("capabilities"),
      call<Record<string, unknown>>("contracts"),
      call<{ labels?: string[] }>("semantic_labels"),
    ]);
    session.capabilities = cap;
    session.contracts = contracts;
    session.labels = labels.labels ?? [];
  } catch (err) {
    toast("err", "协议面加载失败：" + String((err as Error).message).slice(0, 60));
  }
}

export async function loadCatalog(): Promise<void> {
  try {
    const r = await call<{ catalog?: CatalogCard[] }>("error_catalog");
    session.catalog = (r.catalog ?? []).slice().sort((a, b) => a.code_str.localeCompare(b.code_str));
  } catch (err) {
    toast("err", "诊断目录加载失败：" + String((err as Error).message).slice(0, 60));
  }
}

export async function collect(source: string, bpLines: number[] = []): Promise<void> {
  if (session.collecting) return;
  const my = ++session.epoch;
  session.collecting = true;
  session.playing = false;
  stopTimer();
  session.status = "Worker 采集中（编译 + run + step 闭环）…";
  try {
    const r = await rpc<{ frames: StepPayload[]; stopped: string; outputs: { stdout: string; stderr: string; note: string }; ms: number; versions: { engine: string; protocol: string } }>({
      op: "collect",
      source,
      cap: session.cap,
      bpLines: [...session.breakpoints],
    });
    if (my !== session.epoch) return; // 迟到回传：期间有新采集/作废，整体丢弃不碰任何状态
    session.frames = r.frames;
    session.idx = 0;
    session.stopped = r.stopped;
    session.outputs = r.outputs;
    session.tree = buildCallTree(r.frames); // 调用树（帧全集 → trie；物理保留 js/calltree.ts 纯函数）
    try {
      const mem = await call<{ [k: string]: unknown }>("memory.regions");
      session.memory = mem as unknown as import("../js/types.ts").MemoryRegions;
    } catch { session.memory = null; } // memory.regions 失败不阻塞帧回放
    session.perf.collectMs = r.ms;
    session.versions = r.versions;
    session.status = r.frames.length
      ? `采集 ${r.frames.length} 帧 · 耗时 ${r.ms}ms`
      : "零帧——编译失败或程序无步进";
    // 反馈分域：会话态走 status 行；操作结果走 toast（失败/到顶才弹，成功不扰）
    if (r.stopped) toast("err", r.stopped);
  } catch (err) {
    if (my !== session.epoch) return;
    const msg = "采集失败：" + String((err as Error).message);
    session.status = msg;
    toast("err", msg); // 失败原因进 toast 队列（可驻留细读）——status 行保持会话态
  } finally {
    if (my === session.epoch) session.collecting = false; // 仅当仍为当前代号才清旗——迟到回传不得错清新采集的旗
  }
}

export function seek(i: number): void {
  session.idx = Math.max(0, Math.min(i, session.viewFrames.length - 1));
}

export function step(delta: number): void {
  seek(session.idx + delta);
}

let timer: ReturnType<typeof setInterval> | undefined;
function stopTimer(): void {
  if (timer !== undefined) {
    clearInterval(timer);
    timer = undefined;
  }
}

export function togglePlay(): void {
  if (session.playing) {
    session.playing = false;
    stopTimer();
    return;
  }
  if (!session.viewFrames.length) return;
  session.playing = true;
  timer = setInterval(() => {
    if (session.idx >= session.viewFrames.length - 1) {
      togglePlay(); // 播完即停
      return;
    }
    step(1);
  }, Math.round(1000 / session.fps));
}

export function setFps(f: number): void {
  const was = session.playing;
  if (was) togglePlay();
  session.fps = f;
  if (was) togglePlay();
  storeSet(KEYS.playbackFps, String(f));
}

export function setGran(g: "stmt" | "insn"): void {
  const was = session.playing;
  if (was) togglePlay();
  session.gran = g;
  session.idx = Math.min(session.idx, session.viewFrames.length - 1);
  if (was) togglePlay();
  storeSet(KEYS.stepGran, g);
}

export function setCap(v: number): void {
  session.cap = v >= 100 && v <= 200000 ? Math.round(v) : 20000;
  storeSet(KEYS.cap, String(session.cap));
}
