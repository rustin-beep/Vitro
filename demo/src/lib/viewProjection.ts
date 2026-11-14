// 视图分派计划（demo 宿主手写面，批 D 2026-11-14，refs #470 v0.1.1）。
//
// 边界：引擎侧 `projectors.ts`（由 moonbit/view/projectors.json 生成）只给
// 语义契约——哪些 id 合法、需要几条序列、是否需要 dims；本文件负责把课程
// `<!-- vitri-viz v1 -->` 声明与当前帧的 array_snapshots 对上，产出宿主该画
// 什么。**绘制本身在 Svelte 组件里**，这里不碰 DOM/SVG/CSS。
//
// 三条硬规矩：
//   ① 未声明的序列一律退回默认 `cells` 索引格（旧课零改动、渲染面不变）；
//   ② 声明不合法（未知投影器 / 序列缺失 / 条数不符 / 缺 dims）不静默降级，
//      原样带出错误文案由宿主显示（消费点 fail loud）；
//   ③ 宿主绘制器注册表 `RENDERERS` 必须覆盖词表全族——新增投影器不改本表
//      即由 pure.test.mts 的对账锚判红，杜绝「词表加了但两端都没画」。

import type { ArraySnapshot } from "../../js/types.ts";
import type { VizDecl } from "./lessonMd.ts";
import { DEFAULT_PROJECTOR, PROJECTORS, projectorSpec, type ProjectorId } from "./projectors.ts";

export type Renderer = "cells" | "svg";

/** 宿主绘制器注册表：cells = 复用 ArrayCells 索引格；svg = SeriesView 参数化图形。
 *  `Record<ProjectorId, …>` 在编译期强制全族覆盖，运行时再经对账锚复核。 */
export const RENDERERS: Record<ProjectorId, Renderer> = {
  bars: "svg",
  cells: "cells",
  grid2d: "cells",
  line: "svg",
  polar: "svg",
  spectrum: "svg",
};

/** 全族 id（词表定序）——对账锚用。 */
export function rendererIds(): string[] {
  return Object.keys(RENDERERS).sort();
}

export interface CellsView {
  kind: "cells";
  snap: ArraySnapshot;
  key: string;
}

export interface DeclView {
  kind: "decl";
  decl: VizDecl;
  snaps: ArraySnapshot[];
  /** null = 可画；非 null = 声明不合法，宿主只显示错误、不猜绘法。 */
  error: string | null;
  renderer: Renderer;
  key: string;
}

export type ViewPlan = CellsView | DeclView;

/** 一条声明的落点校验（纯函数，逐条给中文原因）。 */
export function declError(decl: VizDecl, found: readonly ArraySnapshot[], missing: readonly string[]): string | null {
  const at = `（课程 viz 第 ${decl.line} 行）`;
  const spec = projectorSpec(decl.projector);
  if (!spec) return `未知投影器 ${decl.projector}${at}；已登记：${PROJECTORS.map((p) => p.id).join("、")}`;
  if (missing.length > 0) return `序列未出现在本帧快照中：${missing.join("、")}${at}`;
  if (found.length < spec.seriesMin) {
    return `${decl.projector} 需至少 ${spec.seriesMin} 条序列，实得 ${found.length}${at}`;
  }
  if (spec.seriesMax !== -1 && found.length > spec.seriesMax) {
    return `${decl.projector} 至多 ${spec.seriesMax} 条序列，实得 ${found.length}${at}`;
  }
  const dims = found[0]?.dims?.length ?? 1;
  if (dims < spec.minDims) {
    return `${decl.projector} 需 ${spec.minDims} 维维度表（dims），当前序列仅 ${dims} 维${at}`;
  }
  return null;
}

/** 把课程声明 + 本帧数组快照 → 视图计划（确定性：声明序在前，未声明序在后）。 */
export function planViews(vizs: readonly VizDecl[], snaps: readonly ArraySnapshot[]): ViewPlan[] {
  const byName = new Map<string, ArraySnapshot>();
  for (const s of snaps) if (!byName.has(s.name)) byName.set(s.name, s);
  const used = new Set<string>();
  const out: ViewPlan[] = [];
  for (const [i, decl] of vizs.entries()) {
    const found: ArraySnapshot[] = [];
    const missing: string[] = [];
    for (const name of decl.series) {
      const s = byName.get(name);
      if (s) {
        found.push(s);
        used.add(name);
      } else missing.push(name);
    }
    const error = declError(decl, found, missing);
    const spec = projectorSpec(decl.projector);
    // 词表命中 ⇒ id 属于 ProjectorId 全族（RENDERERS 由编译期保证逐项覆盖）。
    const renderer: Renderer = spec ? RENDERERS[spec.id as ProjectorId] : "cells";
    const key = `decl:${i}:${decl.projector}:${decl.series.join("+")}`;
    // cells 系投影器逐序列展开成现有索引格（grid2d 由 ArrayCells 的 dims 分支承接）。
    if (error === null && renderer === "cells") {
      for (const [j, s] of found.entries()) {
        out.push({ kind: "cells", snap: s, key: `${key}:${j}` });
      }
      continue;
    }
    out.push({ kind: "decl", decl, snaps: found, error, renderer, key });
  }
  for (const [i, s] of snaps.entries()) {
    if (!used.has(s.name)) out.push({ kind: "cells", snap: s, key: `cells:${i}:${s.name}` });
  }
  return out;
}

/** 无 viz 声明的课：全部按默认投影器画（= 现有索引格行为，逐字节不变）。 */
export function defaultViews(snaps: readonly ArraySnapshot[]): ViewPlan[] {
  return planViews([], snaps);
}

/** 未声明序列的回退投影器（词表真源；宿主实现必须在 RENDERERS 里）。 */
export const FALLBACK_PROJECTOR = DEFAULT_PROJECTOR;
