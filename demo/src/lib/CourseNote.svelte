<script lang="ts">
  // 课程叙述渲染（真源 course/<chap>/<id>/lesson.md → parseLessonMd → 块模型）：
  // keyed 块渲染、无 innerHTML（XSS 归零）；行内 **粗体** / `行内码` 经
  // parseInline token 化后分支渲染（P2-2：此前 ** 当字面量）。
  // 视觉走设计稿的「书页」排版（.vr-note）：衬线小节标题、行内 code chip、
  // 琥珀引言块；标题由页面 hero 承担（page 形态不再重复 h1）。
  import type { Block } from "./lessonMd.ts";
  import { parseInline } from "./lessonMd.ts";

  let { title, blocks, page = false }: { title: string; blocks: Block[]; page?: boolean } = $props();
</script>

{#snippet inline(text: string)}
  {#each parseInline(text) as seg, j (j)}{#if seg.t === "bold"}<b>{seg.s}</b>{:else if seg.t === "code"}<code>{seg.s}</code>{:else}{seg.s}{/if}{/each}
{/snippet}

<article class="vr-note" class:vr-note-page={page} aria-label={title}>
  {#each blocks as b, i (i)}
    {#if b.type === "h2"}
      <h2>{@render inline(b.text)}</h2>
    {:else if b.type === "h3"}
      <h3>{@render inline(b.text)}</h3>
    {:else if b.type === "p"}
      <p>{@render inline(b.text)}</p>
    {:else if b.type === "ul"}
      <ul>{#each b.items as it (it)}<li>{@render inline(it)}</li>{/each}</ul>
    {:else if b.type === "ol"}
      <ol>{#each b.items as it (it)}<li>{@render inline(it)}</li>{/each}</ol>
    {:else if b.type === "code"}
      <pre data-lang={b.lang}><code>{b.text}</code></pre>
    {:else if b.type === "table"}
      <div class="vr-table">
        <table>
          <thead><tr>{#each b.rows[0] as c (c)}<th>{@render inline(c)}</th>{/each}</tr></thead>
          <tbody>
            {#each b.rows.slice(1) as row, ri (ri)}
              <tr>{#each row as c (c)}<td>{@render inline(c)}</td>{/each}</tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {/each}
</article>
