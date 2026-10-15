<script lang="ts">
  // 操作反馈栈（右下）——kind 色彩走 tokens 语义（ok/--ok、err/--danger、
  // info/--accent）；自动过期由 toasts 层管理，此处只渲染 + 手关。
  import { toasts, dismiss } from "../toasts.svelte.ts";
</script>

<div class="toasts" aria-live="polite">
  {#each toasts.items as t (t.id)}
    <div class="toast {t.kind}">
      <span class="t-text">{t.text}</span>
      <button type="button" class="t-x" onclick={() => dismiss(t.id)} aria-label="关闭提示">×</button>
    </div>
  {/each}
</div>

<style>
  .toasts { position: fixed; right: 16px; bottom: 16px; display: flex; flex-direction: column; gap: 8px; z-index: 60; max-width: min(420px, calc(100vw - 32px)); }
  .toast { display: flex; align-items: baseline; gap: 10px; background: var(--pane); border: 1px solid var(--hairline); border-left: 3px solid var(--accent); border-radius: 8px; padding: 9px 12px; box-shadow: var(--inset-soft, none); animation: t-in var(--t-fast) var(--ease-out); }
  .toast.ok { border-left-color: var(--ok); }
  .toast.err { border-left-color: var(--danger); }
  .t-text { font-size: 12.5px; color: var(--t1); white-space: pre-wrap; word-break: break-word; }
  .t-x { background: none; border: 0; color: var(--t3); cursor: pointer; font: 14px var(--font-ui); padding: 0 2px; }
  @keyframes t-in { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }
</style>
