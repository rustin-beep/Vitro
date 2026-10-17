// E-08 快照闸 · SSR 渲染入口（#122 闸门批）——兑现《出口分档与宿主策略》
// §6.2 末条防线义务：「golden payload → 渲染输出」快照测试——**UI 重建启动
// 时立即生效**：框架迁移/组件重写后经本闸比对冻结 golden，渲染漂移即红。
// 形态：vite build --ssr 把本入口编译为 node 可 import 的 ESM bundle（产物
// dist-e08/ 不入库）；demo/tests/e08.test.mts 读冻结 payload 与 golden HTML
// 逐字节比对；demo/tests/e08-update.mts 是唯一显式重建通道（人工令，对齐
// protocol_frames --update-baseline 语义；E-04 纪律：快照不得在测试内由
// 当前实现动态生成）。
//
// 覆盖面边界（诚实登记）：本闸收「session/props 数据 → DOM 语义面」
// （标签/class/属性/文本，归一化剥 HTML 注释与空白——Svelte 每元素 hydration
// 锚注释跨版本漂移不属语义面）；动画指令（flip/fade）、事件 handler、浏览器态
// （Editor 的 CM6 视图 / CallTree 的 rAF 相机 / CourseTree 折叠交互 / bind
// 之后的用户输入态）不产生渲染语义差异，维持浏览器实测纪律。
//
// 课程叙述真源链（2026-10-16 #122 裁定三小件①「E-08 换真值」落地）：payload
// 手写 lesson 段退役——coursenote 用例改吃 course/*.md 真源（?raw 内联经
// parseLessonMd 解析），golden 锚「课程真源 → 解析 → 渲染 HTML」全链。
// **块型覆盖矩阵**（lessonMd 七块型 × 两课试点真源，golden 逐型锚定）：
//   h2 / p / ol / code ← coursenote-blocks（course/basic/bubble/lesson.md）
//   ul / table        ← coursenote-sorting（course/sorting/bubble_sort/lesson.md）
//   h3                ← coursenote-h3 冻结样本块（真源缺口——两试点课均无
//                       ### 标题；在全量课程铺开后复核是否可改吃真源）
"use strict";

import { render } from "svelte/server";
import ArrayBars from "../lib/ArrayBars.svelte";
import CatalogView from "../lib/CatalogView.svelte";
import CourseNote from "../lib/CourseNote.svelte";
import MemoryView from "../lib/MemoryView.svelte";
import OutputView from "../lib/OutputView.svelte";
import ProtoView from "../lib/ProtoView.svelte";
import ReplayBar from "../lib/ReplayBar.svelte";
import VarsList from "../lib/VarsList.svelte";
import { frameAt, session } from "../session.svelte.ts";
import { parseLessonMd, type Block, type LessonDoc } from "../lib/lessonMd.ts";
import bubbleMd from "../../../course/basic/bubble/lesson.md?raw";
import bubbleSortMd from "../../../course/sorting/bubble_sort/lesson.md?raw";
import type { MemoryRegions, StepPayload } from "../../js/types.ts";
import type { CatalogCard } from "../session.svelte.ts";

// 课程真源（?raw 内联——E-08 是 node 侧 SSR 闸，无 fetch 面，内联即真源直读；
// 运行时的懒加载交付格式另走 lessonNotes.ts 的 import.meta.glob ?url，两处
// 消费同一真源、形态各随场景）。
const BUBBLE: LessonDoc = parseLessonMd(bubbleMd);
const BUBBLE_SORT: LessonDoc = parseLessonMd(bubbleSortMd);

// core.json 冻结数据的读面文档——段结构对齐 wire DTO（js/types.ts），段缺省
// 走空兜底（loadPayload 清场保证用例间零串染）。
// 注：lesson 段已退役（2026-10-16 换真值）——coursenote 用例直读 course/*.md
// 真源，不再经 payload 手写块。
export interface CorePayload {
  frames?: StepPayload[];
  idx?: number;
  outputs?: { stdout: string; stderr: string; note: string };
  memory?: MemoryRegions;
  catalog?: CatalogCard[];
  capabilities?: Record<string, unknown>;
  labels?: string[];
}

