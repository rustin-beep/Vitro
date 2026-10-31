// 回放排程内核（D3，refs #122）：帧事件 → 计划表（plan）与播放（play）分离。
//
// 两段式（archify planRelay 形态）：
//   1. plan（本文件，纯函数、零状态零 DOM）：给定帧数 / 事件 / fps，算出每个
//      beat 的 { depart, travel }。指针轨道逐帧线性排程；事件轨道以「指针到达
//      该帧」为唯一前驱（最早到达松弛），同目标事件串行成链，等待超过
//      chainBudgetMs 即种子兜底（放弃等待、接受重叠——WAAPI 单键控已保证同名
//      动画不叠播）；同目标（kind|key）的密集事件按 minGapMs 抽稀。
//   2. play（playhead.svelte.ts）只按表执行；变速 = scalePlan 整表乘系数
//      （以当前 fps 为基准等比缩放，不重排）。
//
// 本文件被 pure.test 单测锁死；不承载「全片硬上限」语义——把整段回放压进
// 固定秒数需要播放器的帧推进同样缩放，属另一个模式（本批未接）。
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
  /** 指针单帧移动占帧间隔的上限比例。 */
  travelRatio?: number;
  /** 指针单帧移动时长上限（ms）——低帧率下避免整段都在滑动。 */
  travelMaxMs?: number;
  /** 同目标事件等待链的最长延后（ms）；超出即种子兜底。默认一帧间隔。 */
  chainBudgetMs?: number;
  /** 同目标（kind|key）密集事件的最小拍间隔（ms）；0 = 不抽稀。
   *  播放期脉冲节流用它——8fps 连续交换不抽稀会变成每秒 8 次满屏闪。
   *  粒度必须与消费端匹配粒度一致（playhead 按 kind|key 查拍），否则第二个
   *  实体（如多数组课的 b 数组）的事件会被整类丢弃（PR #395 审阅 P2-1）。 */
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
  /** 最后一个 beat 的完成时刻与 (n-1)×interval 的较大者（观测/诊断用）。 */
  totalMs: number;
  intervalMs: number;
  beats: RelayBeat[];
}

/** 数值钳制：NaN 回 lo，±Infinity 按方向钳到 hi/lo（越界帧 → 末帧）。 */
function clamp(v: number, lo: number, hi: number): number {
  if (Number.isNaN(v)) return lo;
  return Math.max(lo, Math.min(hi, v));
}

/** 可选数值兜底：非有限值（NaN/±Infinity）一律回默认，不把 NaN 带进表。 */
function finiteOr(v: number | undefined, fallback: number): number {
  return v !== undefined && Number.isFinite(v) ? v : fallback;
}

export function planRelay(opts: RelayOptions): RelayPlan {
  const n = Number.isFinite(opts.frames) ? Math.max(0, Math.floor(opts.frames)) : 0;
  const fps = Number.isFinite(opts.fps) && opts.fps > 0 ? opts.fps : 1;
  const interval = 1000 / fps;
  const ratio = clamp(finiteOr(opts.travelRatio, 0.85), 0, 1);
  const travelMax = Math.max(0, finiteOr(opts.travelMaxMs, FALLBACK_MS.slow));
  const eventMs = Math.max(0, finiteOr(opts.eventMs, FALLBACK_MS.slow));
  const chainBudget = Math.max(0, finiteOr(opts.chainBudgetMs, interval));
  const minGap = Math.max(0, finiteOr(opts.minGapMs, 0));
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

  // 事件轨道：到达帧 = 前驱（松弛一次即最早到达）；同目标上一条完成是第二个
  // 前驱。等待把出发推离到达超过预算 → 种子兜底（自环截断）。
  // minGap：同目标（kind|key）相邻到达过密时丢弃后者——每个实体独立节流，
  // 多数组课 a/b 交替事件互不压制（P2-1）。
  const events = [...(opts.events ?? [])].sort((a, b) => a.frame - b.frame);
  const lastEnd = new Map<string, number>();
  const lastAccepted = new Map<string, number>();
  for (const ev of events) {
    const frame = clamp(Math.floor(ev.frame), 0, Math.max(0, n - 1));
    const arrival = frame * interval;
    const id = `${ev.kind}|${ev.key}`;
    const prevArrival = lastAccepted.get(id);
    if (minGap > 0 && prevArrival !== undefined && arrival - prevArrival < minGap) continue;
    let depart = Math.max(arrival, lastEnd.get(id) ?? 0);
    if (depart - arrival > chainBudget) depart = arrival;
    beats.push({ frame, kind: ev.kind, key: ev.key, depart, travel: eventMs });
    lastEnd.set(id, depart + eventMs);
    lastAccepted.set(id, arrival);
  }

  let total = Math.max(0, (n - 1) * interval);
  for (const b of beats) total = Math.max(total, b.depart + b.travel);
  return { totalMs: total, intervalMs: interval, beats };
}

/** 变速：整表乘系数（depart/travel/总长同乘），不重排。
 *  factor 非有限、≤0 或 1 时原样返回（Infinity 不得把 totalMs 乘成 Infinity）。 */
export function scalePlan(plan: RelayPlan, factor: number): RelayPlan {
  if (!Number.isFinite(factor) || factor <= 0 || factor === 1) return plan;
  return {
    totalMs: plan.totalMs * factor,
    intervalMs: plan.intervalMs * factor,
    beats: plan.beats.map((b) => ({ ...b, depart: b.depart * factor, travel: b.travel * factor })),
  };
}
