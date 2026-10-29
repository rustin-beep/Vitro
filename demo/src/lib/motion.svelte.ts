// 动效治理层（D0，refs #122）：开关 / 系统偏好 / 预算裁决 / WAAPI 脉冲单点。
//
// 三条职责（与呈现层分工，见 demo/DESIGN.md 动效章）：
//   1. 开关：用户偏好（localStorage vitro-motion）+ 系统 prefers-reduced-motion
//      双层禁用；html data-motion="off" 仍是 CSS 一刀切的唯一写口（本层写）。
//   2. 预算：状态类高亮（class/attr）恒亮；脉冲类动效在播放 / 批量推进 /
//      拖拽 scrub 时让位——满屏闪会盖掉正在读的语义。
//   3. 呈现原语：pulse() 给单元素单动画键控（重复触发先取消上一次），
//      时长/缓动从 tokens.css 运行期读取（单源 demo/tokens.json，不在 JS 抄数）。
//
// 为什么 spring 参数不放 tokens.json：Svelte spring 要的是 JS 数值，CSS 变量
// 无法回读成数值参数；硬塞进 token 只会制造第二真相源。回调参数单源在本文件。
"use strict";

import { KEYS, storeGet, storeSet } from "../persisted.svelte.ts";
import { session } from "../session.svelte.ts";
import { cubicOut } from "svelte/easing";

export type MotionTier = "fast" | "base" | "slow";
export type MotionEasing = "standard" | "emphasis" | "enter";

/** Svelte spring 参数（数值面单源；D3 时间轴指针消费）。
 *  相机用 Tween 而非 spring：Svelte Spring 的 damping 被钳在 0..1，可用
 *  stiffness 下必然欠阻尼（快速档过冲），做不出「过阻尼仪器感」；Tween +
 *  cubicOut 无过冲且时长可 token 化（见 CallTree 相机段）。 */
export const SPRING = {
  /** 时间轴指针 / 分镜进度：轻一点，跟手但不跳 */
  pointer: { stiffness: 0.28, damping: 0.86 },
} as const;

const FALLBACK_MS: Record<MotionTier, number> = { fast: 90, base: 160, slow: 280 };
const FALLBACK_EASE: Record<MotionEasing, string> = {
  standard: "cubic-bezier(.2, .7, .3, 1)",
  emphasis: "cubic-bezier(.2, .9, .25, 1)",
  enter: "cubic-bezier(.22, 1, .36, 1)",
};
const EASE_VAR: Record<MotionEasing, string> = {
  standard: "--vr-ease",
  emphasis: "--vr-ease-emphasis",
  enter: "--vr-ease-enter",
};

function cssVar(name: string): string {
  if (typeof getComputedStyle !== "function" || typeof document === "undefined") return "";
  const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return v || "";
}

