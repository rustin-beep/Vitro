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
//
// #238（2026-10-23）：v2 锚点分镜——lesson.md 写死帧下标结构性必错（帧数
// 随程序参数变化：课程带 __PARAM_n__ 位，n=5 实测 914 帧 vs 写死 0..41，
// 89.5% 帧落幕外）。v2 幕的 from/to 是锚点表达式，帧流就绪后经
// resolveScenes 动态求值；锚点未命中 fail loud（该幕 -1 不猜 + console）。
import type { Scene } from "./lessonMd.ts";
import { coalesceStmt } from "../../js/util.ts";

/** 当前帧所在幕的下标；无幕 / 落在幕外 → -1。 */
export function sceneIndexAt(scenes: Scene[], idx: number): number {
  for (let i = 0; i < scenes.length; i += 1) {
    const s = scenes[i];
    if (s !== undefined && idx >= s.from && idx <= s.to) return i;
  }
  return -1;
}

// ── #238 锚点解析（v2）──────────────────────────────────────────────

/** 锚点求值所需的最小帧形态（StepPayload 子集——避免整帧类型耦合）。
 *  array_snapshots 用于 @arr_change:N 差分（可选——无数组帧流上该词 -1）。 */
export interface AnchorFrame {
  code_line: number;
  func_name: string;
  semantic_label: string;
  algorithm_step?: { phase: string } | null;
  array_snapshots?: { name: string; elements: string[] }[];
}

const ANCHOR_RE = /^@([A-Za-z_]\w*)(?::([\w]+))?(?:([+-])(\d+))?$/;

/** 两帧的数组快照是否不同（任一数组名/元素差异即变化）。
 *  快照「有→无」（收尾帧局部表清空）不算变化——那是帧归属切换非数组
 *  内容变化；「无→有」（声明首现）算。 */
function arrayDiffers(a: AnchorFrame, b: AnchorFrame): boolean {
  const as_ = a.array_snapshots ?? [];
  const bs = b.array_snapshots ?? [];
  if (as_.length === 0 && bs.length === 0) return false;
  if (as_.length === 0) return true; // 无→有
  if (bs.length === 0) return false; // 有→无：不计
  if (as_.length !== bs.length) return true;
  for (let i = 0; i < as_.length; i += 1) {
    const a0 = as_[i];
    const b0 = bs[i];
    if (a0 === undefined || b0 === undefined || a0.name !== b0.name) return true;
    const x = a0.elements;
    const y = b0.elements;
    if (x.length !== y.length) return true;
    for (let k = 0; k < x.length; k += 1) if (x[k] !== y[k]) return true;
  }
  return false;
}

/** 求值单个锚点表达式 → 帧号；未命中返回 -1（fail loud 由调用方提示）。
 *  词汇表（受控最小集，帧流可观测事件）：
 *  - `@first_swap` / `@swap:N`：第 N 个交换帧（N 从 1 起；algorithm_step
 *    .phase=="swap" 优先，semantic_label「交换」前缀兜底——#325 起
 *    两判据同源结构判定（交换赋值主行/回写行，左侧下标写），与交换
 *    暂存变量命名无关（旧形态依赖 temp 命名）；无标注算法兜底
 *    @arr_change:N）
 *  - `@compare:N`：第 N 个比较帧（algorithm_step.phase=="compare"——仅
 *    行末标注帧携带，见行为契约 algorithm_step_line_end_sparsity）
 *  - `@arr_change:N`：第 N 次数组内容变化帧（相邻帧快照差分——不依赖
 *    标注/label 命名，任何含数组程序可用；语句级与指令级粒度各自成立）
 *  - `@func:name`：首个 func_name==name 帧（如 `@0..@func:bubbleSort-1`
 *    表达 main 内初始化段——比「数组非全零」类快照判定稳）
 *  - `@last`：末帧
 *  - `±K` 后缀：相对偏移（clamp 到 [0, last]） */
