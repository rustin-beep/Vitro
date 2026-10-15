// Vitro 试点 · theme effects 层（F4 基础设施）：html 元素属性副作用
// （data-theme / data-shade / data-motion / --ed-fs）的**单点写入口**——
// 旧栈 settings.ts 每函数直摸 documentElement、写口分散（审阅 A-P2 形态）；
// 新栈组件只调本层，不直接碰 documentElement。
"use strict";

// 与 settings.ts 逐字一致（F4 迁移时随组件合流单源；改任一侧须对表）
export const THEMES: readonly string[] = ["ice", "rose", "paper", "glass", "soft"];
export const NIGHT_THEMES: ReadonlySet<string> = new Set(["glass", "soft"]);
export const ED_FONT_STEPS: readonly string[] = ["13px", "14px", "16px"];

function root(): HTMLElement {
  return document.documentElement;
}

/** 当前主题（单一状态点）：applyTheme 是唯一写入口，消费方只读
 *  themeState.current——App 头部按钮与 SettingsView 不得各持副本
 *  （状态散布即分裂，2026-10-15 试点实测教训）。 */
export const themeState = $state({ current: "glass" });

export function applyTheme(v: string): void {
  themeState.current = v;
  root().setAttribute("data-theme", v);
  root().setAttribute("data-shade", NIGHT_THEMES.has(v) ? "night" : "day");
}

/** 夜↔日主题对切（theme-toggle 语义：夜主题切到 ice，日主题切到 glass）。 */
export function toggleThemeFamily(current: string): string {
  const next = NIGHT_THEMES.has(current) ? "ice" : "glass";
  applyTheme(next);
  return next;
}

export function applyMotion(on: boolean): void {
  if (!on) root().setAttribute("data-motion", "off");
  else root().removeAttribute("data-motion");
}

export function applyEditorFont(px: string): void {
  root().style.setProperty("--ed-fs", px);
}
