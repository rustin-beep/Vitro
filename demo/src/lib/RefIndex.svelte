<script lang="ts">
  // 诊断手册左栏（参考态）：搜索 + 分类码表。纯展示组件（catalog 来自
  // session 层的 error_catalog 拉取）；选中态写 ui.refCode（单点导航态）。
  // E-08 快照用例 refindex-diagnostics 直接渲染本组件。
  import { session } from "../session.svelte.ts";
  import { ui } from "../ui.svelte.ts";
  import CodeIcon from "./CodeIcon.svelte";

  let query = $state("");

  const groups = $derived.by(() => {
    const q = query.trim().toLowerCase();
    const all = q
      ? session.catalog.filter((c) =>
          [c.code_str, c.title, c.category, c.explanation, ...(c.common_causes ?? [])].join(" ").toLowerCase().includes(q),
        )
      : session.catalog;
    const byCat = new Map<string, typeof all>();
    for (const c of all) {
      if (!byCat.has(c.category)) byCat.set(c.category, []);
      byCat.get(c.category)!.push(c);
    }
    return [...byCat.entries()];
  });
</script>

<aside class="vr-ref-index" aria-label="诊断目录">
  <input class="vr-search" type="search" placeholder="搜索 E 码或关键词…" aria-label="搜索诊断" bind:value={query} />
  {#if !session.catalog.length}
    <p class="vr-empty">（目录加载中或不可用…）</p>
  {:else}
    <div class="vr-ref-list">
      {#each groups as [category, items] (category)}
        <div class="vr-ref-group">{category} · {items.length}</div>
        {#each items as c (c.code_str)}
          <button
            type="button"
            class="vr-ref-item"
            class:is-active={ui.refCode === c.code_str}
            onclick={() => (ui.refCode = c.code_str)}
            title={c.title}
          >
            <CodeIcon icon={c.icon} size={14} />
            <span class="vr-code-id">{c.code_str}</span>
            <span class="vr-ref-name">{c.title}</span>
          </button>
        {/each}
      {/each}
    </div>
    <p class="vr-ref-note">{session.catalog.length} 条 · error_catalog 单源</p>
  {/if}
</aside>
