<script lang="ts">
  // 课程叙述渲染（F4 course 组件批）——块模型 keyed 渲染，无 innerHTML
  // （#125 宿主侧方案的 XSS 归零原则在此兑现）；代码块等宽 + 关连字
  // （#121 纪律），语法高亮（tokenizeC）留后续刀。
  import type { Block } from "./lessonMd.ts";

  let { title, blocks }: { title: string; blocks: Block[] } = $props();
</script>

<article class="cnote">
  <h1>{title}</h1>
  {#each blocks as b, i (i)}
    {#if b.type === "h2"}
      <h2>{b.text}</h2>
    {:else if b.type === "h3"}
      <h3>{b.text}</h3>
    {:else if b.type === "p"}
      <p>{b.text}</p>
    {:else if b.type === "ul"}
      <ul>{#each b.items as it (it)}<li>{it}</li>{/each}</ul>
    {:else if b.type === "ol"}
      <ol>{#each b.items as it (it)}<li>{it}</li>{/each}</ol>
    {:else if b.type === "code"}
      <pre class="cn-code" data-lang={b.lang}><code>{b.text}</code></pre>
    {:else if b.type === "table"}
      <div class="cn-table">
        <table>
          <thead><tr>{#each b.rows[0] as c (c)}<th>{c}</th>{/each}</tr></thead>
          <tbody>
            {#each b.rows.slice(1) as row, ri (ri)}
              <tr>{#each row as c (c)}<td>{c}</td>{/each}</tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {/each}
</article>

<style>
  .cnote h1 { font-size: 16px; margin: 4px 0 10px; }
  .cnote h2 { font-size: 14px; margin: 14px 0 6px; color: var(--t1); border-bottom: 1px solid var(--hairline); padding-bottom: 4px; }
  .cnote h3 { font-size: 13px; margin: 10px 0 4px; color: var(--t1); }
  .cnote p { font-size: 13px; line-height: 1.65; color: var(--t2); margin: 6px 0; }
  .cnote ul, .cnote ol { font-size: 13px; line-height: 1.6; color: var(--t2); margin: 6px 0; padding-left: 20px; }
  .cn-code { background: var(--editor-bg); border: 1px solid var(--hairline); border-radius: 8px; padding: 10px 12px; overflow-x: auto; font: var(--ed-fs, 14px)/1.5 var(--mono); color: var(--code-text); margin: 8px 0; white-space: pre; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .cn-table { overflow-x: auto; margin: 8px 0; }
  .cn-table table { border-collapse: collapse; font-size: 12.5px; width: 100%; }
  .cn-table th, .cn-table td { text-align: left; padding: 4px 10px; border: 1px solid var(--hairline); color: var(--t2); }
  .cn-table th { background: var(--pane); color: var(--t3); font-weight: normal; }
</style>
