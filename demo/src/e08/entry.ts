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
import bubbleC from "../../e08/bubble.c?raw";
import type { Diagnostic, MemoryRegions, StepPayload } from "../../js/types.ts";
import type { CatalogCard } from "../session.svelte.ts";

// 课程真源（?raw 内联——E-08 是 node 侧 SSR 闸，无 fetch 面）
const BUBBLE: LessonDoc = parseLessonMd(bubbleMd);
const BUBBLE_SORT: LessonDoc = parseLessonMd(bubbleSortMd);

// 数组格快照的源码面（frame.code_line 定位当前行）——真源 = demo/e08/bubble.c
// （#324 治本：与 core.json frames 段同一引擎输入，行号自洽；文件带
// editorconfig 尾换行，此处对称剥离——golden 尾换行同款口径）
const SOURCE_SAMPLE = bubbleC.replace(/\n$/, "");

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
  // 粒度显式钉指令级（#324 治本）：frameAt/idx 语义 = payload.frames 的
  // 原始下标一一对应——缺省 gran 是持久化态（浏览器 localStorage / node
  // 侧 initGran 兜底），不钉则 idx 锚随粒度派生（语句级组尾帧）漂移。
  session.gran = "insn";
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

function snapAt(frameIdx: number, nameIdx: number): NonNullable<NonNullable<ReturnType<typeof frameAt>>["array_snapshots"]>[number] {
  const snap = frameAt(frameIdx)?.array_snapshots?.[nameIdx];
  if (snap === undefined) throw new Error(`e08 fixture: 帧 ${frameIdx} 缺数组快照 ${nameIdx}`);
  return snap;
}

// 帧定位（#324 治本批）：实产帧流下标不硬编码——按 algorithm_step.phase
// 语义定位（首个命中），payload 重导后锚点自愈（旧稿硬编码「第 3 帧」在
// 实产 1041 帧流上指向 main 入口期，锚点语义已失效）。
function firstFrameIdx(phase: string): number {
  const i = session.frames.findIndex(
    (f) => (f?.algorithm_step as { phase?: string } | undefined)?.phase === phase,
  );
  if (i === -1) throw new Error(`e08 fixture: 实产帧流无 phase==="${phase}" 帧——payload 与 bubble.c 失配`);
  return i;
}

/** 末个带数组快照的帧（终态数组视图——finish/return 帧常无快照，语句
 * 中间帧清标注语义见 serve_step；从尾向前找首个有快照帧）。 */
function lastSnapshotFrameIdx(): number {
  for (let i = session.frames.length - 1; i >= 0; i -= 1) {
    const f = session.frames[i];
    if (f && (f.array_snapshots?.length ?? 0) > 0) return i;
  }
  throw new Error("e08 fixture: 实产帧流无任何数组快照帧——payload 与 bubble.c 失配");
}

const CASES: Record<string, (p: CorePayload) => string> = {
  "varslist-multi": () => render(VarsList).body,
  "timeline-mid": () => render(Timeline, { props: { source: SOURCE_SAMPLE } }).body,
  // 交换瞬间：session.idx（导出器缺省 = 首个 phase==="swap" 帧——交换
  // 中间的数组格快照；单数组 a——实产 bubble.c 只有一个数组快照位）。
  "arraycells-bubble-a": () =>
    render(ArrayCells, {
      props: {
        snap: snapAt(session.idx, 0),
        frame: frameAt(session.idx),
        before: session.idx > 0 ? frameAt(session.idx - 1) : undefined,
        source: SOURCE_SAMPLE,
      },
    }).body,
  // 终态就位：末个带快照帧（排序完成后的数组升序终值——对照 bubble-a
  // 的交换中间态；finish/return 帧无数组快照故不取物理末帧）。
  "arraycells-bubble-b": () => {
    const last = lastSnapshotFrameIdx();
    return render(ArrayCells, {
      props: {
        snap: snapAt(last, 0),
        frame: frameAt(last),
        before: last > 0 ? frameAt(last - 1) : undefined,
        source: SOURCE_SAMPLE,
      },
    }).body;
  },
  // 当前比较的自动指认：首个 phase==="compare" 帧（比较行上的两个格亮
  // current；props 显式取帧，不依赖 session.idx）。
  "arraycells-focus": () => {
    const i = firstFrameIdx("compare");
    return render(ArrayCells, {
      props: {
        snap: snapAt(i, 0),
        frame: frameAt(i),
        before: i > 0 ? frameAt(i - 1) : undefined,
        source: SOURCE_SAMPLE,
      },
    }).body;
  },
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
