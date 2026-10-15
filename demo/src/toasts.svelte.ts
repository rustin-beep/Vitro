// Vitro 试点 · 操作反馈 toast 队列（F4 基础设施，审阅 B-P2-9 的根治面）：
// 旧栈 setStatus 是全局单例、23+ 调用点全量覆盖、后到者赢（坏分享链接被
// 「就绪」覆盖的实测事故即此形态）。新契约分域：
//   - session.status = 引擎/会话域状态（采集态/帧数）——恒显示不抢过期；
//   - toasts = 操作结果反馈（失败原因/边界事件）——自动过期、可手关。
"use strict";

export type ToastKind = "ok" | "err" | "info";

export interface Toast {
  id: number;
  kind: ToastKind;
  text: string;
}

export const toasts = $state<{ items: Toast[] }>({ items: [] });

let nextId = 1;
const timers = new Map<number, ReturnType<typeof setTimeout>>();

export function toast(kind: ToastKind, text: string, ms = 4200): void {
  const id = nextId++;
  toasts.items.push({ id, kind, text });
  timers.set(
    id,
    setTimeout(() => dismiss(id), ms),
  );
}

export function dismiss(id: number): void {
  const t = timers.get(id);
  if (t !== undefined) {
    clearTimeout(t);
    timers.delete(id);
  }
  const i = toasts.items.findIndex((x) => x.id === id);
  if (i >= 0) toasts.items.splice(i, 1);
}
