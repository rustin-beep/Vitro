// Vitro demo · 共享下拉实例（app.js 拆分批 2026-10-04，refs #28）。
// caseDd 由入口 boot 创建、selectCase/run/timetravel 读；speedDd 由
// timetravel 的 bindAnim 创建、播放调速读。ESM export 只读绑定的限制下
// 用 get/set 对（比模块循环 import 干净）。
"use strict";

import type { Dropdown } from "./util.ts";

let caseDd: Dropdown | null = null;
let speedDd: Dropdown | null = null;
let breakpointLines: number[] = []; // 引擎断点行集（editor 行号点击写、timetravel 采集时读——2026-10-04，refs #28）

export function setCaseDropdown(d: Dropdown): void { caseDd = d; }
export function currentCaseId(): string { return caseDd ? caseDd.value : ""; }
export function setSpeedDropdown(d: Dropdown): void { speedDd = d; }
export function speedValue(): string { return speedDd ? speedDd.value : "200"; }
export function currentBreakpoints(): number[] { return breakpointLines.slice(); }
export function toggleBreakpoint(line: number): void {
  const i = breakpointLines.indexOf(line);
  if (i >= 0) breakpointLines.splice(i, 1);
  else { breakpointLines.push(line); breakpointLines.sort((a, b) => a - b); }
}
