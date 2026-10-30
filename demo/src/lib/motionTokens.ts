// motion 的 CSS token 兜底值（纯数据，无 Svelte runes——pure.test 直接 import 对账）。
//
// 只在 CSS 变量读不到时使用（首帧早期）。与 demo/tokens.json 的**等值**由
// tests/pure.test.mts 锁死：改 token 漏改兜底会直接红，不再静默分叉。
// 这些 token 都是 :root 基座（非主题色板），页面生命周期内不会随 data-theme 变。
"use strict";

export const FALLBACK_MS = { fast: 90, base: 160, slow: 280 } as const;

export const FALLBACK_EASE = {
  standard: "cubic-bezier(.2, .7, .3, 1)",
  emphasis: "cubic-bezier(.2, .9, .25, 1)",
  enter: "cubic-bezier(.22, 1, .36, 1)",
} as const;

export const EASE_VAR = {
  standard: "--vr-ease",
  emphasis: "--vr-ease-emphasis",
  enter: "--vr-ease-enter",
} as const;
