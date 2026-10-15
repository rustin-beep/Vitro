<script lang="ts">
  // Vitro 前端试点 App（F4 布局对齐版，2026-10-16 用户拍板「布局一样即可，
  // 控件细节后续按优」）：骨架对齐现役 demo——header（品牌+徽章+齿轮设置
  // 浮层）/ 两栏 grid（左=pane-head 按钮排+blurb+编辑器+偏好折叠段；
  // 右=下划线 tab 条[内容/运行/内存地图/诊断手册/引擎与协议]+tabpage）/
  // footer 白箱声明。tab 集合与命名逐字对齐 index.html data-tab。
  import { boot, collect, frameAt, loadCatalog, session } from "./session.svelte.ts";
  import { DEFAULT_PROGRAM } from "./program.ts";
  import { themeState, applyTheme } from "./theme.svelte.ts";
  import { KEYS, storeGet, storeSet, migrateTheme } from "./persisted.svelte.ts";
  import { packSource, parseFragment, unpackSource, urlLenWarning, SHARE_URL_WARN } from "../js/share.ts";
  import { activeTab, switchTab, TAB_DEFS, type TabId } from "./tabs.svelte.ts";
  import ArrayBars from "./lib/ArrayBars.svelte";
  import ReplayBar from "./lib/ReplayBar.svelte";
  import VarsList from "./lib/VarsList.svelte";
  import OutputView from "./lib/OutputView.svelte";
  import CallTree from "./lib/CallTree.svelte";
  import MemoryView from "./lib/MemoryView.svelte";
  import CourseTree from "./lib/CourseTree.svelte";
  import CourseNote from "./lib/CourseNote.svelte";
  import SettingsView from "./lib/SettingsView.svelte";
  import CatalogView from "./lib/CatalogView.svelte";
  import Toasts from "./lib/Toasts.svelte";
  import type { TreeLesson } from "./lib/courseTypes.ts";
  import { toast } from "./toasts.svelte.ts";
  import { LESSON_NOTES } from "./lib/lessonNotes.ts";

  let source = $state(DEFAULT_PROGRAM);
  let blurb = $state("");
  let note = $state<{ title: string; blocks: import("./lib/lessonMd.ts").Block[] } | null>(null);
  let settingsOpen = $state(false);

  function onPickLesson(l: TreeLesson, chapId: string): void {
    source = l.source; // 课源码载入编辑器（旧栈 setEditorSource 语义）
    blurb = l.blurb;
    const doc = LESSON_NOTES[chapId + "/" + l.id];
    note = doc ? { title: l.title, blocks: doc.blocks } : null;
    switchTab("run"); // 点课即切运行视图（旧栈 collectCurrentEditor+切 tab 语义）
    void collect(source); // 点课自动采集（旧栈 collectCurrentEditor 语义）
  }

  function cycleTheme(): void {
    const next = themeState.current === "glass" || themeState.current === "soft" ? "ice" : "glass";
    applyTheme(next);
    storeSet(KEYS.theme, next);
  }

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
  applyTheme(migrateTheme(storeGet(KEYS.theme)) || "glass");

  function tabSwitch(id: TabId): void {
    switchTab(id);
  }
</script>

<svelte:document onclick={(e) => {
  // 点浮层外关闭（齿轮与浮层本体豁免——齿轮 onclick 先 toggle，document 冒泡在后只做判定）
  if (!settingsOpen) return;
  const t = e.target as HTMLElement | null;
  if (!t?.closest(".settings-float") && !t.closest("[data-settings]")) settingsOpen = false;
}} />
<svelte:window onkeydown={(e) => {
  if (e.key === "Escape") settingsOpen = false;
}} />

<header class="pilot-head">
  <div class="brand">
    <span class="logo">◎</span>
    <b>Vitro</b>
    <span class="sub">教学 C 子集引擎 · 全 MoonBit · wasm-gc 单出口</span>
  </div>
  <div class="head-right">
    <span class="badge">engine <b>{session.versions.engine || "…"}</b></span>
    <span class="badge">protocol <b>{session.versions.protocol || "…"}</b></span>
    <button type="button" class="icon-btn" onclick={cycleTheme} title="切换主题">◐</button>
    <button type="button" class="icon-btn" data-settings class:on={settingsOpen} onclick={() => (settingsOpen = !settingsOpen)} title="设置">⚙</button>
  </div>
