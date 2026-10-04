// Vitro demo · 算法可视化侧栏（2026-10-04，refs #28：43 教学标注族导航——
// #28 范围说明的「侧栏列表为渲染产物非逐项手画」兑现：数据 = algorithms.js
// 由 scripts/gen_demo_algorithms 从 rules.json/golden/detect 判据源机判生成；
// 全量纳入批（用户拍板「资源放着浪费」）：82 个 .c 模板全覆盖——43 族 +
// 族内变体 + 扩展练习组（未迁移族模板，能跑回放但无算法标注，诚实标注态）。
// 交互：点卡片 → 示例源码进编辑器（编辑器内容恒真源）→ 切「运行」视图 →
// 自动采集 step 流；帧标注与事件行高亮见 timetravel。is_prime/
// threaded_binary_tree 两族因引擎 code_line 基准偏移暂无帧标注（issue #34）。
"use strict";

import { $, esc } from "./util.ts";
import { renderEditorDecor } from "./editor.ts";
import { collectCurrentEditor } from "./timetravel.ts";

interface AlgoVariant {
  tpl: string;
  source: string;
}
interface AlgoItem {
  id: string;
  name: string;
  template: string;
  source: string;
  variants?: AlgoVariant[];
}
interface AlgoXItem {
  id: string;
  name: string;
  source: string;
}
interface AlgoGroup {
  id: string;
  label: string;
  items?: AlgoItem[];
  xitems?: AlgoXItem[];
}

export function renderAlgoGrid(): void {
  const grid = $("algo-grid");
  const groups = (DEMO_ALGORITHMS.groups || []) as AlgoGroup[];
  if (!groups.length) {
    grid.innerHTML = '<p class="muted">algorithms.js 未加载或为空</p>';
    return;
  }
  grid.innerHTML = groups
    .map((g) => {
      if (g.xitems) {
        // 扩展练习组（未迁移族模板——能跑回放，无算法标注）
        return (
          `<div class="algo-group" data-g="${esc(g.id)}">` +
          `<div class="algo-gtitle">${esc(g.label)}<span class="algo-gcount">${g.xitems.length}</span>` +
          `<span class="algo-gnote">未标注族——可运行回放，算法标注随引擎迁移面</span></div>` +
          `<div class="algo-cards">` +
          g.xitems
            .map(
              (it) =>
                `<button class="algo-card xitem" data-x="${esc(it.id)}" title="${esc(it.id)}（暂无算法标注）">` +
                esc(prettify(it.id)) +
                `</button>`
            )
            .join("") +
          `</div></div>`
        );
      }
      const items = g.items || [];
      return (
        `<div class="algo-group" data-g="${esc(g.id)}">` +
        `<div class="algo-gtitle">${esc(g.label)}<span class="algo-gcount">${items.length}</span></div>` +
        `<div class="algo-cards">` +
        items
          .map(
            (it) =>
              `<span class="algo-cardwrap">` +
              `<button class="algo-card" data-id="${esc(it.id)}" title="${esc(it.name)}（${esc(it.id)}）">` +
              esc(it.name) +
              (it.template === "extra" ? '<span class="algo-badge">示例</span>' : "") +
              `</button>` +
              (it.variants && it.variants.length
                ? `<button class="algo-variants" data-v="${esc(it.id)}" title="示例变体（同族其它模板）">+${it.variants.length}</button>`
                : "") +
              `</span>`
          )
          .join("") +
        `</div>` +
        variantRows(items) +
        `</div>`
      );
    })
    .join("");
  bindGrid(grid, groups);
}

// 变体行（默认隐藏，+N 点击展开——课程式三级：组→族→变体）
function variantRows(items: AlgoItem[]): string {
  return items
    .filter((it) => it.variants && it.variants.length)
    .map(
      (it) =>
        `<div class="algo-varlist hidden" data-for="${esc(it.id)}">` +
        it.variants!
          .map((v) => `<button class="algo-var" data-tpl="${esc(v.tpl)}" data-fam="${esc(it.id)}">${esc(prettify(v.tpl))}</button>`)
          .join("") +
        `</div>`
    )
    .join("");
}

function prettify(id: string): string {
  // camelCase/snake → 空格分词首字母大写（扩展组与变体的显示名）
  return id
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function bindGrid(grid: HTMLElement, groups: AlgoGroup[]): void {
  const allItems = groups.flatMap((g) => g.items || []);
  const allX = groups.flatMap((g) => g.xitems || []);
  grid.querySelectorAll<HTMLElement>(".algo-card").forEach((btn) => {
    btn.onclick = () => {
      const item = allItems.find((i) => i.id === btn.dataset.id);
      if (item) loadAlgoSource(item.name, item.source);
    };
  });
  grid.querySelectorAll<HTMLElement>(".algo-card.xitem").forEach((btn) => {
    btn.onclick = () => {
      const it = allX.find((x) => x.id === btn.dataset.x);
      if (it) loadAlgoSource(prettify(it.id), it.source);
    };
  });
  grid.querySelectorAll<HTMLElement>(".algo-variants").forEach((btn) => {
    btn.onclick = (e: MouseEvent) => {
      e.stopPropagation();
      const list = grid.querySelector<HTMLElement>(`.algo-varlist[data-for="${btn.dataset.v}"]`);
      if (list) list.classList.toggle("hidden");
    };
  });
  grid.querySelectorAll<HTMLElement>(".algo-var").forEach((btn) => {
    btn.onclick = () => {
      const fam = allItems.find((i) => i.id === btn.dataset.fam);
      const v = fam && fam.variants ? fam.variants.find((x) => x.tpl === btn.dataset.tpl) : null;
      if (v) loadAlgoSource(`${fam!.name} · ${prettify(v.tpl)}`, v.source);
    };
  });
}

function loadAlgoSource(label: string, source: string): void {
  const ta = $("editor") as HTMLTextAreaElement;
  ta.value = source;
  renderEditorDecor();
  // 切到「运行」视图（时间旅行回放区在运行视图内）
  const tabBtn = document.querySelector<HTMLElement>('.tabs .tab[data-tab="result"]');
  if (tabBtn) tabBtn.click();
  // 自动采集（step 流重建 + 回到帧 0；用户再点 ▶ 播放）——标题提示当前示例
  const phase = document.getElementById("anim-phase");
  if (phase) phase.textContent = `已载入：${label}（采集后回放）`;
  void collectCurrentEditor();
}
