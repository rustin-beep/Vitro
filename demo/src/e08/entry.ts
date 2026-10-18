// E-08 快照闸 · SSR 渲染入口（#122 闸门批；2026-10-18 前端改造批换面）。
//
// 形态不变：vite build --ssr 把本入口编译为 node 可 import 的 ESM bundle
// （dist-e08/ 不入库）；demo/tests/e08.test.mts 读冻结 payload 与 golden HTML
// 逐字节比对；e08-update.mts 是唯一显式重建通道（人工令，E-04 纪律）。
//
// 覆盖面边界（诚实登记）：本闸收「session/props 数据 → DOM 语义面」
// （标签/class/属性/文本，归一化剥 HTML 注释与空白）；**不覆盖** 动画指令
// （flip/fade）、事件 handler、浏览器态（CM6 编辑器视图 / 调用树 rAF 相机 /
// 课程目录交互 / bind 之后的用户输入态）——这些维持浏览器实测纪律。
// CallTree 的画布需要 clientWidth 量测（SSR 无布局），故不入快照面。
//
// 课程叙述真源链：payload 手写 lesson 段退役——coursenote 用例直读
// course/*.md 真源（?raw 内联经 parseLessonMd 解析），golden 锚
// 「课程真源 → 解析 → 渲染 HTML」全链。
// **块型覆盖矩阵**（lessonMd 七块型 × 两课试点真源）：
//   h2 / p / ol / code ← coursenote-blocks（course/basic/bubble/lesson.md）
//   ul / table          ← coursenote-sorting（course/sorting/bubble_sort）
//   h3                  ← coursenote-h3 冻结样本块（真源缺口——两试点课均无 ###）
"use strict";

import { render } from "svelte/server";
import ArrayCells from "../lib/ArrayCells.svelte";
import CourseNote from "../lib/CourseNote.svelte";
import DiagBand from "../lib/DiagBand.svelte";
import MemoryView from "../lib/MemoryView.svelte";
import OutputView from "../lib/OutputView.svelte";
import ProtoView from "../lib/ProtoView.svelte";
import RefIndex from "../lib/RefIndex.svelte";
import Timeline from "../lib/Timeline.svelte";
import VarsList from "../lib/VarsList.svelte";
import { frameAt, session } from "../session.svelte.ts";
import { parseLessonMd, type Block, type LessonDoc } from "../lib/lessonMd.ts";
import { buildCallTree } from "../../js/calltree.ts";
import bubbleMd from "../../../course/basic/bubble/lesson.md?raw";
import bubbleSortMd from "../../../course/sorting/bubble_sort/lesson.md?raw";
import type { Diagnostic, MemoryRegions, StepPayload } from "../../js/types.ts";
import type { CatalogCard } from "../session.svelte.ts";

// 课程真源（?raw 内联——E-08 是 node 侧 SSR 闸，无 fetch 面）
const BUBBLE: LessonDoc = parseLessonMd(bubbleMd);
const BUBBLE_SORT: LessonDoc = parseLessonMd(bubbleSortMd);

// 数组格快照的源码面（frame.code_line 定位当前行；与 core.json 帧同一课）
const SOURCE_SAMPLE = [
  "#include <stdio.h>",
  "",
  "int main(void) {",
  "  int a[5] = {5, 3, 1, 4, 2};",
  "  int n = 5;",
  "  for (int i = 0; i < n - 1; i++) {",
  "    for (int j = 0; j < n - 1 - i; j++) {",
  "      if (a[j] > a[j + 1]) {",
  "        int t = a[j];",
  "        a[j] = a[j + 1];",
  "        a[j + 1] = t;",
  "      }",
  "    }",
  "  }",
  '  for (int k = 0; k < n; k++) printf("%d ", a[k]);',
  "  return 0;",
  "}",
].join("\n");

export interface CorePayload {
  frames?: StepPayload[];
  idx?: number;
  outputs?: { stdout: string; stderr: string; note: string };
  memory?: MemoryRegions;
  catalog?: CatalogCard[];
  capabilities?: Record<string, unknown>;
  labels?: string[];
  /** 编译期诊断面（diagband 用例专用）。 */
  diagnostics?: Diagnostic[];
  compileOk?: boolean;
  stopped?: string;
  runStats?: { status: string; return_value: number; steps_executed: number; waiting_input: boolean } | null;
  /** 用例锚（golden 徽章 / 数组「已就位」推断）。 */
  currentCase?: { id: string; label: string; source: string; referenceOutput?: string; referenceTrap?: string };
}

