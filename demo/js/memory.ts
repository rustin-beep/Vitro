// Vitro demo · 内存跨度纯函数面（2026-10-17 F4 收尾：地图渲染随旧栈退役，
// 新栈 MemoryView.svelte 自绘；本文件只留 heapSpanOf——pure.test 锚定面不变）。
"use strict";

import type { HeapRegion } from "./types.ts";

export interface HeapSpan {
  heapBase: number;
  heapEnd: number;
  span: number;
}

// heapSpanOf 的入参消费面（2026-10-04 审阅 P3-④/tests 类型面）：只读本三
// 面（heap_offset 体内 ?? 0 兜底故可选）——MemoryRegions 结构兼容可直传，
// 测试 mock 只需造最小 regions 块
export interface HeapSpanInput {
  heap_base: number;
  heap_offset?: number;
  regions: Array<Pick<HeapRegion, "is_heap" | "addr" | "size">>;
}

export function heapSpanOf(mem: HeapSpanInput): HeapSpan {
  const heapEnd = Math.max(
    mem.heap_offset ?? 0,
    ...mem.regions.filter((r) => r.is_heap).map((r) => r.addr + r.size),
    mem.heap_base + 64
  );
  return { heapBase: mem.heap_base, heapEnd, span: heapEnd - mem.heap_base };
}
