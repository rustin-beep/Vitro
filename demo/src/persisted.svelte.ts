// Vitro 试点 · 持久化单源层（F4 基础设施，审阅 B-P2-10/A-P2-14 的根治面）：
// localStorage 键名表 + 安全读写（隐私模式/quota 满静默兜底——旧栈 course.ts
// saveDone 裸 setItem 抛未处理拒绝的实锤）+ 旧值迁移链。
//
// 键名与现役 demo 契约兼容（老用户 localStorage 直接共享，逐字保留勿改）；
// 迁移逻辑与 index.html 防闪内联脚本各一份属**有意双处**（防闪必须在 DOM
// 解析期执行、无法共享模块——但迁移规则必须逐字一致，改任一侧须对表另一侧）。
"use strict";

export const KEYS = {
  theme: "vitro-theme",
  edFont: "vitro-ed-font",
  motion: "vitro-motion",
  stepGran: "vitro-step-gran",
  playbackFps: "vitro-playback-fps",
  replayWide: "vitro-replay-wide",
  courseDone: "vitro-course-done",
  cap: "vitro-collect-cap", // 试点新增（旧栈无此键，F2 的 #89 稀疏采集就绪后可能再变语义）
} as const;

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

/** 主题旧值迁移（与 index.html 防闪脚本逐字同规则：light→ice、空/dark→glass）。 */
export function migrateTheme(raw: string): string {
  if (raw === "light") return "ice";
  if (!raw || raw === "dark") return "glass";
  return raw;
}
