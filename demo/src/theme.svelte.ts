// Vitro · 主题五套 + 字号 + 动效的**单点写入口**（2026-10-18 前端改造）：
// html 元素 data-theme / data-size / data-motion 只由本层写，组件不直摸
// documentElement（旧栈 settings.ts 写口分散的反模式不再带入）。
//
// 五主题（用户 2026-10-18 拍板）：
//   ice       明亮实验室（旧色板原样）
//   rose      奶油手账（旧色板原样）
//   soft      绒面深蓝（旧色板原样）
//   paper     白天（纸）——设计稿新增
//   blueprint 夜航图——设计稿新增（接替退役的 glass 深夜书房）
"use strict";

import { KEYS, THEME_KEYS, migrateSize, migrateTheme, storeGet, storeSet, type ThemeKey } from "./persisted.svelte.ts";

/** 主题显示名（设置浮层 / 切换按钮 title）。 */
export const THEME_LABELS: Record<ThemeKey, string> = {
  ice: "明亮实验室",
  rose: "奶油手账",
  soft: "绒面深蓝",
  paper: "白天（纸）",
  blueprint: "夜航图",
};

/** 五主题三色预览点（色面字面量 = 展示预览豁免：渲染当前值无意义，
 *  点要的是目标主题的色板印象）。 */
export const THEME_DOTS: Record<ThemeKey, [string, string, string]> = {
  ice: ["#f2f7fd", "#2563eb", "#1a2740"],
  rose: ["#fbf5f7", "#d4597a", "#2e2428"],
  soft: ["#0d1428", "#7a94e6", "#e6ebf7"],
  paper: ["#efe7d8", "#96520a", "#1d1a15"],
  blueprint: ["#08111a", "#ff8a3c", "#dbe8f4"],
};

/** 夜侧主题（logo 双变体 / color-scheme 判定）。 */
export const NIGHT_THEMES: ReadonlySet<string> = new Set(["soft", "blueprint"]);
export const SIZE_STEPS: readonly string[] = ["13", "14", "16"];
export const SIZE_LABELS: Record<string, string> = { "13": "小", "14": "中", "16": "大" };

export const themeState = $state({ current: "paper" as ThemeKey, size: "14" });

function root(): HTMLElement {
  return document.documentElement;
}

/** 应用主题（唯一写入口）。 */
export function applyTheme(v: ThemeKey): void {
  themeState.current = v;
  root().setAttribute("data-theme", v);
  root().setAttribute("data-shade", NIGHT_THEMES.has(v) ? "night" : "day");
}

/** 应用字号档（13/14/16）。 */
export function applySize(v: string): void {
  const size = SIZE_STEPS.includes(v) ? v : "14";
  themeState.size = size;
  root().setAttribute("data-size", size);
}

/** 动效开关（关 = data-motion="off"，CSS 一刀切停动画/过渡）。 */
export function applyMotion(on: boolean): void {
  if (!on) root().setAttribute("data-motion", "off");
  else root().removeAttribute("data-motion");
}

/** 头部主题按钮：按固定序循环五套（设置里可直接点名）。 */
export function cycleTheme(): ThemeKey {
  const i = (THEME_KEYS as readonly string[]).indexOf(themeState.current ?? "");
  const next = THEME_KEYS[(i + 1) % THEME_KEYS.length];
  if (next === undefined) throw new Error("THEME_KEYS 为空");
  applyTheme(next);
  storeSet(KEYS.theme, next);
  return next;
}

/** 启动引导：读旧值迁移 + 落盘规范化（首访写回 paper，防迁移链再次分叉）。 */
export function initTheme(): void {
  const raw = storeGet(KEYS.theme);
  const theme = migrateTheme(raw);
  applyTheme(theme);
  storeSet(KEYS.theme, theme);
  const size = migrateSize(storeGet(KEYS.size) || storeGet(KEYS.edFont));
  applySize(size);
  storeSet(KEYS.size, size);
  applyMotion(storeGet(KEYS.motion) !== "off");
}
