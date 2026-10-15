// 课程树共享类型（CourseTree / App 共用；数据形态对齐现役 course.ts TreeLesson）
"use strict";

export interface TreeLesson {
  id: string;
  title: string;
  blurb: string;
  kind: "case" | "algo" | "variant" | "xlab";
  famId?: string;
  source: string;
}

export interface TreeChapter {
  id: string;
  label: string;
  lessons: TreeLesson[];
}
