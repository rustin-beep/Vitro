<script lang="ts">
  // 执行信息卡（A12，#140——旧栈 timetravel.ts updateNodeCard/applyCardFold
  // 语义平移）：当前帧的事件标注/合并指令数/算法步/函数与步号/代码预览±2行。
  // 折叠态跨帧保持（组件 $state 生命周期 = 会话级）。合并数来自语句级组的
  // _grp.k（GranFrame 前端自有扩展，非协议字段——指令级帧恒单条）。
  import { session, frameAt } from "../session.svelte.ts";
  import type { GranFrame } from "../../js/types.ts";

  let { source }: { source: string } = $props();
  let folded = $state(false);

  const frame = $derived(frameAt(session.idx) as GranFrame | undefined);
  const mergeText = $derived(frame?._grp && frame._grp.k > 1 ? `本机合并 ${frame._grp.k} 条 · VM 指令` : "单条 VM 指令");
  const preview = $derived.by(() => {
    const ln = frame?.code_line ?? 0;
    if (ln <= 0 || !source) return [];
    const all = source.split("\n");
    const lo = Math.max(0, ln - 3);
    return all.slice(lo, ln + 2).map((t, i) => ({ n: lo + i + 1, t, cur: lo + i + 1 === ln }));
  });
</script>

{#if frame}
  <div class="info-card" class:folded>
    <button type="button" class="ic-head" onclick={() => (folded = !folded)} aria-expanded={!folded}>
      <b>执行信息</b>
      <span class="ic-tri">{folded ? "▸" : "▾"}</span>
    </button>
    {#if !folded}
      <div class="ic-line ic-label">【{frame.semantic_label || "执行"}】第 {frame.code_line} 行 · {frame.func_name}</div>
      <div class="ic-line">{mergeText}</div>
      {#if frame.algorithm_step}
        <div class="ic-line ic-algo">🧭 {frame.algorithm_step.display_name} · {frame.algorithm_step.phase}</div>
      {/if}
      <div class="ic-line ic-step">第 {frame.step_index} 步</div>
      {#if preview.length > 0}
        <pre class="ic-code">{#each preview as p (p.n)}<span class="ic-cl" class:cur={p.cur}>{String(p.n).padStart(3)}  {p.t}</span>{"\n"}{/each}</pre>
      {/if}
    {/if}
  </div>
{/if}

<style>
  .info-card { border: 1px solid var(--hairline); border-radius: 8px; background: var(--pane); padding: 6px 10px; font-size: 12px; min-width: 240px; }
  .info-card.folded { padding: 4px 10px; }
  .ic-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; width: 100%; background: none; border: 0; color: var(--t1); font: 12px var(--font-ui); cursor: pointer; padding: 0; }
  .ic-tri { color: var(--t3); }
  .ic-line { margin-top: 4px; color: var(--t2); }
  .ic-label { color: var(--accent-strong); font-weight: 600; }
  .ic-algo { color: var(--num); }
  .ic-step { font: 11.5px var(--mono); color: var(--t3); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .ic-code { margin: 6px 0 0; padding: 6px 8px; background: var(--editor-bg); border: 1px solid var(--hairline); border-radius: 6px; font: 11px/1.6 var(--mono); color: var(--t2); overflow: auto; max-height: 140px; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .ic-cl { display: block; white-space: pre; }
  .ic-cl.cur { color: var(--accent-strong); background: var(--accent-tint); border-radius: 3px; }
</style>
