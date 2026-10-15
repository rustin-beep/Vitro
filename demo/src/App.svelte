<script lang="ts">
  // Vitro 前端试点 App（F1）——最小验收面：源码编辑 + Worker 采集 +
  // 数组柱（FLIP）+ 重放条 + 变量表。对拍钩子（?bench=1）见 main.ts。
  import { boot, collect, frameAt, loadCatalog, session } from "./session.svelte.ts";
  import { DEFAULT_PROGRAM } from "./program.ts";
  import { themeState, applyTheme } from "./theme.svelte.ts";
  import { KEYS, storeGet, storeSet, migrateTheme } from "./persisted.svelte.ts";
  import { packSource, parseFragment, unpackSource, urlLenWarning, SHARE_URL_WARN } from "../js/share.ts";
  import ArrayBars from "./lib/ArrayBars.svelte";
  import ReplayBar from "./lib/ReplayBar.svelte";
  import VarsList from "./lib/VarsList.svelte";
  import Toasts from "./lib/Toasts.svelte";
  import SettingsView from "./lib/SettingsView.svelte";
  import CatalogView from "./lib/CatalogView.svelte";
  import { toast } from "./toasts.svelte.ts";

  let source = $state(DEFAULT_PROGRAM);

  function cycleTheme(): void {
    // 夜↔日对切（theme-toggle 语义）；主题状态单一源在 theme 层
    const next = themeState.current === "glass" || themeState.current === "soft" ? "ice" : "glass";
    applyTheme(next);
    storeSet(KEYS.theme, next);
  }

  // 分享（旧栈 doShare 语义平移：纯函数物理保留自 js/share.ts，UI 面新写）
  async function share(): Promise<void> {
    try {
      const frag = await packSource(source);
      const url = location.href.split("#")[0] + "#" + frag;
      history.replaceState(null, "", url);
      if (url.length > SHARE_URL_WARN) toast("info", urlLenWarning(url.length));
      else toast("ok", "分享链接已生成（地址栏复制即可）");
    } catch (err) {
      toast("err", "分享失败：" + String((err as Error).message));
    }
  }

  boot()
    .then(() => loadCatalog())
    .then(async () => {
    // 分享链接消费（旧栈 applySharedSource 语义：不可信输入只填编辑器，
    // 点了「运行」才编译；坏链接走 toast 不被就绪覆盖——分域红利）
    const parsed = parseFragment(location.hash.slice(1));
    if (parsed.kind === "payload") {
      try {
        source = await unpackSource(parsed.payload);
        toast("ok", "已从分享链接还原代码");
      } catch (err) {
        toast("err", "分享链接不完整——" + String((err as Error).message).slice(0, 60));
      }
    }
  });

  boot();
  applyTheme(migrateTheme(storeGet(KEYS.theme)) || "glass"); // 与防闪脚本对齐（脚本已设，此处幂等）
</script>

<header class="pilot-head">
  <h1>Vitro 前端试点 · Svelte 5 + Vite</h1>
  <span class="badge">engine <b>{session.versions.engine || "…"}</b></span>
  <span class="badge">protocol <b>{session.versions.protocol || "…"}</b></span>
  <span class="meta">引擎在 Web Worker（主线程只渲染）· 帧预算可配</span>
  <button type="button" class="btn ghost" onclick={cycleTheme} title="切换主题">◐ {themeState.current}</button>
</header>

<div class="pilot-grid">
  <section class="pane">
    <h2>源码（C 子集）</h2>
    <textarea id="src-box" bind:value={source} spellcheck="false" aria-label="C 源码"></textarea>
    <div class="status-line">
      <button type="button" class="btn" onclick={() => collect(source)} disabled={session.collecting}>
        {session.collecting ? "采集中…" : "采集帧流"}
      </button>
      <button type="button" class="btn ghost" onclick={share} disabled={session.collecting}>分享</button>
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
    <h2>数组可视化（keyed FLIP · 多数组）</h2>
    {#each frameAt(session.idx)?.array_snapshots ?? [] as s (s.name)}
      <div class="av-item">
        <div class="av-name">{s.name} : {s.element_ty}</div>
        <ArrayBars snap={s} />
      </div>
    {:else}
      <p class="muted">（此帧无数组快照）</p>
    {/each}
    <ReplayBar />
  </section>

  <section class="pane">
    <h2>局部变量</h2>
    <VarsList />
  </section>

  <section class="pane">
    <h2>设置</h2>
    <SettingsView />
  </section>

  <section class="pane">
    <h2>诊断手册</h2>
    <CatalogView />
  </section>
</div>

<Toasts />
