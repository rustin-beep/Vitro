// Vitro demo · 课程档案树（2026-10-04，refs #28 课程式重构批：仿 heron
// 学习档案形态——用户拍板「两个内容入口归一」）。左栏单一树承载全部内容：
//   第〇章 基础与白箱演示（cases.js 12 用例）+ 七个算法章（43 族+变体）
//   + 扩展练习章（35 未标注模板）。章 = 可折叠 + chip 一色 + 计数徽章；
//   课 = ring 状态环（localStorage 打勾——#28 待办「完成打勾项」兑现）；
//   搜索 = 标题/描述过滤。原「算法」tab 撤销（tab 5→4）。
// 数据全部机判产物（cases.js + algorithms.js 生成器），本模块零硬编码内容。
// 引擎边界在案：is_prime/threaded_binary_tree 两族无帧标注（issue #34）。
"use strict";

import { $, esc } from "./util.ts";
import { renderEditorDecor } from "./editor.ts";
import { collectCurrentEditor } from "./timetravel.ts";
import { setCurrentCase } from "./state.ts";

const DONE_KEY = "vitro-course-done";

interface TreeLesson {
  id: string;          // 唯一键（用例 id / 族 id / 模板名）
  title: string;
  blurb: string;
  kind: "case" | "algo" | "variant" | "xlab";
  famId?: string;      // variant 所属族（缩进渲染用）
  source: string;      // 载入编辑器的源码
  autoCollect: boolean; // 用例=false（走 selectCase 原语义）；算法/扩展=true
}
interface TreeChapter {
  id: string;
  label: string;
  chip: number; // chip 色序（tokens.css --chip-1..5）
  lessons: TreeLesson[];
}

function loadDone(): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(DONE_KEY) || "[]") as string[]);
  } catch {
    return new Set();
  }
}
function saveDone(s: Set<string>): void {
  localStorage.setItem(DONE_KEY, JSON.stringify([...s]));
}

// 组装章节（数据 = DEMO_CASES + DEMO_ALGORITHMS 机判产物）
function buildChapters(): TreeChapter[] {
  const chapters: TreeChapter[] = [];
  // 第〇章：基础与白箱演示（用例 = 基础课）
  chapters.push({
    id: "basic",
    label: "基础与白箱演示",
    chip: 1,
    lessons: DEMO_CASES.map((k) => ({
      id: k.id, title: k.label, blurb: k.blurb || "",
      kind: "case" as const, source: k.source, autoCollect: false,
    })),
  });
  // 七算法章（族 = 课；变体 = 族内子项）
  const chipSeq = [2, 3, 4, 5, 1, 2, 3];
  let ci = 0;
  for (const g of DEMO_ALGORITHMS.groups || []) {
    if (g.xitems) continue;
    const lessons: TreeLesson[] = [];
    for (const it of g.items || []) {
      lessons.push({
        id: it.id, title: it.name, blurb: it.id,
        kind: "algo", source: it.source, autoCollect: true,
      });
      for (const v of it.variants || []) {
        lessons.push({
          id: v.tpl, title: v.tpl, blurb: `${it.name} · 变体`,
          kind: "variant", famId: it.id, source: v.source, autoCollect: true,
        });
      }
    }
    chapters.push({ id: g.id, label: g.label, chip: chipSeq[ci++ % chipSeq.length], lessons });
  }
  // 扩展练习章
  const xg = (DEMO_ALGORITHMS.groups || []).find((g) => g.xitems);
  if (xg && xg.xitems) {
    chapters.push({
      id: "xlab",
      label: "扩展练习",
      chip: 4,
      lessons: xg.xitems.map((x) => ({
        id: x.id, title: prettify(x.id), blurb: "未标注族——可运行回放，算法标注随引擎迁移面",
        kind: "xlab" as const, source: x.source, autoCollect: true,
      })),
    });
  }
  return chapters;
}

