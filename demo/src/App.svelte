<script lang="ts">
  // Vitro 前端试点 App（F1）——最小验收面：源码编辑 + Worker 采集 +
  // 数组柱（FLIP）+ 重放条 + 变量表。对拍钩子（?bench=1）见 main.ts。
  import { boot, collect, session } from "./session.svelte.ts";
  import { DEFAULT_PROGRAM } from "./program.ts";
  import ArrayBars from "./lib/ArrayBars.svelte";
  import ReplayBar from "./lib/ReplayBar.svelte";
  import VarsList from "./lib/VarsList.svelte";

  let source = $state(DEFAULT_PROGRAM);

  boot();
</script>

<header class="pilot-head">
  <h1>Vitro 前端试点 · Svelte 5 + Vite</h1>
  <span class="badge">engine <b>{session.versions.engine || "…"}</b></span>
  <span class="badge">protocol <b>{session.versions.protocol || "…"}</b></span>
  <span class="meta">引擎在 Web Worker（主线程只渲染）· 帧预算可配</span>
</header>

<div class="pilot-grid">
  <section class="pane">
    <h2>源码（C 子集）</h2>
    <textarea id="src-box" bind:value={source} spellcheck="false" aria-label="C 源码"></textarea>
    <div class="status-line">
      <button type="button" class="btn" onclick={() => collect(source)} disabled={session.collecting}>
        {session.collecting ? "采集中…" : "采集帧流"}
      </button>
      <span class:warn={!!session.stopped}>{session.status}</span>
    </div>
    {#if session.stopped}
      <div class="stopped-note">{session.stopped}</div>
    {/if}
    <p class="perf-line">
      采集 {session.perf.collectMs}ms
      {#if session.perf.replayPerFrameUs}· 回放 {session.perf.replayPerFrameUs}µs/帧（flushSync 口径）{/if}
    </p>
  </section>

  <section class="pane">
    <h2>数组可视化（keyed FLIP）</h2>
    <ArrayBars />
    <ReplayBar />
  </section>

  <section class="pane">
    <h2>局部变量</h2>
    <VarsList />
  </section>
</div>
