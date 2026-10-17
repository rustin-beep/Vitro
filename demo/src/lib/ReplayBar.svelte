<script lang="ts">
  // 重放条——播放/暂停/单步/滑条 seek/帧计数/播放帧率档位/采集预算。
  // 全部状态与动作来自 session 层，本组件零私有状态。
  // A10（#140）：步号跳转——本地帧集内按 step_index 定位（引擎级 step.seek
  // 超出本地采集范围的场景不存在：帧集即引擎 step 流全量；超界 fail loud）。
  import { session, seek, step, togglePlay, setFps, setCap, setGran } from "../session.svelte.ts";
  import { toast } from "../toasts.svelte.ts";

  const GRAN_STEPS: Array<{ id: "stmt" | "insn"; label: string }> = [{ id: "stmt", label: "语句级" }, { id: "insn", label: "指令级" }];

  const FPS_STEPS = [2, 8, 30, 60, 120, 240]; // A24（#140）：六档同旧栈

  let seekStep = $state("");
  function doSeek(): void {
    const n = Math.round(Number(seekStep));
    if (!Number.isFinite(n) || seekStep.trim() === "") return;
    const i = session.viewFrames.findIndex((f) => f.step_index === n);
    if (i < 0) {
      const maxStep = session.viewFrames.length ? session.viewFrames[session.viewFrames.length - 1].step_index : 0;
      toast("err", `步号 ${n} 不在本次采集范围（至步 ${maxStep}）——语句级视图为组尾步号`);
      return;
    }
    seek(i);
    seekStep = "";
  }
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
  <span class="frame-count">帧 {session.idx + 1}/{session.viewFrames.length}</span>
  <span class="eng-seek">
    <input
      type="number"
      min="1"
      bind:value={seekStep}
      placeholder="步号"
      aria-label="步号跳转"
      disabled={session.collecting || session.frames.length === 0}
      onkeydown={(e) => { if (e.key === "Enter") doSeek(); }}
    />
    <button type="button" class="btn ghost" onclick={doSeek} disabled={session.collecting || session.frames.length === 0}>跳转</button>
  </span>
  <div class="seg gran" role="radiogroup" aria-label="粒度">
    {#each GRAN_STEPS as g (g.id)}
      <button type="button" class:selected={session.gran === g.id} onclick={() => setGran(g.id)}>{g.label}</button>
    {/each}
  </div>
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
  .gran { display: inline-flex; border: 1px solid var(--hairline); border-radius: 7px; overflow: hidden; }
  .gran button { background: var(--pane); color: var(--t2); border: 0; padding: 4px 10px; font: 12px var(--font-ui); cursor: pointer; }
  .gran button + button { border-left: 1px solid var(--hairline); }
  .gran button.selected { background: var(--accent-tint); color: var(--accent-strong); }
  .cap-row { display: block; margin-top: 10px; font-size: 12px; color: var(--t3); }
  .cap-row input { width: 90px; background: var(--field); color: var(--t1); border: 1px solid var(--hairline); border-radius: 5px; padding: 3px 7px; font: 12px var(--mono); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; margin: 0 4px; }
  .eng-seek { display: inline-flex; align-items: center; gap: 4px; }
  .eng-seek input { width: 72px; background: var(--field); color: var(--t1); border: 1px solid var(--hairline); border-radius: 5px; padding: 3px 7px; font: 12px var(--mono); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
</style>
