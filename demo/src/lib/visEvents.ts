// 帧事件的消费侧纯函数（D1，refs #122）：语句级组内聚合 + ty=2 交换对提取。
//
// 为什么需要组内聚合：vis 事件由 VM 的 StepEvent 在**命中的那一条指令**上
// 发出；语句级回放取的是组的**组尾帧**（局部变量/调用栈是句末快照）。组尾帧
// 自身通常没有 vis_events——bubble 课实测 7 个 ty=2 交换全部落在组内非尾帧，
// 若只读组尾，前端拿到的交换事件是 0（2026-10-29 实测 914 指令帧 → 65 语句帧，
// 组尾过滤后 ty=2 全丢）。本模块把组内事件并到组尾，与 viewFrames 逐位对齐。
"use strict";

import { annotateGroups } from "../../js/util.ts";
import type { VisEvent } from "../../js/types.ts";

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
      acc = [];
      seen = new Set<string>();
    }
  }
  return { frames: tails, events, rawIndex };
}

export interface SwapPair {
  a: number;
  b: number;
}

/** 事件 context 是否点名了该数组（`a[j]:a[j + 1]` 的左侧表达式）。
 *  extras 只有下标没有数组名——多数组课必须靠 context 归属，否则 A 数组的
 *  交换会同时点亮 B 数组的同号格（动效撒谎）。`obj.arr[` 不算 `arr[`
 *  （前面是非词字符 `.`：成员数组不是独立数组变量，快照名也不会是它）。 */
function contextMentionsArray(context: string, name: string): boolean {
  if (!name) return false;
  const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^\\w.])${esc}\\s*\\[`).test(context);
}

/** 从事件表提取可渲染的相邻交换对（ty=2）：extras 越界 / 相等 / -1 哨兵
 *  （运行期读不到局部 j 的诚实空态）一律丢弃；同帧重复对去重。
 *  arrayName 非空时只收 context 点名该数组的事件（多数组课归属过滤）。 */
export function swapPairs(
  events: readonly VisEvent[],
  arrayLength: number,
  arrayName = "",
): SwapPair[] {
  const out: SwapPair[] = [];
  const seen = new Set<string>();
  for (const e of events) {
    if (e.ty !== 2) continue;
    if (arrayName && !contextMentionsArray(e.context, arrayName)) continue;
    if (!Number.isInteger(e.extra0) || !Number.isInteger(e.extra1)) continue;
    const lo = Math.min(e.extra0, e.extra1);
    const hi = Math.max(e.extra0, e.extra1);
    if (lo < 0 || hi >= arrayLength || lo === hi) continue;
    const k = `${lo}:${hi}`;
    if (seen.has(k)) continue;
    seen.add(k);
    out.push({ a: lo, b: hi });
  }
  return out;
}
