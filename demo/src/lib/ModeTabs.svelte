<script lang="ts">
  // 仪器三模式导航（#222 P1 内存/协议形态，2026-10-22）：执行 / 内存 / 协议。
  //
  // 两处渲染同一 DOM 语义（右栏 compact 版 / 模式页页头版）——E2E 与样式契约
  // 只认 .vr-modes/.vr-mode，不因布局位移改锚。`meta` 是右侧状态注（执行态传
  // 粒度「语句级/指令级」，模式页传「只读 · 会话结束态」）。
  import { setMode, ui } from "../ui.svelte.ts";

  let { meta = "" }: { meta?: string } = $props();
</script>

<nav class="vr-modes" aria-label="仪器模式">
  <button type="button" class="vr-mode" class:is-active={ui.mode === "exec"} onclick={() => setMode("exec")}>执行</button>
  <button type="button" class="vr-mode" class:is-active={ui.mode === "mem"} onclick={() => setMode("mem")}>内存</button>
  <button type="button" class="vr-mode" class:is-active={ui.mode === "proto"} onclick={() => setMode("proto")}>协议</button>
  {#if meta}<span class="vr-mode-meta">{meta}</span>{/if}
</nav>
