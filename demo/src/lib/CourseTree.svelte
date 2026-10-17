<script lang="ts">
  // 课程档案树（F4 组件迁移：对齐现役 course.ts buildChapters 形态）——
  // 数据 = DEMO_CASES（第〇章基础课）+ DEMO_ALGORITHMS（七算法章 + 扩展
  // 练习章），经虚拟模块 virtual:demo-globals（审阅 D-#4 三方契约的
  // 过渡形态：构建期追加 export，现役文件零改动）。
  //
  // 迁移红利（审阅 B-P3-13/P2-8）：折叠章集合进 store（旧栈折叠态纯
  // DOM-local——搜索清空把用户手动收起的章全部展开的病在此关死）；
  // 课目行真 button（旧栈 div+onclick 键盘/读屏不可达在此还清）。
  import type { DemoCase, AlgoGroup } from "virtual:demo-globals";
  import { DEMO_CASES, DEMO_ALGORITHMS } from "virtual:demo-globals";
  import { SvelteSet } from "svelte/reactivity";
  import type { TreeLesson, TreeChapter } from "./courseTypes.ts";

  let query = $state("");
  // V5（#141）：初始折叠 = 全部算法章 + 扩展章（groups 的 id 集），第〇章
  // 基础课默认展开——对齐旧栈 course.ts 初始折叠形态（此前全展开 = 长树
  // 不可扫读）。折叠集合仍进 store：搜索清空不复位（迁移红利保留）。
  let collapsed = new SvelteSet<string>((DEMO_ALGORITHMS.groups ?? []).map((g: AlgoGroup) => g.id));
  let selectedId = $state("");

  const chapters: TreeChapter[] = $derived.by(() => {
    const out: TreeChapter[] = [];
    // 第〇章：基础与白箱演示（用例 = 基础课）
    out.push({
      id: "basic",
      label: "基础与白箱演示",
      lessons: DEMO_CASES.map((k: DemoCase) => ({
        id: k.id, title: k.label, blurb: k.blurb || "", kind: "case" as const, source: k.source,
      })),
    });
    // 七算法章（族 = 课；变体 = 族内子项）
    const groups = (DEMO_ALGORITHMS.groups ?? []).filter((g: AlgoGroup) => g.id !== "xlab");
    for (const g of groups) {
      const lessons: TreeLesson[] = [];
      for (const it of g.items ?? []) {
        lessons.push({ id: it.id, title: it.name, blurb: it.id, kind: "algo", source: it.source });
        for (const v of it.variants ?? []) {
          lessons.push({ id: v.tpl, title: v.tpl, blurb: `${it.name} · 变体`, kind: "variant", famId: it.id, source: v.source });
        }
      }
      out.push({ id: g.id, label: g.label, lessons });
    }
    // 扩展练习章
    const xg = (DEMO_ALGORITHMS.groups ?? []).find((g: AlgoGroup) => g.id === "xlab");
    if (xg) {
      out.push({
        id: "xlab",
        label: xg.label,
        lessons: (xg.xitems ?? []).map((x) => ({ id: x.id, title: x.name, blurb: x.id, kind: "xlab" as const, source: x.source })),
      });
    }
    return out;
  });

  const filtered = $derived.by(() => {
    const q = query.trim().toLowerCase();
    if (!q) return chapters;
    return chapters
      .map((ch) => ({ ...ch, lessons: ch.lessons.filter((l) => `${l.title} ${l.blurb} ${l.id}`.toLowerCase().includes(q)) }))
      .filter((ch) => ch.lessons.length > 0);
  });

  function toggleChap(id: string): void {
    if (collapsed.has(id)) collapsed.delete(id);
    else collapsed.add(id);
  }

  function pickLesson(l: TreeLesson, chapId: string): void {
    selectedId = l.id;
    // 课源码载入编辑器的通道（setSource）由 App 注入 prop——组件不含
    // DOM 写权（旧栈 editor.value 直写 + 手工跟渲染的反模式不带入新栈）
    onpick?.(l, chapId);
  }

  interface Props {
    onpick?: (l: TreeLesson, chapId: string) => void;
  }
  let { onpick }: Props = $props();
</script>

<div class="ctree">
  <input class="ct-search" placeholder="搜索课程…" bind:value={query} aria-label="搜索课程" />
  {#each filtered as ch (ch.id)}
    {@const isCollapsed = collapsed.has(ch.id)}
    <div class="chap" class:collapsed={isCollapsed}>
      <button type="button" class="chap-head" onclick={() => toggleChap(ch.id)} aria-expanded={!isCollapsed}>
        <span class="tri">{isCollapsed ? "▸" : "▾"}</span>
        {ch.label}
        <span class="cnt">({ch.lessons.length})</span>
      </button>
      {#if !isCollapsed}
        <div class="lessons">
          {#each ch.lessons as l (ch.id + "/" + l.kind + "/" + l.id)}
            <button type="button" class="lesson" class:selected={selectedId === l.id} onclick={() => pickLesson(l, ch.id)} title={l.blurb}>
              <span class="lid">{l.id}</span>
              <span class="ltitle">{l.title}</span>
            </button>
          {/each}
        </div>
      {/if}
    </div>
  {:else}
    <p class="muted">（无匹配课程）</p>
  {/each}
</div>

<style>
  .ct-search { width: 100%; background: var(--field); color: var(--t1); border: 1px solid var(--hairline); border-radius: 6px; padding: 7px 10px; font: 13px var(--font-ui); margin-bottom: 8px; }
  .chap { margin: 2px 0; }
  .chap-head { display: flex; align-items: center; gap: 6px; width: 100%; text-align: left; background: none; border: 0; color: var(--t1); font: 12.5px var(--font-ui); padding: 5px 6px; cursor: pointer; border-radius: 6px; }
  .chap-head:hover { background: var(--accent-tint); }
  .tri { color: var(--t3); width: 12px; }
  .cnt { color: var(--t3); font-size: 11px; }
  .lessons { padding-left: 14px; }
  .lesson { display: flex; gap: 8px; width: 100%; text-align: left; background: none; border: 0; color: var(--t2); font: 12px var(--font-ui); padding: 4px 6px; cursor: pointer; border-radius: 5px; }
  .lesson:hover { background: var(--accent-tint); }
  .lesson.selected { background: var(--accent-tint); color: var(--accent-strong); }
  .lid { font-family: var(--mono); color: var(--t3); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; min-width: 0; }
  .ltitle { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .muted { color: var(--t3); font-size: 12.5px; }
</style>
