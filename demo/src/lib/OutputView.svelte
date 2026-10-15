<script lang="ts">
  // 运行输出四通道视图（F4 组件迁移：对齐旧栈 renderOutput 分域形态）——
  // stdout 主通道、stderr/note 折叠次通道；文本插值自动转义（旧栈
  // renderOutput 的 esc 义务在此消失）。 Latin-1 还原已在 worker 完成。
  import { session } from "../session.svelte.ts";

  let showErr = $state(false);
  let showNote = $state(false);
</script>

<div class="out">
  {#if session.outputs.stdout}
    <pre class="ch stdout">{session.outputs.stdout}</pre>
  {:else}
    <p class="muted">（stdout 无输出）</p>
  {/if}
  {#if session.outputs.stderr}
    <button type="button" class="ch-toggle err" onclick={() => (showErr = !showErr)} aria-expanded={showErr}>
      stderr ({session.outputs.stderr.length} B) {showErr ? "▾" : "▸"}
    </button>
    {#if showErr}<pre class="ch stderr">{session.outputs.stderr}</pre>{/if}
  {/if}
  {#if session.outputs.note}
    <button type="button" class="ch-toggle note" onclick={() => (showNote = !showNote)} aria-expanded={showNote}>
      note ({session.outputs.note.length} B) {showErr || showNote ? "▾" : "▸"}
    </button>
    {#if showNote}<pre class="ch note">{session.outputs.note}</pre>{/if}
  {/if}
</div>

<style>
  .out { min-width: 0; }
  .ch { background: var(--editor-bg); border: 1px solid var(--hairline); border-radius: 8px; padding: 9px 12px; overflow-x: auto; white-space: pre-wrap; word-break: break-word; margin: 6px 0; font: 12.5px/1.6 var(--mono); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .ch.stdout { color: var(--code-text); }
  .ch.stderr { color: var(--danger); }
  .ch.note { color: var(--accent-strong); }
  .ch-toggle { background: none; border: 0; color: var(--t3); font: 12px var(--mono); cursor: pointer; padding: 2px 0; text-align: left; font-variant-ligatures: none; }
  .ch-toggle.err { color: var(--danger); }
  .muted { color: var(--t3); font-size: 12.5px; }
</style>
