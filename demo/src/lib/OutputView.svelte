<script lang="ts">
  // 运行输出四通道视图（F4 组件迁移：对齐旧栈 renderOutput 分域形态）——
  // stdout 主通道、stderr/note 次通道；V3 质感批恢复常驻分域框；A17（#140）
  // note 通道接 [语义id]→SVG 徽章装饰（decorateBadges 白名单表，输入先 esc）。
  import { session } from "../session.svelte.ts";
  import { decorateBadges, esc } from "../../js/util.ts";
</script>

<div class="out">
  {#if session.outputs.stdout}
    <pre class="ch stdout">{session.outputs.stdout}</pre>
  {:else}
    <p class="muted">（stdout 无输出）</p>
  {/if}
  {#if session.outputs.stderr}
    <pre class="ch stderr">{session.outputs.stderr}</pre>
  {/if}
  {#if session.outputs.note}
    <pre class="ch note">{@html decorateBadges(esc(session.outputs.note))}</pre>
  {/if}
</div>

<style>
  .out { min-width: 0; }
  .ch { background: var(--editor-bg); border: 1px solid var(--hairline); border-radius: 8px; padding: 10px 12px; min-height: 46px; max-height: 360px; overflow: auto; white-space: pre-wrap; word-break: break-word; margin: 6px 0 0; font: 12.5px/1.6 var(--mono); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .ch.stdout { color: var(--code-text); }
  .ch.stderr { margin-top: 10px; background: var(--danger-tint); border: 1px dashed var(--danger); color: var(--danger); }
  .ch.note { margin-top: 10px; background: var(--accent-tint); border: 1px dashed var(--accent); color: var(--accent-strong); }
  .muted { color: var(--t3); font-size: 12.5px; }
</style>