function prettify(id: string): string {
  return id
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/** 用例课的选中回调（app 注入——走原 selectCase 语义：编辑器/blurb/configHint） */
let onCasePick: (id: string) => void = () => {};
export function bindCasePicker(fn: (id: string) => void): void { onCasePick = fn; }

export function renderCourseTree(): void {
  const chapters = buildChapters();
  const done = loadDone();
  const tree = $("course-tree");
  tree.innerHTML = chapters
    .map((ch, i) => {
      const doneN = ch.lessons.filter((l) => done.has(lessonKey(l))).length;
      return (
        `<div class="crs-group${i === 0 ? "" : " closed"}" data-ch="${esc(ch.id)}">` +
        `<button class="crs-chap crs-chip${ch.chip}">` +
        `<i class="crs-cchip"></i>${esc(ch.label)}` +
        `<span class="crs-badge">${doneN > 0 ? doneN + " / " : ""}${ch.lessons.length}</span>` +
        `<svg class="crs-chev" viewBox="0 0 16 16"><path d="M4.4 6.4 8 10l3.6-3.6" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>` +
        `</button>` +
        `<div class="crs-lessons">` +
        ch.lessons
          .map((l) => {
            const key = lessonKey(l);
            const isVar = l.kind === "variant";
            return (
              `<div class="crs-lesson${done.has(key) ? " done" : ""}${isVar ? " sub" : ""}" data-key="${esc(key)}" data-kind="${l.kind}" data-id="${esc(l.id)}" data-blurb="${esc(l.blurb)}"${l.famId ? ` data-fam="${esc(l.famId)}"` : ""}>` +
              `<span class="crs-ring"></span><span class="crs-ltitle">${esc(isVar ? prettify(l.title) : l.title)}</span>` +
              `</div>`
            );
          })
          .join("") +
        `</div></div>`
      );
    })
    .join("");
  // 章折叠
  tree.querySelectorAll<HTMLElement>(".crs-chap").forEach((btn) => {
    btn.onclick = () => btn.parentElement!.classList.toggle("closed");
  });
  // 课点击：路由两条路径 + 打勾
  tree.querySelectorAll<HTMLElement>(".crs-lesson").forEach((el) => {
    el.onclick = () => {
      const key = el.dataset.key || "";
      const ch = chapters.find((c) => c.lessons.some((l) => lessonKey(l) === key));
      const lesson = ch && ch.lessons.find((l) => lessonKey(l) === key);
      if (!lesson) return;
      if (lesson.kind === "case") {
        onCasePick(lesson.id);
      } else {
        loadAlgoLesson(lesson);
      }
      const s = loadDone();
      s.add(key);
      saveDone(s);
      markDoneRow(tree, key);
      if (ch) updateBadge(tree, ch);
    };
  });
  // 搜索过滤（标题/blurb 含关键词；无中课的章收起）
  const search = $("course-search") as HTMLInputElement;
  search.oninput = () => {
    const q = search.value.trim().toLowerCase();
    tree.querySelectorAll<HTMLElement>(".crs-group").forEach((grp) => {
      let visible = 0;
      grp.querySelectorAll<HTMLElement>(".crs-lesson").forEach((el) => {
        const t = (el.textContent || "").toLowerCase();
        const blurb = (el.getAttribute("data-blurb") || "").toLowerCase();
        const hit = !q || t.includes(q) || blurb.includes(q);
        el.style.display = hit ? "" : "none";
        if (hit) visible++;
      });
      grp.classList.toggle("closed", !!q && visible === 0);
      (grp.querySelector(".crs-chap") as HTMLElement).style.display = (q && visible === 0) ? "none" : "";
    });
  };
}

function lessonKey(l: TreeLesson): string {
  return l.kind === "variant" ? `${l.famId}:${l.id}` : l.id;
}
function markDoneRow(tree: HTMLElement, key: string): void {
  const row = tree.querySelector<HTMLElement>(`.crs-lesson[data-key="${CSS.escape(key)}"]`);
  if (row) row.classList.add("done");
}
function updateBadge(tree: HTMLElement, ch: TreeChapter): void {
  const grp = tree.querySelector<HTMLElement>(`.crs-group[data-ch="${ch.id}"]`);
  const badge = grp && grp.querySelector<HTMLElement>(".crs-badge");
  if (!badge) return;
  const done = loadDone();
  const n = ch.lessons.filter((l) => done.has(lessonKey(l))).length;
  badge.textContent = `${n > 0 ? n + " / " : ""}${ch.lessons.length}`;
}

// 算法/变体/扩展课载入：源码进编辑器（恒真源）→ 切运行视图 → 自动采集
function loadAlgoLesson(l: TreeLesson): void {
  setCurrentCase(""); // 非基础用例——configHint 语义不得沿用上个用例（run.ts 消费）
  const ta = $("editor") as HTMLTextAreaElement;
  ta.value = l.source;
  renderEditorDecor();
  const tabBtn = document.querySelector<HTMLElement>('.tabs .tab[data-tab="result"]');
  if (tabBtn) tabBtn.click();
  $("case-blurb").textContent = l.blurb;
  const phase = document.getElementById("anim-phase");
  if (phase) phase.textContent = `已载入：${l.kind === "variant" ? prettify(l.id) : l.title}（采集后回放）`;
  void collectCurrentEditor();
}
