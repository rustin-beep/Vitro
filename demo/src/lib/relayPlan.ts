// 回放排程内核（D3，refs #122）：帧事件 → 计划表（plan）与播放（play）分离。
//
// 两段式（archify planRelay 形态）：
//   1. plan（本文件，纯函数、零状态零 DOM）：给定帧数 / 事件 / fps / 上限，
//      算出每个 beat 的 { depart, travel }。指针轨道逐帧线性排程；事件轨道
//      以「指针到达该帧」为唯一前驱（最早到达松弛），同目标事件串行成链，
//      等待超过 chainBudgetMs 即种子兜底（放弃等待、接受重叠——WAAPI 单键控
//      已保证同名动画不叠播）；总长超 maxMs 时全表等比缩放。
//   2. play（playhead.svelte.ts）只按表执行；变速 = scalePlan 整表乘系数，
//      不重排。
//
// 边界：指针轨道**不受 maxMs 压缩**——fps 是用户显式语义（2 帧/秒就是
// 2 帧/秒），压缩只服务事件动效层（下一批接线）。本文件被 pure.test 单测锁死。
"use strict";

import { FALLBACK_MS } from "./motionTokens.ts";

export type RelayKind = "pointer" | "swap" | "vars" | "tree" | "scene";

export interface RelayEvent {
  /** 事件所在帧（viewFrames 下标）。 */
  frame: number;
  kind: Exclude<RelayKind, "pointer">;
  /** 动效目标键——同一目标的连续事件构成串行链（如某格连续两次交换）。 */
  key: string;
}

export interface RelayOptions {
  /** 帧数（viewFrames 长度）。 */
  frames: number;
  /** 播放帧率（帧/秒）。 */
  fps: number;
  /** 事件动效时长（ms，播放器传运行期 token）。 */
  eventMs?: number;
  /** 全片上限（ms）；<= 0 = 不压缩（默认，指针跟 fps 走）。 */
  maxMs?: number;
  /** 指针单帧移动占帧间隔的上限比例。 */
  travelRatio?: number;
  /** 指针单帧移动时长上限（ms）——低帧率下避免整段都在滑动。 */
  travelMaxMs?: number;
  /** 同目标事件等待链的最长延后（ms）；超出即种子兜底。默认一帧间隔。 */
  chainBudgetMs?: number;
  /** 同 kind 事件的最小拍间隔（ms）；密集事件按到达时刻抽稀，0 = 不抽稀。
   *  播放期脉冲节流用它——8fps 连续交换不抽稀会变成每秒 8 次满屏闪。 */
  minGapMs?: number;
  /** 事件列表（不要求按帧序，本函数自行排序）。 */
  events?: readonly RelayEvent[];
}

export interface RelayBeat {
  frame: number;
  kind: RelayKind;
  key: string;
  /** 出发时刻（ms，自回放起点）。 */
  depart: number;
  /** 行走时长（ms）；0 = 瞬时到位。 */
  travel: number;
}

export interface RelayPlan {
  totalMs: number;
  /** 是否被 maxMs 等比压缩过。 */
  scaled: boolean;
  intervalMs: number;
  beats: RelayBeat[];
}

function clamp(v: number, lo: number, hi: number): number {
  return Number.isFinite(v) ? Math.max(lo, Math.min(hi, v)) : lo;
}

export function planRelay(opts: RelayOptions): RelayPlan {
  const n = Math.max(0, Math.floor(opts.frames));
  const fps = Math.max(1, opts.fps);
  const interval = 1000 / fps;
  const ratio = clamp(opts.travelRatio ?? 0.85, 0, 1);
  const travelMax = Math.max(0, opts.travelMaxMs ?? FALLBACK_MS.slow);
  const eventMs = Math.max(0, opts.eventMs ?? FALLBACK_MS.slow);
  const chainBudget = Math.max(0, opts.chainBudgetMs ?? interval);
  const beats: RelayBeat[] = [];

  // 指针轨道：帧 i 的 beat = 从 i-1 走向 i 的移动（帧 0 无移动）。
  // travel 受比例、token 上限、帧间隔三重钳制——永远不越过下一帧。
  for (let i = 0; i < n; i += 1) {
    beats.push({
      frame: i,
      kind: "pointer",
      key: "pointer",
      depart: i === 0 ? 0 : (i - 1) * interval,
      travel: i === 0 ? 0 : Math.min(interval * ratio, travelMax, interval),
    });
  }

  // 事件轨道：到达帧 = 前驱（松弛一次即最早到达）；同 key 上一条完成
  // 是第二个前驱。等待把出发推离到达超过预算 → 种子兜底（自环截断）。
  // minGap：同 kind 相邻到达过密时丢弃后者（播放期脉冲节流的计划形态）。
  const events = [...(opts.events ?? [])].sort((a, b) => a.frame - b.frame);
  const lastEnd = new Map<string, number>();
  const lastAccepted = new Map<string, number>();
  const minGap = Math.max(0, opts.minGapMs ?? 0);
  for (const ev of events) {
    const frame = clamp(Math.floor(ev.frame), 0, Math.max(0, n - 1));
    const arrival = frame * interval;
    const prevArrival = lastAccepted.get(ev.kind);
    if (minGap > 0 && prevArrival !== undefined && arrival - prevArrival < minGap) continue;
    let depart = Math.max(arrival, lastEnd.get(ev.key) ?? 0);
    if (depart - arrival > chainBudget) depart = arrival;
    beats.push({ frame, kind: ev.kind, key: ev.key, depart, travel: eventMs });
    lastEnd.set(ev.key, depart + eventMs);
    lastAccepted.set(ev.kind, arrival);
  }

  let total = Math.max(0, (n - 1) * interval);
  for (const b of beats) total = Math.max(total, b.depart + b.travel);

  const limit = opts.maxMs ?? 0;
  if (limit > 0 && total > limit) {
    return { ...scalePlan({ totalMs: total, scaled: false, intervalMs: interval, beats }, limit / total), scaled: true };
  }
  return { totalMs: total, scaled: false, intervalMs: interval, beats };
}

/** 变速：整表乘系数（depart/travel/总长同乘），不重排。factor ≤ 0 或 1 原样返回。 */
export function scalePlan(plan: RelayPlan, factor: number): RelayPlan {
  if (!(factor > 0) || factor === 1) return plan;
  return {
    totalMs: plan.totalMs * factor,
    scaled: plan.scaled,
    intervalMs: plan.intervalMs * factor,
    beats: plan.beats.map((b) => ({ ...b, depart: b.depart * factor, travel: b.travel * factor })),
  };
}
