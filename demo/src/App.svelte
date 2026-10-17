<script lang="ts">
  // Vitro 前端试点 App（F4 布局对齐版，2026-10-16 用户拍板「布局一样即可，
  // 控件细节后续按优」）：骨架对齐现役 demo——header（品牌+徽章+齿轮设置
  // 浮层）/ 两栏 grid（左=pane-head 按钮排+blurb+编辑器+偏好折叠段；
  // 右=下划线 tab 条[内容/运行/内存地图/诊断手册/引擎与协议]+tabpage）/
  // footer 白箱声明。tab 集合与命名逐字对齐 index.html data-tab。
  import { boot, collect, frameAt, loadCatalog, loadProto, session } from "./session.svelte.ts";
  import { DEFAULT_PROGRAM } from "./program.ts";
  import { themeState, applyTheme, NIGHT_THEMES } from "./theme.svelte.ts";
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
  import Editor from "./lib/Editor.svelte";
  import CatalogView from "./lib/CatalogView.svelte";
  import ProtoView from "./lib/ProtoView.svelte";
  import DiagnosticsCard from "./lib/DiagnosticsCard.svelte";
  import StepInfoCard from "./lib/StepInfoCard.svelte";
  import CallStackChain from "./lib/CallStackChain.svelte";
  import WorkspaceBar from "./lib/WorkspaceBar.svelte";
  import { ensureClosedForLesson, saveActiveFile, syncSource, workspace } from "./lib/workspace.svelte.ts";
  import SessionConfig from "./lib/SessionConfig.svelte";
  import RunMeta from "./lib/RunMeta.svelte";
  import Toasts from "./lib/Toasts.svelte";
  import type { TreeLesson } from "./lib/courseTypes.ts";
  import { toast } from "./toasts.svelte.ts";
  import { loadLessonNote } from "./lib/lessonNotes.ts";
  import { DEMO_CASES } from "virtual:demo-globals";
  // V10（#141）：品牌位真 logo（昼夜双变体随主题族切换——替代「◎」文本点）
  import iconDark from "../assets/logo/vitro-icon-dark.svg?url";
  import iconLight from "../assets/logo/vitro-icon-light.svg?url";

  let source = $state(DEFAULT_PROGRAM);
  let editorRef: Editor | null = $state(null);
  let blurb = $state("");
  let note = $state<{ title: string; blocks: import("./lib/lessonMd.ts").Block[] } | null>(null);
  let settingsOpen = $state(false);
  // 引擎加载失败面（#139）：旧栈 boot-error 红横幅形态——失败必须可感知，
  // 禁止徽章停在「…」占位的静默假态
  let bootError = $state("");

  async function onPickLesson(l: TreeLesson, chapId: string): Promise<void> {
    // 点课 = 离开工作区（旧栈 ensureClosedForLesson 语义）：dirty 时 confirm
    // 保存后关闭；用户取消则整个选课动作中止
    if (!(await ensureClosedForLesson())) return;
    source = l.source; // 课源码载入编辑器（旧栈 setEditorSource 语义）
    blurb = l.blurb;
    // A7/A6/A3 单源锚（#140）：从 DEMO_CASES 反查原用例（golden 预置真值 /
    // configHint / argv）；算法课无 case 记录 → 退化形态（无 ref，source
    // 锚仍在——修改失效逻辑照常工作）
    const base = DEMO_CASES.find((k) => k.id === l.id);
    session.currentCase = base
      ? {
          id: base.id,
          label: base.label,
          source: base.source,
          referenceOutput: base.referenceOutput as string | undefined,
          referenceTrap: base.referenceTrap as string | undefined,
          referenceKind: base.referenceKind as string | undefined,
          configHint: base.configHint as Record<string, unknown> | undefined,
          argv: base.argv as string[] | undefined,
          files: base.files as Array<{ filename: string; source: string }> | undefined,
        }
      : { id: l.id, label: l.title, source: l.source };
    // 叙述懒加载（import.meta.glob ?url 交付格式——全量课程不压首屏包）；
    // 无此课叙述 = null 不渲染面板（诚实空态）
    const doc = await loadLessonNote(chapId + "/" + l.id);
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
      shareUrl = url; // A23：链接条常驻（含长度提示与复制钮）
      if (url.length > SHARE_URL_WARN) toast("info", urlLenWarning(url.length));
      else toast("ok", "分享链接已生成（地址栏复制即可）");
    } catch (err) {
      toast("err", "分享失败：" + String((err as Error).message));
    }
  }

  boot()
    .then(() => Promise.all([loadCatalog(), loadProto()]))
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
    })
    .catch((err: unknown) => {
      // #139：boot 链必须有失败面——横幅 + 采集禁用（对齐旧栈 boot-error
      // 形态：失败原因 + wasm-gc 浏览器支持指引）
      bootError = (err instanceof Error ? err.message : String(err)).slice(0, 200);
    });
  applyTheme(migrateTheme(storeGet(KEYS.theme)) || "glass");

  function tabSwitch(id: TabId): void {
    switchTab(id);
  }

  // 工作区缓冲同步（F4 残留②）：编辑器 source 任何变化（键入/点课/分享还原/
  // 文件切换）都落进 active 文件缓冲——dirty 追踪的单一同步点
  $effect(() => {
    syncSource(source);
  });

  // Ctrl+S 保存当前文件（工作区开时才劫持——旧栈 initWorkspace 语义）
  $effect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if (!workspace.active) return;
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        void saveActiveFile();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  });

  // 关页兜底：dirty 时浏览器原生「离开页面？」提示（用户拍板的退出防护形态）
  $effect(() => {
    const onBeforeUnload = (e: BeforeUnloadEvent): void => {
      if (workspace.dirty) { e.preventDefault(); e.returnValue = ""; }
    };
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  });

  // 回放跟随当前行（A13，#140）：帧 code_line 驱动编辑器中性 accent 行染
  // + 就近滚动（不居中不抢焦——播放节奏不被打断）。采集期不跟随（源码
  // 可能正被替换）。
  $effect(() => {
    const line = frameAt(session.idx)?.code_line;
    if (line && line > 0 && !session.collecting) editorRef?.followLine(line);
  });

  // vis_events 左缘标记（A14，#140）：当前帧事件行集 → 编辑器 accent 竖条
  // （visLines 派生此前零消费——死派生在此接线）。
  $effect(() => {
    if (session.collecting) return;
    editorRef?.setVisLines([...session.visLines]);
  });

  // A20（#140）：schema 冻结徽章（旧栈 cap-badge 同语义——title 挂受控词
  // 表 kind 数）。capabilities 未载时不渲染。
  const schemaInfo = $derived.by(() => {
    const schema = ((session.capabilities ?? {}) as Record<string, unknown>).schema as Record<string, unknown> | undefined;
    if (!schema) return null;
    return { version: String(schema.version ?? "—"), frozen: String(schema.frozen_at ?? "—") };
  });
  const labelKinds = $derived(String(((session.capabilities ?? {}) as Record<string, unknown>).semantic_label_kinds ?? "—"));

  // A23（#140）：分享链接条（生成后常驻——剪贴板被拒时它是唯一手动复制出口）
  let shareUrl = $state("");
  async function copyShare(): Promise<void> {
    try {
      await navigator.clipboard.writeText(shareUrl);
      toast("ok", "已复制到剪贴板");
    } catch {
      toast("err", "剪贴板不可用——请在链接条中手动全选复制");
    }
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
    <img class="logo" src={NIGHT_THEMES.has(themeState.current) ? iconDark : iconLight} alt="Vitro" width="22" height="22" />
    <b>Vitro</b>
    <span class="sub">教学 C 子集引擎 · 全 MoonBit · wasm-gc 单出口</span>
  </div>
  <div class="head-right">
    <!-- A21（#140）：文档站 / GitHub 外链（旧栈 .links .icon-link 同款图标） -->
    <a class="icon-btn" href="./docs/current/02-构建与上手/快速入门.html" target="_blank" rel="noopener" title="文档站（快速入门）">
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 7c-1.2-1.6-3.1-2.5-5.2-2.5H3.5V18h4.3c1.9 0 3.3.7 4.2 2 1-1.3 2.3-2 4.2-2h4.3V4.5h-3.3C15.1 4.5 13.2 5.4 12 7z"/><path d="M12 7v13"/></svg>
    </a>
    <a class="icon-btn" href="https://github.com/rustin-beep/Vitro" target="_blank" rel="noopener" title="GitHub 仓库">
      <svg viewBox="0 0 16 16" width="20" height="20" aria-hidden="true" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
    </a>
    <span class="badge">engine <b>{session.versions.engine || "…"}</b></span>
    <span class="badge">protocol <b>{session.versions.protocol || "…"}</b></span>
    {#if schemaInfo}
      <span class="badge" title={`semantic_label_kinds=${labelKinds}`}>schema <b>{schemaInfo.version}</b>（冻结于 {schemaInfo.frozen}）</span>
    {/if}
    <button type="button" class="icon-btn" onclick={cycleTheme} title="切换主题">◐</button>
    <button type="button" class="icon-btn" data-settings class:on={settingsOpen} onclick={() => (settingsOpen = !settingsOpen)} title="界面设置" aria-haspopup="true" aria-expanded={settingsOpen}>
      <!-- V3 质感批（#141）：⚙ 文本字符 → 旧栈滑杆 SVG（style.css settings-toggle 同款） -->
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><line x1="21" y1="4" x2="14" y2="4"/><line x1="10" y1="4" x2="3" y2="4"/><line x1="21" y1="12" x2="12" y2="12"/><line x1="8" y1="12" x2="3" y2="12"/><line x1="21" y1="20" x2="16" y2="20"/><line x1="12" y1="20" x2="3" y2="20"/><line x1="14" y1="2" x2="14" y2="6"/><line x1="8" y1="10" x2="8" y2="14"/><line x1="16" y1="18" x2="16" y2="22"/></svg>
    </button>
  </div>
</header>

{#if settingsOpen}
  <div class="settings-float">
    <SettingsView />
  </div>
{/if}

{#if bootError}
  <div class="boot-error" role="alert">
    <b>引擎加载失败</b>——{bootError}。本页需要支持 wasm-gc 与 js-string builtins
    的现代浏览器（Chrome/Edge 130+、Firefox 134+）；请检查网络后刷新重试。
  </div>
{/if}

<main class="pilot-grid" class:replaying-wide={session.playing && session.replayWide}>
  <section class="pane editor-pane">
    <div class="pane-head">
      <button type="button" class="btn" onclick={() => collect(source, editorRef?.getBpLines() ?? [])} disabled={session.collecting || !!bootError} title={bootError ? "引擎未加载——见上方提示" : ""}>
        {session.collecting ? "采集中…" : "▶ 采集帧流"}
      </button>
      <button type="button" class="btn ghost" onclick={share} disabled={session.collecting}>分享链接</button>
      <span class="pill" class:busy={session.collecting} class:err={!!session.stopped}>
        {session.collecting ? "采集中" : session.stopped ? "受检终止" : "就绪"}
      </span>
    </div>
    {#if blurb}<p class="blurb">{blurb}</p>{/if}
    {#if shareUrl}
      <div class="share-row">
        <input class="share-out" readonly value={shareUrl} onfocus={(e) => e.currentTarget.select()} aria-label="分享链接" />
        <span class="share-len">{shareUrl.length} 字符</span>
        <button type="button" class="btn ghost" onclick={copyShare}>复制</button>
      </div>
    {/if}
    <WorkspaceBar onswitch={(_path, src) => (source = src)} />
    <div class="editor-wrap">
      <Editor bind:source bind:this={editorRef} disabled={session.collecting} />
    </div>
    <p class="perf-line">
      采集 {session.perf.collectMs}ms
      {#if session.perf.replayPerFrameUs}· 回放 {session.perf.replayPerFrameUs}µs/帧（flushSync 口径）{/if}
    </p>
    <p class="status-line">{session.status}</p>
    {#if session.stopped}
      <!-- 位置拍板 2026-10-17：死因全文详报框归位「运行」视图（RunMeta 顶部
           pane 框内）——左栏只留单行摘要指引，不再撑爆编辑器区 -->
      <div class="stopped-note">
        {session.stopped.split("\n")[0]}{session.stopped.includes("\n") ? "……" : ""}——{session.stopped.startsWith("受检终止") ? "死因详报见「运行」视图" : ""}
      </div>
    {/if}
    <SessionConfig />
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
        <DiagnosticsCard onjump={(ln) => editorRef?.revealLine(ln)} />
        <RunMeta source={source} />
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
        <div class="tree-head">
          <h2 class="tab-h">调用树（visited = 当前帧已走路径）</h2>
          <StepInfoCard source={source} />
        </div>
        <CallTree tree={session.tree} idx={session.idx} />
        <h2 class="tab-h">局部变量</h2>
        <VarsList />
        <h2 class="tab-h">调用栈</h2>
        <CallStackChain />
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
        <p class="proto-line">engine <b>{session.versions.engine}</b> · protocol <b>{session.versions.protocol}</b> —— wasm-gc 单出口，invoke 字符串通道（canonicalize 口径）。</p>
        <ProtoView />
      </div>
    {/if}
  </section>
</main>

<footer class="pilot-foot">
  <p>白箱引擎：内存映射、freed/隔离区、VM 步数、诊断全部来自引擎真实数据（memory.regions / output.delta / error_catalog / trap 帧），非装饰性 mock。</p>
  <p>参考输出为 Clang golden 预置真值；时间旅行（step 流回放 + 调用树 + 数组动画）已上线「运行」视图——trap 类程序与结构可视化的引擎能力缺口见 issue 台账。</p>
</footer>

<Toasts />
