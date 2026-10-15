<script lang="ts">
  // 重放条——播放/暂停/单步/滑条 seek/帧计数/播放帧率档位/采集预算。
  // 全部状态与动作来自 session 层，本组件零私有状态。
  import { session, seek, step, togglePlay, setFps, setCap } from "../session.svelte.ts";

  const FPS_STEPS = [8, 30, 60, 240];
</script>

<div class="replay">
  <button type="button" class="btn ghost" onclick={togglePlay} disabled={session.collecting || session.frames.length === 0}>
    {session.playing ? "⏸ 暂停" : "▶ 播放"}
  </button>
  <button type="button" class="btn ghost" onclick={() => step(-1)} disabled={session.collecting || session.frames.length === 0} aria-label="上一帧">◀|</button>
  <button type="button" class="btn ghost" onclick={() => step(1)} disabled={session.collecting || session.frames.length === 0} aria-label="下一帧">|▶</button>
  <input
    type="range"
    min="0"
    max={Math.max(session.frames.length - 1, 0)}
    value={session.idx}
    oninput={(e) => seek(Number(e.currentTarget.value))}
    disabled={session.collecting || session.frames.length === 0}
    aria-label="帧滑条"
  />
  <span class="frame-count">帧 {session.idx + 1}/{session.frames.length}</span>
  {#each FPS_STEPS as f (f)}
    <button type="button" class="btn ghost" class:selected={session.fps === f} onclick={() => setFps(f)}>{f}</button>
  {/each}
</div>

<label class="cap-row">
  采集帧预算
  <input type="number" min="100" max="200000" step="1000" value={session.cap} onchange={(e) => setCap(Number(e.currentTarget.value))} />
  （原 demo 硬上限 4000 已改可配——引擎侧无此上限；到顶只提示不静默截断）
</label>

<style>
  .cap-row { display: block; margin-top: 10px; font-size: 12px; color: var(--t3); }
  .cap-row input { width: 90px; background: var(--field); color: var(--t1); border: 1px solid var(--hairline); border-radius: 5px; padding: 3px 7px; font: 12px var(--mono); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; margin: 0 4px; }
</style>
