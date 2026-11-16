// 帧事件的消费侧纯函数（D1，refs #122）：语句级组内聚合 + plan 组聚合。
//
// 为什么需要组内聚合：vis 事件由 VM 的 StepEvent 在**命中的那一条指令**上
// 发出；语句级回放取的是组的**组尾帧**（局部变量/调用栈是句末快照）。组尾帧
// 自身通常没有 vis_events——bubble 课实测 7 个 ty=2 交换全部落在组内非尾帧，
// 若只读组尾，前端拿到的交换事件是 0（2026-10-29 实测 914 指令帧 → 65 语句帧，
// 组尾过滤后 ty=2 全丢）。本模块把组内事件并到组尾，与 viewFrames 逐位对齐。
//
// #470 批三：交换归属判据已下沉引擎（doc.timeline / timeline.plan）——本模块
// 不再自带 context 归属规则，只做「指令帧 plan → 语句组 plan」的时间聚合：
// 归属（哪个数组/哪对下标）由引擎给，聚合（组内多帧并到组尾）是回放粒度的事。
"use strict";

import { annotateGroups } from "../../js/util.ts";
import type { TimelineCam, TimelineStep, TimelineSwap, VisEvent } from "../../js/types.ts";

export interface EventFrame {
  code_line: number;
  vis_events?: readonly VisEvent[];
}

export interface StatementView<F> {
  /** 语句级回放帧（每组组尾——与 coalesceStmt 同源同序）。 */
  frames: F[];
  /** 与 frames 逐位对齐的事件表（组内事件去重后并入组尾）。 */
  events: VisEvent[][];
  /** 与 frames 逐位对齐的**原流帧下标**（组尾在 frames 原数组里的位置）。
   *  调用树 frameNode 等按指令帧下标建的表必须经此映射，不能拿 view 下标直查。 */
  rawIndex: number[];
  /** 与 frames 逐位对齐的原流组区间（闭区间）——plan 组聚合用。 */
  ranges: Array<{ from: number; to: number }>;
}

function eventKey(e: VisEvent): string {
  return `${e.ty}:${e.line}:${e.extra0}:${e.extra1}:${e.extra2}:${e.context}`;
}

/** 指令帧流 → 语句级帧 + 逐帧事件。分组口径复用 annotateGroups（与
 *  coalesceStmt 完全同源），只额外把组内事件聚到组尾。 */
export function statementEvents<F extends EventFrame>(frames: F[]): StatementView<F> {
  const tails: F[] = [];
  const events: VisEvent[][] = [];
  const rawIndex: number[] = [];
  const ranges: Array<{ from: number; to: number }> = [];
  let acc: VisEvent[] = [];
  let seen = new Set<string>();
  const groups = annotateGroups(frames);
  for (let i = 0; i < groups.length; i += 1) {
    const g = groups[i];
    if (g === undefined) continue;
    for (const e of g.f.vis_events ?? []) {
      const k = eventKey(e);
      if (seen.has(k)) continue;
      seen.add(k);
      acc.push(e);
    }
    if (g.m === g.k) {
      tails.push(g.f);
      events.push(acc);
      rawIndex.push(i); // annotateGroups 每帧一项，i 即原流帧下标
      ranges.push({ from: i - g.k + 1, to: i });
      acc = [];
      seen = new Set<string>();
    }
  }
  return { frames: tails, events, rawIndex, ranges };
}

/** 宿主绘制面的交换对（升序下标；由 plan.sw 投影，来源单指 TimelineSwap）。 */
export interface SwapPair {
  a: number;
  b: number;
}

/** 语句组（或单帧）的 plan 视图：sws = 组内各帧 sw 按帧序去重（归属判据
 *  已在引擎）；cap/bar = 组尾帧字幕段与量感条（组尾快照的视图）；cam/enter =
 *  组内最后一个相机/进场意图（变化帧语义）。ch 不在此聚合——demo 的
 *  「值变化」基准是相邻**可视帧**（语句组选择层），与 plan 的「帧集内前帧」
 *  基准不同语义，由 ArrayCells 的宿主差分承担（边界登记见 spec §3）。 */
export interface ViewPlanStep {
  sws: TimelineSwap[];
  cap?: { t: string; w: number; dur: number };
  bar?: Record<string, number[]>;
  cam?: TimelineCam;
  enter?: string;
}

/** 指令级 plan steps → 单组 plan 视图（insn 粒度传单元素）。 */
export function aggregatePlanStep(steps: readonly TimelineStep[]): ViewPlanStep {
  const sws: TimelineSwap[] = [];
  const seen = new Set<string>();
  for (const st of steps) {
    const sw = st.sw;
    if (sw === undefined) continue;
    const k = `${sw.name}:${sw.i}:${sw.j}`;
    if (seen.has(k)) continue;
    seen.add(k);
    sws.push(sw);
  }
  const tail = steps[steps.length - 1];
  const out: ViewPlanStep = { sws };
  if (tail?.cap !== undefined) out.cap = tail.cap;
  if (tail?.bar !== undefined) out.bar = tail.bar;
  for (let i = steps.length - 1; i >= 0; i -= 1) {
    const st = steps[i];
    if (st?.cam !== undefined) {
      out.cam = st.cam;
      break;
    }
  }
  for (let i = steps.length - 1; i >= 0; i -= 1) {
    const st = steps[i];
    if (st?.enter !== undefined) {
      out.enter = st.enter;
      break;
    }
  }
  return out;
}

/** 语句级 plan（与 viewFrames 逐位对齐）：ranges = statementEvents 的组区间，
 *  steps = 指令级 plan（长度必须等于原流帧数，否则不猜 → null）。 */
export function viewPlanOf(
  steps: readonly TimelineStep[] | undefined,
  ranges: readonly { from: number; to: number }[] | undefined,
): ViewPlanStep[] | null {
  if (steps === undefined || ranges === undefined) return null;
  const out: ViewPlanStep[] = [];
  for (const r of ranges) {
    if (r.from < 0 || r.to < r.from || r.to >= steps.length) return null;
    out.push(aggregatePlanStep(steps.slice(r.from, r.to + 1)));
  }
  return out;
}
