// Vitro demo · 设置与主题（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。）
"use strict";

import { $ } from "./util.ts";

function storeGet(key: string): string | null { try { return localStorage.getItem(key); } catch { return null; } }
function storeSet(key: string, val: string): void { try { localStorage.setItem(key, val); } catch { /* 存储不可用时静默（隐私模式） */ } }

const THEMES: readonly string[] = ["ice", "rose", "paper", "glass", "soft"];
const NIGHT_THEMES: ReadonlySet<string> = new Set(["glass", "soft"]);

function syncSeg(segId: string, v: string): void {
  const seg = $(segId);
  if (!seg) return;
  for (const b of seg.querySelectorAll("button")) b.classList.toggle("on", b.dataset.v === v);
}

function setTheme(v: string): void {
  document.documentElement.setAttribute("data-theme", v);
  document.documentElement.setAttribute("data-shade", NIGHT_THEMES.has(v) ? "night" : "day");
  storeSet("vitro-theme", v);
  syncSeg("set-theme", v);
}

function applyEdFont(px: string): void {
  // 编辑器对齐契约：hl 与 textarea 两层的 font 都引用 --ed-fs，改一处即同步
  document.documentElement.style.setProperty("--ed-fs", px);
  syncSeg("set-font", px);
}

function applyMotion(v: string): void {
  if (v === "off") document.documentElement.setAttribute("data-motion", "off");
  else document.documentElement.removeAttribute("data-motion");
  syncSeg("set-motion", v);
}

export function initSettings() {
  let saved: string = storeGet("vitro-theme") ?? "";
  if (saved === "light") saved = "ice"; // 旧双值迁移
  else if (!saved || saved === "dark") saved = "glass";
  if (!THEMES.includes(saved)) saved = "glass";
  setTheme(saved);
  const savedFont = storeGet("vitro-ed-font");
  applyEdFont(savedFont === "12px" || savedFont === "15px" ? savedFont : "13px");
  applyMotion(storeGet("vitro-motion") === "off" ? "off" : "on");

  const themeBtn = $("theme-toggle");
  if (themeBtn) {
    themeBtn.onclick = () => {
      const cur = document.documentElement.getAttribute("data-theme") ?? "";
      setTheme(NIGHT_THEMES.has(cur) ? "ice" : "glass");
    };
  }
  const segBind = (segId: string, apply: (v: string | undefined) => void): void => {
    $(segId).addEventListener("click", (e) => {
      const b = (e.target as HTMLElement).closest("button");
      if (b) apply(b.dataset.v);
    });
  };
  segBind("set-theme", setTheme);
  segBind("set-font", (px) => { if (px) { applyEdFont(px); storeSet("vitro-ed-font", px); } });
  segBind("set-motion", (v) => { applyMotion(v); storeSet("vitro-motion", v); });

  // 面板开关：齿轮 toggle / 点击面板外关闭 / ESC 关闭
  const panel = $("settings-panel");
  const toggle = $("settings-toggle");
  const setOpen = (open: boolean): void => {
    panel.classList.toggle("hidden", !open);
    toggle.setAttribute("aria-expanded", String(open));
  };
  toggle.addEventListener("click", () => setOpen(panel.classList.contains("hidden")));
  document.addEventListener("click", (e: MouseEvent) => {
    if (!panel.classList.contains("hidden") && !(e.target as HTMLElement).closest(".settings-wrap")) setOpen(false);
  });
  document.addEventListener("keydown", (e: KeyboardEvent) => {
    if (e.key === "Escape" && !panel.classList.contains("hidden")) setOpen(false);
  });
}

// 【拆分批注】原为 IIFE 自调（app.js:1276）；ESM 化后由入口 boot 显式调用
//（node --test import 本模块时顶层不再触 DOM）。
