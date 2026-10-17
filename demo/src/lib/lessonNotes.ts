// 课程叙述索引（交付格式：import.meta.glob ?url 懒加载——2026-10-16 #122
// 裁定三小件③落地）。course/*.md 真源由打包器逐文件发射（哈希名资产），
// 运行时按需 fetch + 解析——课程从试点 2 课铺到全量 110 课时，不再把全部
// md 文本压进首屏包（此前 2 课 ?raw 内联是试点形态，全量即爆）。
// 消费键 = "<chap>/<id>"（frontmatter id 章内唯一，跨章可能重名故带 chap）。
//
// 与 E-08 闸的分工（同真源两形态）：E-08 SSR 入口直读 ?raw 内联做快照锚
// （node 侧无 fetch 面）；本文件是运行时消费形态。改课程真源两边同源联动。
"use strict";

import { parseLessonMd, type LessonDoc } from "./lessonMd.ts";

// glob key = 相对本文件的路径（../../../course/<chap>/<id>/lesson.md）；
// ?url + import:"default" + eager:false = 每文件一个 URL 资产 + 懒加载器。
const mdLoaders = import.meta.glob<() => Promise<string>>("../../../course/**/lesson.md", {
  query: "?url",
  import: "default",
  eager: false,
});

/** glob key → 消费键 "<chap>/<id>"（剥 course/ 前缀与 /lesson.md 尾段；
 *  不匹配的 key 跳过——glob 面只收 lesson.md，防御性兜底）。 */
function keyOf(globKey: string): string {
  const m = globKey.match(/^(?:\.\.\/)+course\/(.+)\/lesson\.md$/);
  return m ? m[1] : "";
}

const notes = new Map<string, () => Promise<string>>();
for (const [k, load] of Object.entries(mdLoaders)) {
  const key = keyOf(k);
  if (key) notes.set(key, load);
}

/** 按消费键懒加载叙述。无此课 = null（诚实空态——调用方不渲染叙述面板）；
 *  加载/解析失败 = null + 控制台 fail loud（宽容于用户、不阻塞选课——
 *  与原 ?raw 试点形态的 doc() 兜底同语义）。 */
export async function loadLessonNote(key: string): Promise<LessonDoc | null> {
  const load = notes.get(key);
  if (!load) return null;
  try {
    const url = await load();
    const src = await (await fetch(url)).text();
    return parseLessonMd(src);
  } catch (err) {
    console.error(`[lessonNotes] ${key} 加载或解析失败:`, err);
    return null;
  }
}

/** 已登记叙述键集合（调试/对账面——E2E 与 dev 断言 glob 收录用）。 */
export function lessonNoteKeys(): string[] {
  return [...notes.keys()].sort();
}