export interface CaseResult {
  html: string;
}

// 单例装载 + 全段清场——renderCase 之间互不串染（catalog 残留污染下一用例
// 的渲染即串染形态，显式全量重置而非常量差量修补）。
function loadPayload(p: CorePayload): void {
  session.frames = p.frames ?? [];
  session.idx = p.idx ?? 0;
  session.outputs = p.outputs ?? { stdout: "", stderr: "", note: "" };
  session.memory = p.memory ?? null;
  session.catalog = p.catalog ?? [];
  session.capabilities = p.capabilities ?? null;
  session.contracts = null;
  session.labels = p.labels ?? [];
  session.playing = false;
  session.collecting = false;
  session.batching = false;
  session.stopped = "";
  session.status = "E-08 快照渲染";
}

// 归一化：剥全部 HTML 注释（Svelte hydration 锚 `<!--[-->`/`<!--n-->` 的
// 字面形态随编译器版本漂移，不属 DOM 语义面）+ scoped-hash class（
// `svelte-xxxx` 由编译器按组件内容 hash 派生，样式微调即变——快照锚的是
// DOM 语义与业务 class，样式一致性由 ui_lint/浏览器实测管）+ 空白折叠。
// 边界：文本内容若出现 `svelte-` 字样字面量会被误剥（教学文案无此形态）。
function normalize(html: string): string {
  return html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/\bsvelte-[a-z0-9]+\b/g, "")
    .replace(/class="\s*"/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

// 用例表：组件渲染闭包按 payload 参数取数。空态用例（outputview-empty）
// 与实态用例（outputview-three）同组件异 payload——payload 是输入、golden
// 是输出，两分支各锚一份快照。
// renderCase 先 loadPayload 再调闭包——闭包内 frameAt(session.idx) 读到的
// 即本用例 payload 的帧，无需透传 p；签名统一 (p) => string 供 CourseNote
// 的 props 段取数，直读 session 的组件忽略参数。空态用例（outputview-empty）
// 与实态用例（outputview-three）同组件异 payload——payload 是输入、golden
// 是输出，两分支各锚一份快照。
const CASES: Record<string, (p: CorePayload) => string> = {
  "varslist-multi": () => render(VarsList).body,
  "replaybar-mid": () => render(ReplayBar).body,
  "arraybars-bubble-a": () => render(ArrayBars, { props: { snap: frameAt(session.idx)?.array_snapshots[0] } }).body,
  "arraybars-bubble-b": () => render(ArrayBars, { props: { snap: frameAt(session.idx)?.array_snapshots[1] } }).body,
  "memoryview-mallocfree": () => render(MemoryView).body,
  "outputview-three": () => render(OutputView).body,
  "outputview-empty": () => render(OutputView).body,
  "catalogview-diagnostics": () => render(CatalogView).body,
  "protoview-caps": () => render(ProtoView).body,
  // 课程叙述 × 真源链（换真值）：title 与 blocks 全部来自 course/*.md 解析
  "coursenote-blocks": () =>
    render(CourseNote, {
      props: { title: BUBBLE.meta.title ?? "", blocks: BUBBLE.blocks },
    }).body,
  // sorting 真源（覆盖矩阵：ul / table 块型的真源锚——basic/bubble 无此两型）
  "coursenote-sorting": () =>
    render(CourseNote, {
      props: { title: BUBBLE_SORT.meta.title ?? "", blocks: BUBBLE_SORT.blocks },
    }).body,
  // h3 块型覆盖（冻结样本块——真源缺口登记见头注覆盖矩阵；样本块文案明标
  // 「冻结样本」防与真源内容混淆）
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
