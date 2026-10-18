<script lang="ts">
  // 操作反馈栈——kind 走语义边色（ok / err / info），全局样式在 app.css
  // （.vr-toasts / .vr-toast）。自动过期由 toasts 层管理，此处只渲染 + 手关。
  import { toasts, dismiss } from "../toasts.svelte.ts";
</script>

<div class="vr-toasts" aria-live="polite" aria-atomic="false">
  {#each toasts.items as t (t.id)}
    <div class="vr-toast is-{t.kind}">
      <span>{t.text}</span>
      <button type="button" onclick={() => dismiss(t.id)} aria-label="关闭提示">×</button>
    </div>
  {/each}
</div>
