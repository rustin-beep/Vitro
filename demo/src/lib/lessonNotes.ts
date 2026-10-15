// 课程叙述索引（试点形态：真源 md 经 vite ?raw 内联——零 fetch 零部署拷贝；
// 课程铺开后改 fetch + 构建期 manifest，形态演进不破消费接口）。
// 键 = "<chap>/<id>"（frontmatter id 在章内唯一，跨章可能重名故带 chap）。
"use strict";

import bubbleMd from "../../../course/basic/bubble/lesson.md?raw";
import bubbleSortMd from "../../../course/sorting/bubble_sort/lesson.md?raw";
import { parseLessonMd, type LessonDoc } from "./lessonMd.ts";

function doc(src: string, key: string): LessonDoc {
  try {
    return parseLessonMd(src);
  } catch (err) {
    // 叙述解析失败不阻塞选课——空文档 + 控制台可见（fail loud 于开发者、宽容于用户）
    console.error(`[lessonNotes] ${key} 解析失败:`, err);
    return { version: 1, meta: { id: key, kind: "", order: 0 }, blocks: [] };
  }
}

export const LESSON_NOTES: Record<string, LessonDoc> = {
  "basic/bubble": doc(bubbleMd, "basic/bubble"),
  "sorting/bubble_sort": doc(bubbleSortMd, "sorting/bubble_sort"),
};
