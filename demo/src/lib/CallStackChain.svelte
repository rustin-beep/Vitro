<script lang="ts">
  // 调用栈链（A11，#140——旧栈 stepRender 调用栈区语义平移）：
  // 当前帧 call_stack 序列重建 main → … → 当前函数，非栈顶帧标 return_line
  // （返回行号）；空栈显式说明（prog 帧等无栈场景）。
  import { session, frameAt } from "../session.svelte.ts";

  const stack = $derived(frameAt(session.idx)?.call_stack ?? []);
</script>

<div class="cschain">
  {#if stack.length === 0}
    <span class="muted">（空栈——当前帧不在函数调用内）</span>
  {:else}
    {#each stack as cf, i (i)}
      <span class="csf" class:top={i === stack.length - 1}>{cf.func_name}</span>
      {#if i < stack.length - 1}
        <span class="csret">—r{cf.return_line}→</span>
      {/if}
    {/each}
  {/if}
</div>

<style>
  .cschain { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; font: 12px var(--mono); color: var(--t2); padding: 4px 0; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .csf { padding: 2px 8px; border: 1px solid var(--hairline); border-radius: 10px; background: var(--pane); }
  .csf.top { border-color: var(--accent); color: var(--accent-strong); background: var(--accent-tint); }
  .csret { color: var(--t3); font-size: 11px; }
  .muted { color: var(--t3); font-size: 12px; }
</style>
