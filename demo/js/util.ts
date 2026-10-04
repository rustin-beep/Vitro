// Vitro demo · 页面工具（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。）
"use strict";

export const MEM_TOTAL = 1024 * 1024; // 1MB 内存映射（引擎口径）
// 中文等 UTF-8 多字节序列在此形态下是 mojibake——按字节还原为文本。
export const latin1ToUtf8 = (delta) => {
  if (!delta) return "";
  const bytes = new Uint8Array(delta.length);
  for (let i = 0; i < delta.length; i++) bytes[i] = delta.charCodeAt(i) & 0xff;
  return new TextDecoder("utf-8").decode(bytes);
};

// ── 页面骨架 ──────────────────────────────────────────────
export const $ = (id) => document.getElementById(id);
export function makeDropdown(hostId, items, value, onChange) {
  const host = $(hostId);
  host.innerHTML =
    '<button type="button" class="dd-btn" aria-haspopup="listbox" aria-expanded="false">' +
    '<span class="dd-label"></span>' +
    '<svg class="dd-chev" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>' +
    '</button><div class="dd-list" role="listbox" hidden></div>';
  const btn = host.querySelector(".dd-btn");
  const label = host.querySelector(".dd-label");
  const list = host.querySelector(".dd-list");
  let cur = value;
  let committed = value;
  const idxOf = () => items.findIndex((i) => i.v === cur);
  function syncLabel() {
    const it = items[idxOf()];
    label.textContent = it ? it.label : "";
  }
  function renderList() {
    list.innerHTML = items
      .map((i) =>
        `<button type="button" class="dd-opt${i.v === cur ? " on" : ""}" role="option" aria-selected="${i.v === cur}" data-v="${esc(String(i.v))}">${esc(i.label)}</button>`
      )
      .join("");
  }
  function open() {
    committed = cur;
    renderList();
    list.hidden = false;
    host.setAttribute("data-open", "");
    btn.setAttribute("aria-expanded", "true");
    const el = list.querySelector(".dd-opt.on");
    if (el) el.scrollIntoView({ block: "nearest" });
  }
  function close() {
    list.hidden = true;
    host.removeAttribute("data-open");
    btn.setAttribute("aria-expanded", "false");
  }
  function pick(v) {
    cur = v;
    syncLabel();
    close();
    if (onChange) onChange(v);
  }
  btn.onclick = () => (list.hidden ? open() : close());
  list.onclick = (e) => {
    const opt = e.target.closest(".dd-opt");
    if (opt) pick(opt.dataset.v);
  };
  btn.onkeydown = (e) => {
    if (list.hidden) {
      if (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        open();
      }
      return;
    }
    if (e.key === "Escape") {
      e.stopPropagation();
      cur = committed; // 撤回浏览未确认的值
      syncLabel();
      close();
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const idx = Math.max(0, idxOf()) + (e.key === "ArrowDown" ? 1 : -1);
      cur = items[Math.max(0, Math.min(idx, items.length - 1))].v;
      renderList();
      syncLabel();
      const el = list.querySelector(".dd-opt.on");
      if (el) el.scrollIntoView({ block: "nearest" });
    } else if (e.key === "Enter") {
      e.preventDefault();
      pick(cur);
    }
  };
  document.addEventListener("click", (e) => {
    if (!list.hidden && !e.target.closest("#" + host.id)) close();
  });
  syncLabel();
  return {
    get value() { return cur; },
    // 外部同步显示用（不触发 onChange——同视图双向同步语义）
    setValue(v) { if (items.some((i) => i.v === v)) { cur = v; syncLabel(); } },
  };
}

export function setStatus(kind, text) {
  const el = $("status-pill");
  el.className = "pill " + kind;
  el.textContent = text;
}

export function esc(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

// ── C 语法高亮（F-1b①）───────────────────────────────────
// 页面侧独立小型着色器：零第三方依赖，与引擎 lexer 无契约绑定（呈现层
// 自治，F-2a SVG 包接管渲染时本逻辑随 JS 侧一起迁走，CSS transition 原样保留）。
// 形态（修订版）：textarea 前景透明只留光标 + 背后逐行行盒高亮层；软换行
// 自动折行（无横向滚动）+ 编辑器高度随内容伸缩（滚动收口在外层 .editor-wrap，
// 两层恒等宽保证折行断点一致——textarea 自身不滚，滚动条不会挤压文本区）。

// 含数组声明的用例判定（「· 数组动画」标注——时间旅行对这类用例出柱状图；
// 声明形态正则：`int a[8]` 命中、下标访问 `a[0]` 不误标；自 app.js boot
// 内联抽出成纯函数供 node --test 锚定）。
export function isArrayAnimCase(source) {
  return /(?:int|char|long|short|unsigned|float|double)\s*(?:\*+\s*)?\w+\s*\[\s*\d+\s*\]/.test(source);
}
