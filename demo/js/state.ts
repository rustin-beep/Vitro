// Vitro demo · 共享态（app.js 拆分批 2026-10-04，refs #28）。
// currentCase 由课程树点击写入、run/timetravel 读（configHint 语义只对基础
// 用例生效）；breakpointLines 由编辑器行号点击写、采集时读。
// 回放粒度/帧率（2026-10-09 语句级批）：真值在此、设置面板 seg 写入——原
// speedDd 速度下拉已随帧率进设置面板撤销（单一真值，免双 UI 同步）。
"use strict";

import { storeGet } from "./util.ts";

let currentCase = ""; // 当前基础用例 id（课程树写入；算法/扩展课载入时清空）
let breakpointLines: number[] = []; // 引擎断点行集（editor 行号点击写、timetravel 采集时读——2026-10-04，refs #28）

export type Gran = "stmt" | "insn";
let gran: Gran = storeGet("vitro-step-gran") === "insn" ? "insn" : "stmt"; // 默认语句级（播放时长与指令密度解耦）
const FPS_STEPS = [2, 8, 30, 60, 120, 240];
let fps = FPS_STEPS.includes(Number(storeGet("vitro-playback-fps"))) ? Number(storeGet("vitro-playback-fps")) : 8; // 默认 8 帧/秒

export function granularity(): Gran { return gran; }
export function setGranularity(g: Gran): void { gran = g; }
export function fpsValue(): number { return fps; }
export function setFps(v: number): void { fps = v; }
export function setCurrentCase(id: string): void { currentCase = id; }
export function currentCaseId(): string { return currentCase; }
export function currentBreakpoints(): number[] { return breakpointLines.slice(); }
export function toggleBreakpoint(line: number): void {
  const i = breakpointLines.indexOf(line);
  if (i >= 0) breakpointLines.splice(i, 1);
  else { breakpointLines.push(line); breakpointLines.sort((a, b) => a - b); }
}
