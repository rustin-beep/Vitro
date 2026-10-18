<script lang="ts">
  // 诊断手册目录（F4 组件迁移低风险批第一件，refs 审阅 B-P3-12/B-P3-15）：
  // 纯展示组件——协议数据归 session 层（session.catalog），本组件只有
  // 搜索框本地态 + 过滤/分组派生。keyed each by code_str——搜索过滤
  // $derived，details 展开态跨键入存活（旧栈每键全量 innerHTML 重建、
  // 展开态即丢）；文本插值自动转义。图标消费收编为 @html 仅限生成表
  // 可信体（icons.ts @generated）+ [id] 文本徽章 fallback（审阅 C-#9 处方）。
  import { session } from "../session.svelte.ts";
  import { catalogSeed } from "../tabs.svelte.ts";
  import { ICONS } from "../../js/icons.ts";

  let query = $state("");

  // P2-10：诊断卡/trap 详报的 E 码跳转种子——一次性消费后清空（防用户
  // 手动清空搜索框后被旧种子回跳覆盖）。
  $effect(() => {
    if (catalogSeed.q) {
      query = catalogSeed.q;
      catalogSeed.q = "";
    }
  });

  const groups = $derived.by(() => {
    const q = query.trim().toLowerCase();
    const all = q
      ? session.catalog.filter((c) =>
          [c.code_str, c.title, c.category, c.explanation, ...(c.common_causes ?? [])]
            .join(" ")
            .toLowerCase()
            .includes(q),
        )
      : session.catalog;
    const byCat = new Map<string, typeof all>();
    for (const c of all) {
      if (!byCat.has(c.category)) byCat.set(c.category, []);
      byCat.get(c.category)!.push(c);
    }
    return [...byCat.entries()];
  });

  function iconSvgOrFallback(id: string): string {
    // 壳参数对齐旧栈 icon.ts iconSvg（ICONS 表存 SVG 内部片段非完整 svg）
    const body = ICONS[id];
    if (!body) return `<span class="icon-missing">[${id}]</span>`;
    return `<svg class="icon-svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
  }
</script>

<div class="cat">
  <input class="cat-search" placeholder="搜索诊断码 / 关键词…" bind:value={query} aria-label="搜索诊断目录" />
  {#if !session.catalog.length}
    <p class="muted">（目录加载中或不可用…）</p>
  {:else}
    <p class="cat-count">{groups.reduce((n, [, items]) => n + items.length, 0)} / {session.catalog.length} 条</p>
    {#each groups as [category, items] (category)}
      <div class="cat-group">
        <div class="cat-head">{category} <span class="muted">({items.length})</span></div>
        {#each items as c (c.code_str)}
          <details class="cat-card">
            <summary>
              <span class="ic">{@html iconSvgOrFallback(c.icon)}</span>
              <span class="code">{c.code_str}</span>
              {c.title}
            </summary>
            <div class="cat-body">
              <p>{c.explanation}</p>
              {#if c.common_causes?.length}
                <p class="b">常见原因：{c.common_causes.join("；")}</p>
              {/if}
            </div>
          </details>
        {/each}
      </div>
    {/each}
  {/if}
</div>

<style>
  .cat-search { width: 100%; background: var(--field); color: var(--t1); border: 1px solid var(--hairline); border-radius: 6px; padding: 7px 10px; font: 13px var(--mono); margin: 6px 0; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .cat-count { font: 12px var(--mono); color: var(--t3); margin: 4px 0; font-variant-ligatures: none; }
  .muted { color: var(--t3); font-size: 12.5px; }
  .cat-group { margin: 8px 0 4px; }
  .cat-head { font-size: 12.5px; color: var(--t1); padding: 2px 0; border-bottom: 1px solid var(--hairline); }
  .cat-head .muted { font-size: 11px; }
  details.cat-card { border: 1px solid var(--hairline); border-radius: 6px; margin: 4px 0; padding: 6px 10px; background: var(--pane); }
  details.cat-card summary { cursor: pointer; font-size: 12.5px; display: flex; align-items: center; gap: 6px; }
  .ic { display: inline-flex; width: 16px; height: 16px; }
  .ic :global(svg) { width: 100%; height: 100%; }
  /* icon-missing 徽章 mono 面连字关闭（#121①——demo_ui_lint 检查 D 机判） */
  .ic :global(.icon-missing) { font: 10px var(--mono); color: var(--t3); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .code { font-family: var(--mono); color: var(--warn, var(--num)); font-variant-ligatures: none; }
  .cat-body { margin-top: 6px; font-size: 12.5px; color: var(--t2); }
  .cat-body p { margin: 4px 0; }
  .cat-body .b { color: var(--t3); }
</style>
