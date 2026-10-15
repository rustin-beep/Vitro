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

// 共享状态 = 官方推荐形态（best practices：classes with $state fields）——
// $state.raw 只能作声明初始化器/类字段，不可嵌在 $state({}) 字面量里
// （state_invalid_placement，2026-10-15 编译器实测）。
class SessionState {
  booted = $state(false);
  collecting = $state(false);
  playing = $state(false);
  batching = $state(false); // 批量推进中（bench/scrub）——FLIP 等交互动画此态关闭
  fps = $state(30); // 播放帧率（档位见 ReplayBar；采集帧率与引擎吞吐见 #89）
  cap = $state(20000); // 采集帧预算（原 demo 硬上限 4000 → 可配，引擎侧无此上限）
  /** 帧大数据：引用替换响应、内容不深代理（采完只读）。⚠️ 帧源不可放
   * 模块级普通变量——非响应源不被 $derived 跟踪，首算后永不重算
   * （2026-10-15 浏览器实测踩坑：柱与变量表恒空即此因）。 */
  frames = $state.raw([] as StepPayload[]);
  idx = $state(0);
  status = $state("未采集——编辑源码后点「采集帧流」");
  stopped = $state("");
  versions = $state({ engine: "", protocol: "" });
  perf = $state({ collectMs: 0, replayPerFrameUs: 0 });
}

export const session = new SessionState();

export function frameAt(i: number): StepPayload | undefined {
  return session.frames[i];
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

// ── 对外动作 ────────────────────────────────────────────────
export async function boot(): Promise<void> {
  session.versions = await rpc<{ engine: string; protocol: string }>({ op: "boot" });
  session.booted = true;
}

export async function collect(source: string): Promise<void> {
  if (session.collecting) return;
  session.collecting = true;
  session.playing = false;
  stopTimer();
  session.status = "Worker 采集中（编译 + run + step 闭环）…";
  try {
    const r = await rpc<{ frames: StepPayload[]; stopped: string; ms: number; versions: { engine: string; protocol: string } }>({
      op: "collect",
      source,
      cap: session.cap,
    });
    session.frames = r.frames;
    
    session.idx = 0;
    session.stopped = r.stopped;
    session.perf.collectMs = r.ms;
    session.versions = r.versions;
    session.status = r.frames.length
      ? `采集 ${r.frames.length} 帧 · 耗时 ${r.ms}ms`
      : "零帧——编译失败或程序无步进";
  } catch (err) {
    session.status = "采集失败：" + String((err as Error).message);
  } finally {
    session.collecting = false;
  }
}

export function seek(i: number): void {
  session.idx = Math.max(0, Math.min(i, session.frames.length - 1));
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
  if (!session.frames.length) return;
  session.playing = true;
  timer = setInterval(() => {
    if (session.idx >= session.frames.length - 1) {
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
}
