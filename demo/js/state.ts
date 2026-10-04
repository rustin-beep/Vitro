// Vitro demo · 共享下拉实例（app.js 拆分批 2026-10-04，refs #28）。
// caseDd 由入口 boot 创建、selectCase/run/timetravel 读；speedDd 由
// timetravel 的 bindAnim 创建、播放调速读。ESM export 只读绑定的限制下
// 用 get/set 对（比模块循环 import 干净）。
"use strict";

let caseDd = null;
let speedDd = null;

export function setCaseDropdown(d) { caseDd = d; }
export function currentCaseId() { return caseDd ? caseDd.value : ""; }
export function setSpeedDropdown(d) { speedDd = d; }
export function speedValue() { return speedDd ? speedDd.value : "200"; }
