// Vitro demo · 页面工具（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。TS 重写批：签名类型化。）
"use strict";

export const MEM_TOTAL = 1024 * 1024; // 1MB 内存映射（引擎口径）

// 中文等 UTF-8 多字节序列在此形态下是 mojibake——按字节还原为文本。
export const latin1ToUtf8 = (delta: string | null | undefined): string => {
  if (!delta) return "";
  const bytes = new Uint8Array(delta.length);
  for (let i = 0; i < delta.length; i++) bytes[i] = delta.charCodeAt(i) & 0xff;
  return new TextDecoder("utf-8").decode(bytes);
};

// ── 页面骨架 ──────────────────────────────────────────────
/** 按 id 取元素——index.html 静态契约下不存在即抛（boot 期炸好过 undefined 传播）。
 *  泛型：调用点按已知元素类型断言，如 `<HTMLInputElement>$("editor")`。 */
export function $<T extends HTMLElement = HTMLElement>(id: string): T {
  const el = document.getElementById(id);
  if (!el) throw new Error(`#${id} 不存在（index.html 契约破坏）`);
  return el as T;
}

/** 含数组声明的用例判定（「· 数组动画」标注——时间旅行对这类用例出柱状图；
 *  声明形态正则：`int a[8]` 命中、下标访问 `a[0]` 不误标；紧凑/指针形态
 *  `int*p[4]`/`int** m[2]` 同命中——存量 bug 修复锁见 pure.test.mts）。 */
export function isArrayAnimCase(source: string): boolean {
  return /(?:int|char|long|short|unsigned|float|double)\s*(?:\*+\s*)?\w+\s*\[\s*\d+\s*\]/.test(source);
}

export interface DropdownItem {
  v: string;
  label: string;
}

/** 自绘下拉实例（value getter + setValue 双向同步口）。 */
export interface Dropdown {
  readonly value: string;
  /** 外部同步显示用（不触发 onChange——同视图双向同步语义） */
  setValue(v: string): void;
}

// 自绘下拉：闭合态按钮 + 浮层 listbox；键盘（Enter/Space 开、↑↓ 浏览、
// Enter 确认、Esc 撤回）、点击外部关闭、aria 展开态。
export function makeDropdown(
  hostId: string,
  items: DropdownItem[],
  value: string,
  onChange?: (v: string) => void,
): Dropdown {
  const host = $(hostId);
  host.innerHTML =
    '<button type="button" class="dd-btn" aria-haspopup="listbox" aria-expanded="false">' +
    '<span class="dd-label"></span>' +
    '<svg class="dd-chev" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>' +
    '</button><div class="dd-list" role="listbox" hidden></div>';
  const btn = host.querySelector(".dd-btn") as HTMLElement;
  const label = host.querySelector(".dd-label") as HTMLElement;
  const list = host.querySelector(".dd-list") as HTMLElement;
  let cur = value;
  let committed = value;
  const idxOf = (): number => items.findIndex((i) => i.v === cur);
  function syncLabel(): void {
    const it = items[idxOf()];
    label.textContent = it ? it.label : "";
  }
  function renderList(): void {
    list.innerHTML = items
      .map((i) =>
        `<button type="button" class="dd-opt${i.v === cur ? " on" : ""}" role="option" aria-selected="${i.v === cur}" data-v="${esc(String(i.v))}">${esc(i.label)}</button>`
      )
      .join("");
  }
  function open(): void {
    committed = cur;
    renderList();
    list.hidden = false;
    host.setAttribute("data-open", "");
    btn.setAttribute("aria-expanded", "true");
    const el = list.querySelector(".dd-opt.on");
    if (el) el.scrollIntoView({ block: "nearest" });
  }
  function close(): void {
    list.hidden = true;
    host.removeAttribute("data-open");
    btn.setAttribute("aria-expanded", "false");
  }
  function pick(v: string): void {
    cur = v;
    syncLabel();
    close();
    if (onChange) onChange(v);
  }
  btn.onclick = () => (list.hidden ? open() : close());
  list.onclick = (e: MouseEvent) => {
    const opt = (e.target as HTMLElement).closest<HTMLElement>(".dd-opt");
    if (opt) pick(opt.dataset.v as string);
  };
  btn.onkeydown = (e: KeyboardEvent) => {
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
  document.addEventListener("click", (e: MouseEvent) => {
    if (!list.hidden && !(e.target as HTMLElement).closest("#" + host.id)) close();
  });
  syncLabel();
  return {
    get value() { return cur; },
    // 外部同步显示用（不触发 onChange——同视图双向同步语义）
    setValue(v: string) { if (items.some((i) => i.v === v)) { cur = v; syncLabel(); } },
  };
}

export function setStatus(kind: string, text: string): void {
  const el = $("status-pill");
  el.className = "pill " + kind;
  el.textContent = text;
}

export function esc(s: string): string {
  return String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] as string));
}
