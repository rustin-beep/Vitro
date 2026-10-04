// Vitro demo · 编辑器（词法高亮）（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。）
"use strict";

import { $, esc } from "./util.js";

export const C_KEYWORDS = new Set(
  (
    "auto break case char const continue default do double else enum extern " +
    "float for goto if inline int long register restrict return short signed " +
    "sizeof static struct switch typedef union unsigned void volatile while " +
    "_Bool _Complex _Imaginary bool true false nullptr"
  ).split(" ")
);
// 组合正则按优先级一次扫描：块注释/行注释/字符串/字符/预处理行/数字/标识符。
// 未闭合的注释与字符串也吞到末尾（打字中间态高亮稳定）；预处理行匹配
// ^\s*#（m 标志），因注释/字符串组在前，处于它们内部的 # 不会被误判。
export const C_TOKEN =
  /(\/\*[\s\S]*?(?:\*\/|$))|(\/\/[^\n]*)|("(?:\\.|[^"\\\n])*"?)|('(?:\\.|[^'\\\n])*'?)|(^[ \t]*#[^\n]*)|(\.?\d(?:[\w.]|[eEpP][+-])*)|([A-Za-z_]\w*)/gm;

export function tokenizeC(src) {
  const toks = [];
  let last = 0;
  let m;
  C_TOKEN.lastIndex = 0;
  while ((m = C_TOKEN.exec(src))) {
    if (m.index > last) toks.push({ cls: "", text: src.slice(last, m.index) });
    const cls = m[1] || m[2] ? "syn-com"
      : m[3] || m[4] ? "syn-str"
      : m[5] ? "syn-pre"
      : m[6] ? "syn-num"
      : C_KEYWORDS.has(m[7]) ? "syn-key"
      : "";
    toks.push({ cls, text: m[0] });
    last = m.index + m[0].length;
    if (m[0].length === 0) C_TOKEN.lastIndex += 1; // 防零宽匹配死循环
  }
  if (last < src.length) toks.push({ cls: "", text: src.slice(last) });
  return toks;
}

// 整体 tokenize 后按 \n 切分组装行盒（块注释等跨行 token 的着色状态
// 在行间延续）；每行一个 .cl，行号 .ln 内嵌行盒，折行后行号不重复。
export function highlightLines(src) {
  const rows = [];
  let cur = "";
  const feed = (cls, text) => {
    const parts = text.split("\n");
    for (let i = 0; i < parts.length; i++) {
      if (i > 0) {
        rows.push(cur);
        cur = "";
      }
      if (parts[i]) cur += cls ? `<span class="${cls}">${esc(parts[i])}</span>` : esc(parts[i]);
    }
  };
  for (const t of tokenizeC(src)) feed(t.cls, t.text);
  rows.push(cur);
  return rows
    .map((html, i) => `<div class="cl"><span class="ln">${i + 1}</span><span class="lc">${html || "\u200b"}</span></div>`)
    .join("");
}

// input 同步渲染（不走 rAF）：textarea 高度即时跟随内容，消除打字回车
// 瞬间 textarea 内部出现溢出的时序差。
export function renderEditorDecor() {
  const ta = $("editor");
  if (!ta) return;
  $("editor-hl").innerHTML = highlightLines(ta.value);
}

export function initEditorDecor() {
  const ta = $("editor");
  ta.addEventListener("input", renderEditorDecor);
  renderEditorDecor();
}

// ── 行跳转（F-1 视觉件）+ 高亮闪烁定位（F-1b②动效）──────────
export function scrollToLine(line, flash = true) {
  line = Number(line);
  if (!line || line < 1) return;
  const wrapEl = $("editor-wrap");
  const row = wrapEl.querySelectorAll("#editor-hl .cl")[line - 1];
  if (!row) return;
  // 目标行滚到编辑器视口中部（offsetTop 相对 .editor-lay，即内容坐标）
  wrapEl.scrollTop = Math.max(0, row.offsetTop - wrapEl.clientHeight / 2);
  const hlEl = $("editor-hl");
  hlEl.querySelectorAll(".flash-on").forEach((el) => el.classList.remove("flash-on"));
  hlEl.querySelectorAll(".cl.cur").forEach((el) => el.classList.remove("cur"));
  row.classList.add("cur");
  if (!flash) return; // 时间旅行播放中：只滚+描边当前行，不闪
  void hlEl.offsetWidth; // 重触发闪烁动画
  row.classList.add("flash-on");
  const onEnd = () => {
    row.classList.remove("flash-on");
    row.removeEventListener("animationend", onEnd);
  };
  row.addEventListener("animationend", onEnd);
}

// ── tab 切换 ─────────────────────────────────────────────