function prefersReduced(): boolean {
  return typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** token 时长（ms）：CSS 变量单源，读不到才用兜底值。 */
export function motionMs(tier: MotionTier = "base"): number {
  const raw = cssVar(tier === "base" ? "--vr-t" : `--vr-t-${tier}`);
  const n = Number.parseFloat(raw);
  return Number.isFinite(n) ? n : FALLBACK_MS[tier];
}

/** token 缓动串：WAAPI 与 CSS 共用同一组曲线。 */
export function motionEase(kind: MotionEasing = "standard"): string {
  return cssVar(EASE_VAR[kind]) || FALLBACK_EASE[kind];
}

class MotionState {
  /** 用户偏好（设置浮层开关；持久化 vitro-motion）。 */
  enabled = $state(storeGet(KEYS.motion) !== "off");
  /** 系统偏好镜像（initMotion 订阅 matchMedia；展示/测试可读）。 */
  systemReduced = $state(false);
  /** 时间轴拖拽中（Timeline 写；scrub 是跳转语义，脉冲让位）。 */
  scrubbing = $state(false);
  /** 已放行的脉冲数（观测面：E2E 判预算是否真的放行/旁路，不靠动画时长赌时序）。 */
  pulseCount = 0;
  /** 已放行的 JS 过渡数（Svelte transition 不走 CSS 媒体查询——motion 关闭时
   *  由 gatedFade/growFromParent 直接给 duration 0；本计数只记 duration>0 的）。 */
  transitionCount = 0;
  /** 过渡函数被调用的次数（含 duration=0；诊断 Svelte 是否真的排了过渡）。 */
  transitionStarts = 0;
  /** 相机平滑真实放行的目标变更次数（瞬时模式不计；E2E 判 reduced/scrub
   *  是否让位，不靠采样时序赌）。 */
  cameraAnimations = 0;

  /** 一切动效（含 WAAPI）是否允许：用户关或系统 reduced 即旁路。 */
  get allowed(): boolean {
    return this.enabled && !this.systemReduced && !prefersReduced();
  }

  /** 脉冲类动效预算：播放 / 批量推进 / scrub 时让位；状态类高亮不受影响。 */
  get transientAllowed(): boolean {
    return this.allowed && !session.playing && !session.batching && !this.scrubbing;
  }
}

export const motion = new MotionState();

/** 唯一写口：html data-motion（CSS 一刀切停动画/过渡）。 */
function writeRootFlag(on: boolean): void {
  if (typeof document === "undefined") return;
  if (on) document.documentElement.removeAttribute("data-motion");
  else document.documentElement.setAttribute("data-motion", "off");
}

let watchingSystem = false;

/** 启动引导（App 顶层调用）：落盘偏好 + 系统偏好订阅。 */
export function initMotion(): void {
  writeRootFlag(motion.enabled);
  motion.systemReduced = prefersReduced();
  if (watchingSystem || typeof matchMedia !== "function") return;
  watchingSystem = true;
  const mq = matchMedia("(prefers-reduced-motion: reduce)");
  mq.addEventListener?.("change", (e) => {
    motion.systemReduced = e.matches;
  });
}

/** 设置浮层开关（持久化 + 立即生效）。 */
export function setMotion(on: boolean): void {
  motion.enabled = on;
  writeRootFlag(on);
  storeSet(KEYS.motion, on ? "on" : "off");
}

/** 时间轴 scrub 预算（Timeline 指针按下/松开）。 */
export function setScrubbing(on: boolean): void {
  motion.scrubbing = on;
}

export interface PulseOptions {
  tier?: MotionTier;
  easing?: MotionEasing;
}

/** Svelte transition 通用门（D2）：JS 过渡不吃 CSS 媒体查询/全局 !important，
 *  动效关或系统 reduced 时直接 duration 0。只计**真实放行**的过渡（E2E 判
 *  旁路是否生效的观测面）。armed=false 用于「首棵树不进/出场」（页面首帧
 *  不做生长动画，换树才演）。 */
export function gatedFade(_el: Element, params: { armed?: boolean } = {}): { duration: number; easing: typeof cubicOut; css: (t: number) => string } {
  motion.transitionStarts += 1;
  const duration = (params.armed ?? true) && motion.allowed ? motionMs("fast") : 0;
  if (duration > 0) motion.transitionCount += 1;
  return { duration, easing: cubicOut, css: (t) => `opacity: ${t}` };
}

const running = new WeakMap<Element, Animation>();

/** 单次脉冲：同一元素重复触发先取消上一次（不叠播）；预算关闭时返回 null。
 *  调用方负责静态状态（class/attr）——动效只是强调，不是语义的载体。 */
export function pulse(
  el: Element | null | undefined,
  keyframes: Keyframe[],
  opts: PulseOptions = {},
): Animation | null {
  if (!el || !motion.transientAllowed) return null;
  const animate = (el as HTMLElement).animate;
  if (typeof animate !== "function") return null;
  running.get(el)?.cancel();
  const anim = animate.call(el, keyframes, {
    duration: motionMs(opts.tier ?? "slow"),
    easing: motionEase(opts.easing ?? "emphasis"),
    fill: "none",
  });
  running.set(el, anim);
  motion.pulseCount += 1;
  void anim.finished
    .catch(() => undefined)
    .finally(() => {
      if (running.get(el) === anim) running.delete(el);
    });
  return anim;
}
