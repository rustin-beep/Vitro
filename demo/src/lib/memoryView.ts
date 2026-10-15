// memoryView —— 内存地图纯变换（F4 组件迁移，审阅 C-P1-4 处方）：
// 旧栈 renderMemory 五个 DOM 产出一锅烩、heapSpanOf 每帧双跑、E-08 无落点；
// 此处 payload→视图模型全部抽纯函数（heapSpanOf 物理保留 js/memory.ts——
// tests 锚零改动），组件侧 $derived 消费。
// kind 显式映射（审阅 C-P2-7：引擎 kind 裸拼 className 无校验面——未知 kind
// 落可见 unknown 灰 + 不静默）。
"use strict";

import { MEM_TOTAL } from "../../js/util.ts";
import { heapSpanOf } from "../../js/memory.ts";
import type { MemoryRegions, HeapRegion } from "../../js/types.ts";

export interface BandEntry {
  key: string; // addr:size:name（同位复分配视为新块——旧栈同语义）
  r: HeapRegion;
  cls: string; // 显式映射后的类（blk 基类外）
  left: number; // 0..1
  width: number; // 0..1
  title: string;
}

// 引擎 kind → 显示类显式表；未知 kind 落 "kind-unknown"（可见灰块不静默）
const KIND_CLASS: Record<string, string> = {
  global: "k-global",
  heap: "k-heap",
  stack: "k-stack",
};

function clsOf(r: HeapRegion): string {
  const base = KIND_CLASS[r.kind] ?? "k-unknown";
  return r.is_freed ? `${base} freed` : base;
}

function entryOf(r: HeapRegion, left: number, width: number): BandEntry {
  return {
    key: `${r.addr}:${r.size}:${r.name}`,
    r,
    cls: clsOf(r),
    left: Math.min(left, 0.996), // 右缘截断（旧栈同值；块间静默叠块的登记随旧栈继承）
    width: Math.max(width, 0.004),
    title: `${r.name} · ${r.ty} · ${r.size} B @0x${r.addr.toString(16)}${r.is_freed ? " · freed" : ""}`,
  };
}

/** 全局内存带条目（addr/MEM_TOTAL 线性映射）。 */
export function fullBandEntries(mem: MemoryRegions): BandEntry[] {
  return mem.regions.map((r) => entryOf(r, r.addr / MEM_TOTAL, r.size / MEM_TOTAL));
}

/** 堆放大带条目（heapSpan 内线性映射 + 0.02 最小可见宽）。 */
export function heapBandEntries(mem: MemoryRegions): BandEntry[] {
  const { heapBase, span } = heapSpanOf(mem);
  return mem.regions
    .filter((r) => r.is_heap)
    .map((r) => entryOf(r, (r.addr - heapBase) / span, r.size / span));
}

export function heapZoomLabel(mem: MemoryRegions): string {
  const { heapBase, heapEnd, span } = heapSpanOf(mem);
  return `堆区放大 0x${heapBase.toString(16)} – 0x${heapEnd.toString(16)}（span ${span} B）`;
}

export interface MemStat {
  label: string;
  value: string;
}

export function memStats(mem: MemoryRegions): MemStat[] {
  const q = mem.quarantine;
  return [
    { label: "全局", value: String(mem.region_counts.global) },
    { label: "堆", value: String(mem.region_counts.heap) },
    { label: "栈", value: String(mem.region_counts.stack) },
    { label: "分配计数", value: String(mem.alloc_counter) },
    { label: "free_list", value: String(mem.free_list.length) },
    { label: "隔离区", value: `${q.bytes} / ${q.budget} 字节（${q.blocks} 块）` },
  ];
}

export function quarPct(mem: MemoryRegions): number {
  return Math.min((mem.quarantine.bytes / mem.quarantine.budget) * 100, 100);
}

export function tableRows(mem: MemoryRegions): Array<{
  addrHex: string;
  size: string;
  name: string;
  ty: string;
  kind: string;
  freed: boolean;
  allocLine: string;
  allocBy: string;
}> {
  return mem.regions.map((r) => ({
    addrHex: "0x" + r.addr.toString(16),
    size: `${r.size} B`,
    name: r.name,
    ty: r.ty,
    kind: r.kind,
    freed: r.is_freed,
    allocLine: r.alloc_line ? String(r.alloc_line) : "—",
    allocBy: r.alloc_by,
  }));
}
