// Vitro · 学习进度与「继续上次」单点（2026-10-18 前端改造）：
//   - 已完成课集合：沿用旧键 vitro-course-done（两栈数据互通），点课即标完成；
//   - 上次停留：vitro-last-visit = { lessonId, chapId, title, frame, total, at }。
//     「继续上次」卡与首访落地都读它（设计说明 §2.3 / 入口态「继续上次」）。
// 写入口只有 markDone / rememberLesson / rememberFrame——组件只读。
"use strict";

import { KEYS, storeGet, storeSet, storeGetJSON, storeSetJSON } from "../persisted.svelte.ts";

export interface LastVisit {
  lessonId: string;
  chapId: string;
  title: string;
  frame: number;
  total: number;
  at: number;
}

class ProgressState {
  done = $state<string[]>([]);
  last = $state<LastVisit | null>(null);

  constructor() {
    try {
      const raw = JSON.parse(storeGet(KEYS.courseDone) || "[]") as unknown;
      this.done = Array.isArray(raw) ? raw.filter((x): x is string => typeof x === "string") : [];
    } catch {
      this.done = [];
    }
    const last = storeGetJSON<LastVisit | null>(KEYS.lastVisit, null);
    this.last = last && typeof last.lessonId === "string" ? last : null;
  }

  get doneCount(): number {
    return this.done.length;
  }

  isDone(id: string): boolean {
    return this.done.includes(id);
  }

  markDone(id: string): void {
    if (this.done.includes(id)) return;
    this.done = [...this.done, id];
    storeSet(KEYS.courseDone, JSON.stringify(this.done));
  }

  rememberLesson(lessonId: string, chapId: string, title: string): void {
    const prev = this.last;
    if (prev && prev.lessonId === lessonId && prev.chapId === chapId) return;
    this.last = { lessonId, chapId, title, frame: 0, total: 0, at: Date.now() };
    storeSetJSON(KEYS.lastVisit, this.last);
  }

  /** 记帧（去抖在调用侧；同一课才写——切课后旧帧不得冒充新课进度）。 */
  rememberFrame(lessonId: string, chapId: string, frame: number, total: number): void {
    const prev = this.last;
    if (!prev || prev.lessonId !== lessonId || prev.chapId !== chapId) return;
    if (prev.frame === frame && prev.total === total) return;
    this.last = { ...prev, frame, total, at: Date.now() };
    storeSetJSON(KEYS.lastVisit, this.last);
  }
}

export const progress = new ProgressState();
