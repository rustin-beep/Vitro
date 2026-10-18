// Vitro demo · 页面工具（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。TS 重写批：签名类型化。）
"use strict";

import { ICONS } from "./icons.ts";

export const MEM_TOTAL = 1024 * 1024; // 1MB 内存映射（引擎口径）

// 中文等 UTF-8 多字节序列在此形态下是 mojibake——按字节还原为文本。
export const latin1ToUtf8 = (delta: string | null | undefined): string => {
  if (!delta) return "";
  const bytes = new Uint8Array(delta.length);
  for (let i = 0; i < delta.length; i++) bytes[i] = delta.charCodeAt(i) & 0xff;
  return new TextDecoder("utf-8").decode(bytes);
};

/** 含数组声明的用例判定（「· 数组动画」标注——时间旅行对这类用例出柱状图；
 *  声明形态正则：`int a[8]` 命中、下标访问 `a[0]` 不误标；紧凑/指针形态
 *  `int*p[4]`/`int** m[2]` 同命中——存量 bug 修复锁见 pure.test.mts）。 */
export function isArrayAnimCase(source: string): boolean {
  return /(?:int|char|long|short|unsigned|float|double)\s*(?:\*+\s*)?\w+\s*\[\s*\d+\s*\]/.test(source);
}

// ── localStorage 安全读写（settings/state 共用单源；隐私模式静默）──
export function storeGet(key: string): string | null { try { return localStorage.getItem(key); } catch { return null; } }
export function storeSet(key: string, val: string): void { try { localStorage.setItem(key, val); } catch { /* 存储不可用 */ } }

// ── 回放粒度变换（2026-10-09 语句级批）──────────────────────────
// 按 code_line 把连续同行的帧划成语句组。指令级=原帧全集仅标注组内位置；
// 语句级=每组取组尾帧（语句执行完的状态——局部变量表/调用栈是句末快照），
// 播放时长与 VM 指令密度解耦、只与语句执行次数成正比（冒泡实测 1018→42）。
export interface GranGroup<F> { f: F; m: number; k: number }

/** 相邻同 code_line 的帧划为一组，组内标序 m（1 起）、组大小 k。O(n) 单遍。 */
export function annotateGroups<F extends { code_line: number }>(frames: F[]): GranGroup<F>[] {
  const out: GranGroup<F>[] = [];
  let start = 0;
  for (let i = 1; i <= frames.length; i++) {
    if (i === frames.length || frames[i].code_line !== frames[start].code_line) {
      for (let j = start; j < i; j++) out.push({ f: frames[j], m: j - start + 1, k: i - start });
      start = i;
    }
  }
  return out;
}

/** 语句级帧序列：每组取组尾帧（m === k）。 */
export function coalesceStmt<F extends { code_line: number }>(frames: F[]): F[] {
  return annotateGroups(frames).filter((g) => g.m === g.k).map((g) => g.f);
}

export function esc(s: string): string {
  return String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] as string));
}

/** A17（#140）：[语义id] → 内联 SVG 徽章（旧栈 icon.ts decorateBadges 同
 *  语义，白名单 = icons.ts ICONS 表）。**输入必须先 esc**——本函数只做
 *  表替换不引入转义义务（{@html} 消费面的转义责任在调用方）。 */
export function decorateBadges(escaped: string): string {
  return escaped.replace(/\[([a-z0-9_-]+)\]/gi, (m, id: string) => {
    const svg = ICONS[id];
    return svg ? `<span class="icon-svg">${svg}</span>` : m;
  });
}

/** trap 详报格式化（#140 收口批：语义徽章 + E 码 mono 徽章 + 结构标签加粗）。
 *  输入必须先 esc（同 decorateBadges 契约）。[cause]/[fix]/[location] 是
 *  结构化字段标记（非语义 id，不在 ICONS 表——保留文本只做视觉区分）；
 *  E 码（E3xxx 族）渲染为等宽徽章「码表」样式，data-ecode 供 RunMeta 事件
 *  委托跳诊断手册（P2-10 轻量联动）。 */
export function formatTrap(escaped: string): string {
  return decorateBadges(escaped)
    .replace(/\[(cause|fix|location)\]/g, '<b class="tp-tag">[$1]</b>')
    .replace(/\b(E[1-9][0-9]{3})\b/g, '<code class="tp-code" data-ecode="$1">$1</code>');
}