export interface CaseResult {
  html: string;
}

// 单例装载 + 全段清场——renderCase 之间互不串染
function loadPayload(p: CorePayload): void {
  session.frames = p.frames ?? [];
  session.idx = p.idx ?? 0;
  session.outputs = p.outputs ?? { stdout: "", stderr: "", note: "" };
  session.memory = p.memory ?? null;
  session.catalog = p.catalog ?? [];
  session.capabilities = p.capabilities ?? null;
  session.contracts = null;
  session.labels = p.labels ?? [];
  session.diagnostics = p.diagnostics ?? [];
  session.compileOk = p.compileOk ?? true;
  session.stopped = p.stopped ?? "";
  session.runStats = p.runStats ?? null;
  session.currentCase = p.currentCase ?? null;
  session.liveSource = p.currentCase?.source ?? "";
  session.tree = session.frames.length ? buildCallTree(session.frames) : null;
  session.playing = false;
  session.collecting = false;
  session.batching = false;
  session.status = "E-08 快照渲染";
}

// 归一化：剥全部 HTML 注释（Svelte hydration 锚）+ scoped-hash class +
// 空白折叠。样式一致性由 ui_lint/浏览器实测管，本闸锚 DOM 语义。
function normalize(html: string): string {
  return html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/\bsvelte-[a-z0-9]+\b/g, "")
    .replace(/class="\s*"/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

const CASES: Record<string, (p: CorePayload) => string> = {
  "varslist-multi": () => render(VarsList).body,
  "timeline-mid": () => render(Timeline, { props: { source: SOURCE_SAMPLE } }).body,
  "arraycells-bubble-a": () =>
    render(ArrayCells, {
      props: {
        snap: frameAt(session.idx)?.array_snapshots[0],
        frame: frameAt(session.idx),
        before: session.idx > 0 ? frameAt(session.idx - 1) : undefined,
        source: SOURCE_SAMPLE,
      },
    }).body,
  "arraycells-bubble-b": () =>
    render(ArrayCells, {
      props: {
        snap: frameAt(session.idx)?.array_snapshots[1],
        frame: frameAt(session.idx),
        before: session.idx > 0 ? frameAt(session.idx - 1) : undefined,
        source: SOURCE_SAMPLE,
      },
    }).body,
  // 当前比较的自动指认（本稿新增）：第 3 帧 line 8 `a[j] > a[j+1]`、j=2 →
  // a[2] / a[3] 两个格亮 current（props 显式取第 3 帧，不依赖 session.idx）。
  "arraycells-focus": () =>
    render(ArrayCells, {
      props: {
        snap: frameAt(2)?.array_snapshots[0],
        frame: frameAt(2),
        before: frameAt(1),
        source: SOURCE_SAMPLE,
      },
    }).body,
  "memoryview-mallocfree": () => render(MemoryView).body,
  "outputview-three": () => render(OutputView).body,
  "outputview-empty": () => render(OutputView).body,
  "diagband-ok": () => render(DiagBand).body,
  "diagband-compilefail": () => render(DiagBand).body,
  "diagband-trap": () => render(DiagBand).body,
  "refindex-diagnostics": () => render(RefIndex).body,
  "protoview-caps": () => render(ProtoView).body,
  "coursenote-blocks": () =>
    render(CourseNote, {
      props: { title: BUBBLE.meta.title ?? "", blocks: BUBBLE.blocks },
    }).body,
  "coursenote-sorting": () =>
    render(CourseNote, {
      props: { title: BUBBLE_SORT.meta.title ?? "", blocks: BUBBLE_SORT.blocks },
    }).body,
  "coursenote-h3": () =>
    render(CourseNote, {
      props: {
        title: BUBBLE.meta.title ?? "",
        blocks: [...BUBBLE.blocks, { type: "h3", text: "（冻结样本块）真源 h3 缺口占位——两试点课无 ### 标题" } as Block],
      },
    }).body,
};

export const CASE_NAMES: readonly string[] = Object.keys(CASES);

export function renderCase(name: string, payload: CorePayload): CaseResult {
  const fn = CASES[name];
  if (!fn) throw new Error(`E-08 未知用例: ${name}（用例表 ${CASE_NAMES.length} 条 = ${CASE_NAMES.join(", ")}）`);
  loadPayload(payload);
  return { html: normalize(fn(payload)) };
}