export function resolveAnchor(anchor: string, src: AnchorFrame[]): number {
  // 粒度归一（审阅 P1-2 定稿）：全部词汇在语句级域（同行组取组尾）求值
  //——@arr_change 的差分序数、±K 偏移（=语句组偏移）、@last 端点在
  // 指令级/语句级两粒度下语义一致；结果经对象同一性映射回原流帧号
  //（消费方 sceneIndexAt 在原流 idx 上工作）。语句级流传入时 coalesce
  // 幂等。
  const frames = coalesceStmt(src);
  // @N：数字直答锚（@0..@arr_change:2 的起点形态）——clamp 进帧域
  const pure = anchor.match(/^@(\d+)$/);
  if (pure) {
    const k = Math.min(Number.parseInt(pure[1] as string, 10), frames.length - 1);
    const target = frames[k];
    return target === undefined ? -1 : src.indexOf(target);
  }
  const m = anchor.match(ANCHOR_RE);
  if (!m) return -1;
  const [, word, arg, sign, off] = m;
  let base = -1;
  const last = frames.length - 1;
  if (word === "last") {
    base = last;
  } else if (word === "first_swap" || (word === "swap" && arg !== undefined)) {
    const want = word === "first_swap" ? 1 : Number.parseInt(arg as string, 10);
    let seen = 0;
    for (let i = 0; i < frames.length; i += 1) {
      const f = frames[i] as AnchorFrame;
      if (f.algorithm_step?.phase === "swap" || f.semantic_label.startsWith("交换")) {
        seen += 1;
        if (seen === want) {
          base = i;
          break;
        }
      }
    }
  } else if (word === "compare" && arg !== undefined) {
    const want = Number.parseInt(arg, 10);
    let seen = 0;
    for (let i = 0; i < frames.length; i += 1) {
      if ((frames[i] as AnchorFrame).algorithm_step?.phase === "compare") {
        seen += 1;
        if (seen === want) {
          base = i;
          break;
        }
      }
    }
  } else if (word === "arr_change" && arg !== undefined) {
    // 审阅 P1-2：差分前先语句级归一（同 code_line 组取组尾）——指令级
    // 流上数组初始化是逐元素多次写 + 归零，逐帧差分序数与语句级不同
    //（实测 29 vs 20），两粒度各自成立的前提是归一。语句级流传入时
    // coalesceStmt 幂等（每帧已独立成组）。
    const stmt = coalesceStmt(frames);
    const want = Number.parseInt(arg, 10);
    let seen = 0;
    for (let i = 1; i < stmt.length; i += 1) {
      const prev = stmt[i - 1];
      const cur = stmt[i];
      if (prev !== undefined && cur !== undefined && arrayDiffers(prev, cur)) {
        seen += 1;
        if (seen === want) {
          base = frames.indexOf(cur);
          break;
        }
      }
    }
  } else if (word === "func" && arg !== undefined) {
    for (let i = 0; i < frames.length; i += 1) {
      if ((frames[i] as AnchorFrame).func_name === arg) {
        base = i;
        break;
      }
    }
  }
  if (base < 0) return -1;
  if (sign && off) {
    const k = Number.parseInt(off, 10) * (sign === "-" ? -1 : 1);
    base = Math.max(0, Math.min(last, base + k));
  }
  const target = frames[base];
  return target === undefined ? -1 : src.indexOf(target);
}

/** 解析一课的分镜（v2 锚点 → 数字区间；v1 数字幂等直通）。
 *  锚点未命中的幕 from/to 置 -1（sceneIndexAt「不猜」语义天然接住——
 *  界面无当前幕）并 console.warn 明示——静默错位是 #238 的病根形态。 */
export function resolveScenes(scenes: Scene[], frames: AnchorFrame[]): Scene[] {
  if (frames.length === 0) return scenes;
  if (!scenes.some((s) => s.fromAnchor !== undefined || s.toAnchor !== undefined)) return scenes;
  return scenes.map((s) => {
    if (s.fromAnchor === undefined && s.toAnchor === undefined) return s;
    const from = resolveAnchor(s.fromAnchor ?? "@0", frames);
    const to = resolveAnchor(s.toAnchor ?? "@last", frames);
    if (from < 0 || to < 0 || from > to) {
      console.warn(`[scenes] 分镜锚点未命中（${s.id}）：${s.fromAnchor}..${s.toAnchor} —— 该幕不可定位，保持无幕态`);
      return { ...s, from: -1, to: -1 };
    }
    return { ...s, from, to };
  });
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
