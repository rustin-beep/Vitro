// Vitro demo · 内存地图（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。）
"use strict";

import { MEM_TOTAL, $, esc } from "./util.js";

export function heapSpanOf(mem) {
  const heapEnd = Math.max(
    mem.heap_offset ?? 0,
    ...mem.regions.filter((r) => r.is_heap).map((r) => r.addr + r.size),
    mem.heap_base + 64
  );
  return { heapBase: mem.heap_base, heapEnd, span: heapEnd - mem.heap_base };
}

export function renderMemory(mem) {
  $("mem-stats").innerHTML =
    `<span>全局 ${mem.region_counts.global}</span>` +
    `<span>堆 ${mem.region_counts.heap}</span>` +
    `<span>栈 ${mem.region_counts.stack}</span>` +
    `<span>分配计数 ${mem.alloc_counter}</span>` +
    `<span>free_list ${mem.free_list.length}</span>` +
    `<span>隔离区 ${mem.quarantine.bytes} / ${mem.quarantine.budget} 字节（${mem.quarantine.blocks} 块）</span>`;

  const band = $("mem-band-full");
  bandRender(
    band,
    mem.regions.map((r) => ({ r, left: r.addr / MEM_TOTAL, width: Math.max(r.size / MEM_TOTAL, 0.004) }))
  );
  const { heapBase, span: heapSpan } = heapSpanOf(mem);
  const zoom = $("mem-band-heap");
  bandRender(
    zoom,
    mem.regions
      .filter((r) => r.is_heap)
      .map((r) => ({ r, left: (r.addr - heapBase) / heapSpan, width: Math.max(r.size / heapSpan, 0.02) }))
  );
  $("mem-zoom-label").textContent =
    `堆区放大 0x${heapBase.toString(16)} – 0x${heapSpanOf(mem).heapEnd.toString(16)}（span ${heapSpan} B）`;

  const q = mem.quarantine;
  $("quar-bar-fill").style.width = `${Math.min((q.bytes / q.budget) * 100, 100)}%`;
  $("quar-label").textContent = `quarantine（UAF 检测窗）：${q.blocks} 块 / ${q.bytes} B，预算 ${q.budget} B`;

  $("mem-table").innerHTML =
    "<tr><th>地址</th><th>大小</th><th>名称</th><th>类型</th><th>段</th><th>状态</th><th>分配行</th><th>来源</th></tr>" +
    mem.regions
      .map(
        (r) =>
          `<tr class="${r.is_freed ? "freed" : ""}"><td>0x${r.addr.toString(16)}</td><td>${r.size} B</td>` +
          `<td>${esc(r.name)}</td><td>${esc(r.ty)}</td><td>${esc(r.kind)}</td>` +
          `<td>${r.is_freed ? "freed（隔离中）" : "活跃"}</td><td>${r.alloc_line || "—"}</td><td>${esc(r.alloc_by)}</td></tr>`
      )
      .join("");
}

// 条块 keyed 复用（F-1b②）：addr/size 过渡的前提是元素存活——同 key 只更新
// 位置/尺寸/状态类，transition 才吃得到变化；本帧消失的 key 直接移除。
// key 含 addr+size+name：同一位置复分配出的新块视为新块（瞬现，不跨会话漂移）。
function bandRender(band, entries) {
  for (const n of Array.from(band.childNodes)) {
    // 占位提示（HTML 静态 .muted.center 与 selectCase 重置的 .muted 两种）一律清，
    // 条块本体（.blk）是复用对象，不能动
    if (!(n.nodeType === 1 && n.classList.contains("blk"))) n.remove();
  }
  const seen = new Set();
  for (const { r, left, width } of entries) {
    const key = `${r.addr}:${r.size}:${r.name}`;
    seen.add(key);
    let b = band.querySelector(`[data-key="${CSS.escape(key)}"]`);
    if (!b) {
      b = document.createElement("div");
      b.dataset.key = key;
      band.appendChild(b);
    }
    b.className = "blk " + r.kind + (r.is_freed ? " freed" : "");
    b.style.left = `${Math.min(left * 100, 99.6)}%`;
    b.style.width = `${width * 100}%`;
    b.title = `${r.name} · ${r.ty} · ${r.size} B @0x${r.addr.toString(16)}${r.is_freed ? " · freed" : ""}`;
  }
  for (const b of band.querySelectorAll(".blk")) {
    if (!seen.has(b.dataset.key)) b.remove();
  }
}

// ── 诊断手册（error_catalog）────────────────────────────
