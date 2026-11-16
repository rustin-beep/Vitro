// Vitro · 课程索引（2026-10-18 前端改造）——课程目录/面包屑/「继续上次」的
// 单一数据源。数据 = DEMO_CASES（第〇章基础课）+ DEMO_ALGORITHMS（算法章 +
// 扩展练习章），经虚拟模块 virtual:demo-globals 构建期合成（现役数据文件零改动）。
//
// 与旧 CourseTree.svelte 的差异：折叠/搜索本地态随组件迁入目录页；本模块只做
// 数据整形（纯函数、可 SSR、无响应式态），保证「课目与计数同一数据源」。
"use strict";

import type { DemoCase, AlgoGroup } from "virtual:demo-globals";
import { DEMO_CASES, DEMO_ALGORITHMS } from "virtual:demo-globals";
import { COURSE_BLURB } from "./courseBlurbs.ts";

export type LessonKind = "case" | "algo" | "variant" | "xlab";

export interface CourseLesson {
  id: string;
  title: string;
  blurb: string;
  kind: LessonKind;
  famId?: string;
  source: string;
  chapId: string;
  chapLabel: string;
  /** 章内第几课（1 起——工作态 kicker「课 03」同源）。 */
  ordinal: number;
  /** 全局课序号（1 起——目录计数用）。 */
  index: number;
}

export interface CourseChapter {
  id: string;
  label: string;
  lessons: CourseLesson[];
}

/** 课类标签（目录行右侧小签；case 课 = 有 Clang golden 预置真值的实跑课）。 */
export const KIND_LABELS: Record<LessonKind, string> = {
  case: "实跑",
  algo: "算法",
  variant: "变体",
  xlab: "练习",
};

/** 一句话说明兜底：课程数据里的 blurb 仍是 id 或「族名 · 变体」这类**占位**时，
 *  改取 COURSE_BLURB["<chap>/<id>"]；已有真实说明（case 课的 blurb 字段）
 *  一律不覆盖。键缺失时回落原占位文案——不白屏、不改既有行为。 */
function blurbOf(chapId: string, id: string, raw: string): string {
  const placeholder = !raw || raw === id || raw.endsWith("变体");
  return placeholder ? (COURSE_BLURB[chapId + "/" + id] ?? raw) : raw;
}

function buildChapters(): CourseChapter[] {
  const out: CourseChapter[] = [];
  let n = 0;
  const push = (id: string, label: string, lessons: Omit<CourseLesson, "chapId" | "chapLabel" | "ordinal" | "index">[]): void => {
    out.push({
      id,
      label,
      lessons: lessons.map((l, i) => ({ ...l, chapId: id, chapLabel: label, ordinal: i + 1, index: ++n })),
    });
  };

  // 第〇章：基础与白箱演示（用例 = 基础课）
  push(
    "basic",
    "基础与白箱演示",
    DEMO_CASES.map((k: DemoCase) => ({
      id: k.id,
      title: k.label,
      blurb: blurbOf("basic", k.id, k.blurb ?? ""),
      kind: "case" as const,
      source: k.source,
    })),
  );

  // 算法章（族 = 课；变体 = 族内子项）
  const groups = (DEMO_ALGORITHMS.groups ?? []).filter((g: AlgoGroup) => g.id !== "xlab");
  for (const g of groups) {
    const lessons: Omit<CourseLesson, "chapId" | "chapLabel" | "ordinal" | "index">[] = [];
    for (const it of g.items ?? []) {
      lessons.push({ id: it.id, title: it.name, blurb: blurbOf(g.id, it.id, it.id), kind: "algo", source: it.source });
      for (const v of it.variants ?? []) {
        lessons.push({ id: v.tpl, title: v.tpl, blurb: blurbOf(g.id, v.tpl, `${it.name} · 变体`), kind: "variant", famId: it.id, source: v.source });
      }
    }
    push(g.id, g.label, lessons);
  }

  // 扩展练习章
  const xg = (DEMO_ALGORITHMS.groups ?? []).find((g: AlgoGroup) => g.id === "xlab");
  if (xg) {
    push(
      "xlab",
      xg.label,
      (xg.xitems ?? []).map((x) => ({ id: x.id, title: x.name, blurb: blurbOf("xlab", x.id, x.id), kind: "xlab" as const, source: x.source })),
    );
  }
  return out;
}

export const CHAPTERS: CourseChapter[] = buildChapters();
export const LESSON_COUNT: number = CHAPTERS.reduce((s, c) => s + c.lessons.length, 0);

/** 按 id 查课（同 id 跨章重名可能——优先 chapId 命中）。 */
export function findLesson(id: string, chapId = ""): { lesson: CourseLesson; chapter: CourseChapter } | null {
  if (chapId) {
    const ch = CHAPTERS.find((c) => c.id === chapId);
    const l = ch?.lessons.find((x) => x.id === id);
    if (ch && l) return { lesson: l, chapter: ch };
  }
  for (const c of CHAPTERS) {
    const l = c.lessons.find((x) => x.id === id);
    if (l) return { lesson: l, chapter: c };
  }
  return null;
}

/** 叙述懒加载键（course/<chap>/<id>/lesson.md —— lessonNotes.ts 消费）。
 *  变体课按族目录取（真源只落在族课目录）。 */
export function noteKeyOf(l: CourseLesson): string {
  return l.chapId + "/" + l.id;
}

/** 首访默认课：bubble（设计稿首访动线「一眼看到代码 + 数组 + 时间轴」）；
 *  缺省回落第〇章第一课。 */
export function defaultLesson(): { lesson: CourseLesson; chapter: CourseChapter } | null {
  return findLesson("bubble", "basic") ?? (CHAPTERS[0]?.lessons[0] ? { lesson: CHAPTERS[0].lessons[0], chapter: CHAPTERS[0] } : null);
}
