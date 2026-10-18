// tab 状态单点（F4 基础设施，审阅 B-P2-11 处方：旧栈「模拟点击 tab 按钮」
// 的反模式在新栈的正解 = activeTab store；课程点课/分享等流程直接写本 store，
// 禁止任何合成 DOM 点击）。tab 集合与命名对齐现役 demo data-tab。
"use strict";

export type TabId = "content" | "run" | "mem" | "cat" | "proto";

export const TAB_DEFS: Array<{ id: TabId; label: string }> = [
  { id: "content", label: "内容" },
  { id: "run", label: "运行" },
  { id: "mem", label: "内存地图" },
  { id: "cat", label: "诊断手册" },
  { id: "proto", label: "引擎与协议" },
];

export const activeTab = $state<{ current: TabId }>({ current: "content" });

/** P2-10 轻量联动（2026-10-18）：E 码 → 诊断手册跳转种子。诊断卡/trap 详报
 *  的 E 码点击后置种子并切 cat tab，CatalogView 消费后清空（一次性种子，
 *  防用户手动清搜索后被回跳覆盖）。 */
export const catalogSeed = $state<{ q: string }>({ q: "" });

export function jumpToCatalog(code: string): void {
  catalogSeed.q = code;
  activeTab.current = "cat";
}

export function switchTab(id: TabId): void {
  activeTab.current = id;
}
