// 帧 → 幕定位（分镜条 / 时间轴分幕共用单点，2026-10-21 P1 第二片）。
//
// scene 真源 = `course/**/lesson.md` 的 vitri-scenes 块（lessonMd.parseLessonMd
// 解析、blocks 剥离）；`from/to` 是 viewFrames 下标**闭区间**。本模块只做纯
// 函数定位，不 import Svelte 状态——时间轴与分镜条各自 $derived 调这里，
// 保证「当前在第几幕」只有一个判据。
//
// 边界语义：
//   - 空幕表（未迁移的老课）→ -1，调用方回退现有长文；
//   - 幕缝（上一幕 to + 1 = 下一幕 from）落在下一幕——闭区间不重叠；
//   - idx 落在所有幕之外（负数未采集 / 帧数变化后的旧存档）→ -1，不猜。
import type { Scene } from "./lessonMd.ts";

/** 当前帧所在幕的下标；无幕 / 落在幕外 → -1。 */
export function sceneIndexAt(scenes: Scene[], idx: number): number {
  for (let i = 0; i < scenes.length; i += 1) {
    if (idx >= scenes[i].from && idx <= scenes[i].to) return i;
  }
  return -1;
}

/** 幕内进度 0..1（进度条用）。单帧幕到即满，避免 0/0 = NaN 污染 style。 */
export function sceneProgress(s: Scene, idx: number): number {
  if (s.to <= s.from) return idx >= s.from ? 1 : 0;
  const p = (idx - s.from) / (s.to - s.from);
  return Math.max(0, Math.min(1, p));
}

/** 帧范围文案：多帧 "帧 0–4"、单帧 "帧 7"（时间轴分幕条与分镜条同形）。 */
export function sceneRangeLabel(s: Scene): string {
  return s.from === s.to ? `帧 ${s.from}` : `帧 ${s.from}–${s.to}`;
}

/** 幕头文案："第 2 幕 / 共 4 幕 · 帧 5–20"（幕号从 1 起，与分镜条 id 视觉一致）。 */
export function sceneKicker(s: Scene, i: number, total: number): string {
  return `第 ${i + 1} 幕 / 共 ${total} 幕 · ${sceneRangeLabel(s)}`;
}

/** 分幕条几何：按**帧格**（frameCount 等分轴宽）给 left/width 百分比。
 *  未采集（frameCount ≤ 0）→ 零宽而不是 NaN——`NaN%` 会让整条轴静默消失；
 *  `to` 越过现存帧（旧存档 / 帧数变化）→ 钳到末帧，条不出轴。 */
export function sceneBand(s: Scene, frameCount: number): { left: number; width: number } {
  if (frameCount <= 0) return { left: 0, width: 0 };
  const from = Math.max(0, Math.min(s.from, frameCount - 1));
  const to = Math.max(from, Math.min(s.to, frameCount - 1));
  return { left: (from / frameCount) * 100, width: ((to - from + 1) / frameCount) * 100 };
}
