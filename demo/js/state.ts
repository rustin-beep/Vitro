// Vitro demo · 共享态（app.js 拆分批 2026-10-04，refs #28）。
// speedDd 由 timetravel 的 bindAnim 创建、播放调速读；currentCase 由
// course 树的基础课点击写入（下拉已随课程树重构撤销）、run/timetravel
// 读（configHint 语义只对基础用例生效）。ESM export 只读绑定的限制下
// 用 get/set 对（比模块循环 import 干净）。
"use strict";

import type { Dropdown } from "./util.ts";

let speedDd: Dropdown | null = null;
let currentCase = ""; // 当前基础用例 id（课程树写入；算法/扩展课载入时清空）
let breakpointLines: number[] = []; // 引擎断点行集（editor 行号点击写、timetravel 采集时读——2026-10-04，refs #28）

export function setSpeedDropdown(d: Dropdown): void { speedDd = d; }
export function speedValue(): string { return speedDd ? speedDd.value : "200"; }
export function setCurrentCase(id: string): void { currentCase = id; }
export function currentCaseId(): string { return currentCase; }
export function currentBreakpoints(): number[] { return breakpointLines.slice(); }
export function toggleBreakpoint(line: number): void {
  const i = breakpointLines.indexOf(line);
  if (i >= 0) breakpointLines.splice(i, 1);
  else { breakpointLines.push(line); breakpointLines.sort((a, b) => a - b); }
}
