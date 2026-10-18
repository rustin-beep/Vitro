// Vitro · 三态信息架构的单点（2026-10-18 前端改造）：
//   工作态 work  —— 左书右仪（默认落地）
//   入口态 entry —— 课程目录（顶栏「课程」）
//   参考态 ref   —— 诊断手册（顶栏「诊断手册」/ 一句话诊断跳转）
// 仪器三模式（工作态内）：exec 执行 / mem 内存 / proto 协议。
//
// 旧栈 tabs.svelte.ts（内容/运行/内存地图/诊断手册/引擎与协议五 tab）按设计
// 说明 §2.1 归并——语义落点见设计说明，状态集中在此，组件零本地导航态。
"use strict";

export type Screen = "work" | "entry" | "ref";
export type Mode = "exec" | "mem" | "proto";

class UiState {
  screen = $state<Screen>("work");
  mode = $state<Mode>("exec");
  /** 诊断手册当前条目（空 = 首条/由页面自选）。 */
  refCode = $state("");
  /** 课程目录：当前章 / 当前预览课（点课只换预览，不跳转——A-3/B 反馈④）。 */
  entryChapter = $state("");
  entryLesson = $state("");
  /** 首访落地位：boot 链（协议面 + 首课装载/采集）走完后才撤加载遮罩——
   *  否则遮罩先撤、默认示例先闪一帧再被 bubble 覆盖（2026-10-18 实测形态）。 */
  ready = $state(false);
  // 浮层（锚定 —— 不用 portal/fixed）
  settingsOpen = $state(false);
  shareOpen = $state(false);
  // 面板折叠
  diagOpen = $state(false);
  paramsOpen = $state(false);
  railExpanded = $state(false);
}

export const ui = new UiState();

export function showWork(): void {
  ui.screen = "work";
  ui.settingsOpen = false;
}

export function showEntry(): void {
  ui.screen = "entry";
  ui.settingsOpen = false;
}

/** 打开诊断手册（code 非空则定位该条目——一句话诊断 / trap 报告跳转）。 */
export function showRef(code = ""): void {
  if (code) ui.refCode = code;
  ui.screen = "ref";
  ui.settingsOpen = false;
}

export function setMode(m: Mode): void {
  ui.mode = m;
}
