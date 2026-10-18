// Vitro · 持久化单源层（2026-10-18 前端改造批）：
// localStorage 键名表 + 安全读写（隐私模式/quota 满静默兜底）+ 旧值迁移链。
//
// 键名与旧 demo/试点兼容（老用户 localStorage 直接共享）；新增两键：
//   vitro-size      字号档（13/14/16——旧 vitro-ed-font 的 px 值迁移）
//   vitro-last-visit 上次课 + 帧（「继续上次」的真实数据源）
// 主题键沿用 vitro-theme：五主题 ice/rose/soft/paper/blueprint；
// 旧 glass（深夜书房）→ blueprint（夜航图），旧 paper 键保留但色板换成
// 设计稿「白天（纸）」（用户 2026-10-18 拍板：牛皮档案 → 白天）。
// ⚠️ 迁移规则与 demo/index.html 防闪内联脚本**逐字一致**（防闪必须在 DOM
// 解析期执行、无法共享模块——改任一侧须对表另一侧）。
"use strict";

export const KEYS = {
  theme: "vitro-theme",
  size: "vitro-size",
  edFont: "vitro-ed-font", // 旧键（只读迁移）
  motion: "vitro-motion",
  stepGran: "vitro-step-gran",
  playbackFps: "vitro-playback-fps",
  replayWide: "vitro-replay-wide",
  courseDone: "vitro-course-done",
  cap: "vitro-collect-cap",
  lastVisit: "vitro-last-visit",
} as const;

export const THEME_KEYS = ["ice", "rose", "soft", "paper", "blueprint"] as const;
export type ThemeKey = (typeof THEME_KEYS)[number];

export function storeGet(key: string): string {
  try {
    return localStorage.getItem(key) ?? "";
  } catch {
    return "";
  }
}

export function storeSet(key: string, v: string): void {
  try {
    localStorage.setItem(key, v);
  } catch {
    /* 隐私模式/quota 满——持久化是尽力而为，静默兜底 */
  }
}

export function storeGetJSON<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw === null ? fallback : (JSON.parse(raw) as T);
  } catch {
    return fallback;
  }
}

export function storeSetJSON(key: string, v: unknown): void {
  storeSet(key, JSON.stringify(v));
}

/** 主题旧值迁移（与 index.html 防闪脚本逐字同规则）：
 *  light→ice · dark/空→paper · glass→blueprint
 *  未登记的键（含旧 rose/soft/paper/ice）原样返回；未知值回落 paper。 */
export function migrateTheme(raw: string): ThemeKey {
  if (raw === "light") return "ice";
  if (raw === "dark" || raw === "") return "paper";
  if (raw === "glass") return "blueprint"; // 深夜书房退役 → 夜航图
  return (THEME_KEYS as readonly string[]).includes(raw) ? (raw as ThemeKey) : "paper";
}

/** 字号档迁移：新键优先；旧 vitro-ed-font 的 "13px"/"14px"/"16px" 折成档位。 */
export function migrateSize(raw: string): string {
  if (raw === "13" || raw === "14" || raw === "16") return raw;
  if (raw === "13px") return "13";
  if (raw === "16px") return "16";
  return "14";
}