</header>

{#if settingsOpen}
  <div class="settings-float">
    <SettingsView />
  </div>
{/if}

<main class="pilot-grid">
  <section class="pane editor-pane">
    <div class="pane-head">
      <button type="button" class="btn" onclick={() => collect(source)} disabled={session.collecting}>
        {session.collecting ? "采集中…" : "▶ 采集帧流"}
      </button>
      <button type="button" class="btn ghost" onclick={share} disabled={session.collecting}>分享链接</button>
      <span class="pill" class:busy={session.collecting} class:err={!!session.stopped}>
        {session.collecting ? "采集中" : session.stopped ? "受检终止" : "就绪"}
      </span>
    </div>
    {#if blurb}<p class="blurb">{blurb}</p>{/if}
    <div class="editor-wrap">
      <textarea id="src-box" bind:value={source} spellcheck="false" aria-label="C 源码"></textarea>
    </div>
    <p class="perf-line">
      采集 {session.perf.collectMs}ms
      {#if session.perf.replayPerFrameUs}· 回放 {session.perf.replayPerFrameUs}µs/帧（flushSync 口径）{/if}
    </p>
    {#if session.stopped}
      <div class="stopped-note">{session.stopped}</div>
    {/if}
    <details class="pref">
      <summary>偏好（主题 / 字号 / 动效 / 采集预算）</summary>
      <SettingsView />
    </details>
  </section>

  <section class="pane">
    <div class="tabs" role="tablist" aria-label="内容区">
      {#each TAB_DEFS as t (t.id)}
        <button type="button" role="tab" aria-selected={activeTab.current === t.id} class="tab" class:active={activeTab.current === t.id} onclick={() => tabSwitch(t.id)}>{t.label}</button>
      {/each}
    </div>

    {#if activeTab.current === "content"}
      <div class="tabpage">
        <p class="tab-desc">课程档案——章节树导航。点击课程载入示例并自动采集回放；状态环标记已完成，数据全部引擎侧机判产物。</p>
        <CourseTree onpick={onPickLesson} />
        {#if note}
          <CourseNote title={note.title} blocks={note.blocks} />
        {/if}
      </div>
    {:else if activeTab.current === "run"}
      <div class="tabpage">
        <h2 class="tab-h">数组可视化（keyed FLIP · 多数组）</h2>
        {#each frameAt(session.idx)?.array_snapshots ?? [] as s (s.name)}
          <div class="av-item">
            <div class="av-name">{s.name} : {s.element_ty}</div>
            <ArrayBars snap={s} />
          </div>
        {:else}
          <p class="muted">（此帧无数组快照）</p>
        {/each}
        <ReplayBar />
        <h2 class="tab-h">调用树（visited = 当前帧已走路径）</h2>
        <CallTree tree={session.tree} idx={session.idx} />
        <h2 class="tab-h">局部变量</h2>
        <VarsList />
        <h2 class="tab-h">运行输出（stdout / stderr / note）</h2>
        <OutputView />
      </div>
    {:else if activeTab.current === "mem"}
      <div class="tabpage">
        <h2 class="tab-h">内存地图（会话结束态 · malloc/free/UAF）</h2>
        <MemoryView />
      </div>
    {:else if activeTab.current === "cat"}
      <div class="tabpage">
        <h2 class="tab-h">诊断手册</h2>
        <CatalogView />
      </div>
    {:else if activeTab.current === "proto"}
      <div class="tabpage">
        <h2 class="tab-h">引擎与协议</h2>
        <p class="proto-line">engine <b>{session.versions.engine}</b> · protocol <b>{session.versions.protocol}</b> —— wtparams：wasm-gc 单出口，invoke 字符串通道（canonicalize 口径）；capabilities/contracts 面板随 F4 后续刀接入。</p>
      </div>
    {/if}
  </section>
</main>

<footer class="pilot-foot">
  <p>白箱引擎：内存映射、freed/隔离区、VM 步数、诊断全部来自引擎真实数据（memory.regions / output.delta / error_catalog / trap 帧），非装饰性 mock。</p>
  <p>参考输出为 Clang golden 预置真值；时间旅行（step 流回放 + 调用树 + 数组动画）已上线「运行」视图——trap 类程序与结构可视化的引擎能力缺口见 issue 台账。</p>
</footer>

<Toasts />
