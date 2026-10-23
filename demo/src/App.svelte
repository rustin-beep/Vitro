<script lang="ts">
  // Vitro · C 执行观察台（2026-10-18 前端改造，设计稿 v4 落地）
  //
  // 信息架构（设计说明 §2）：三态 + 一手册 + 一目录——
  //   工作态（默认）/ 入口态（课程）/ 参考态（诊断手册）；
  //   顶栏任何页面都能切课程、进手册、换主题、开设置。
  // 本文件只做外壳：顶栏 / 加载态 / 横幅 / 页脚 / 键盘仪表盘 / 首访动线。
  // 屏幕内容在 screens/，课与源码在 lib/lessonSession。
  import { boot, loadCatalog, loadProto, seek, session, setFps, step, togglePlay } from "./session.svelte.ts";
  import { parseFragment, unpackSource } from "../js/share.ts";
  import { toast } from "./toasts.svelte.ts";
  import { progress } from "./lib/progress.svelte.ts";
  import { lessonSession } from "./lib/lessonSession.svelte.ts";
  import { saveActiveFile, workspace } from "./lib/workspace.svelte.ts";
  import { showEntry, showRef, showWork, setFocus, ui } from "./ui.svelte.ts";
  import { sceneIndexAt } from "./lib/scenes.ts";
  import { KEYS, storeGet, storeSet } from "./persisted.svelte.ts";
  import { NIGHT_THEMES, cycleTheme, initTheme, themeState } from "./theme.svelte.ts";
  import WorkScreen from "./screens/WorkScreen.svelte";
  import EntryScreen from "./screens/EntryScreen.svelte";
  import RefScreen from "./screens/RefScreen.svelte";
  import SettingsPopover from "./lib/SettingsPopover.svelte";
  import Toasts from "./lib/Toasts.svelte";
  // 品牌真 logo（V10 双变体随主题族切换；设计稿的方形 glyph 只是占位）
  import iconDark from "../assets/logo/vitro-icon-dark.svg?url";
  import iconLight from "../assets/logo/vitro-icon-light.svg?url";

  let bootError = $state("");
  let shareError = $state("");

  // 专注模式深链：?focus=1 首帧即专注（课堂投屏/录屏入口）；F/Esc 后续切换。
  // 只读 location，写入由下方 effect 单点（replaceState，不新增历史项）。
  if (typeof location !== "undefined" && new URLSearchParams(location.search).get("focus") === "1") {
    ui.focus = true;
  }

  // 主题/字号/动效引导（旧值迁移 + 落盘规范化）。旧 glass 用户收到一次说明。
  const rawTheme = storeGet(KEYS.theme);
  initTheme();
  if (rawTheme && rawTheme !== themeState.current && storeGet("vitro-theme-migrated") !== "1") {
    storeSet("vitro-theme-migrated", "1");
    const from = rawTheme === "glass" ? "深夜书房" : rawTheme === "light" ? "明亮" : rawTheme;
    const to = themeState.current === "blueprint" ? "夜航图" : themeState.current === "paper" ? "白天（纸）" : themeState.current;
    toast("info", `主题已迁移：旧「${from}」→「${to}」`);
  }

  const chapterLabel = $derived(lessonSession.lesson?.chapLabel ?? "");
  const lessonId = $derived(lessonSession.lesson?.id ?? "分享代码");
  const ctxRef = $derived(ui.refCode || session.catalog[0]?.code_str || "");
  const focusScenes = $derived(lessonSession.scenes);
  const focusSceneIdx = $derived(session.viewFrames.length ? sceneIndexAt(focusScenes, session.idx) : -1);
  const focusScene = $derived(focusSceneIdx >= 0 ? focusScenes[focusSceneIdx] : null);

  function startBoot(): void {
    bootError = "";
    ui.ready = false;
    boot()
      .then(() => Promise.all([loadCatalog(), loadProto()]))
      .then(async () => {
        const parsed = parseFragment(location.hash.slice(1));
        if (parsed.kind === "bad") {
          shareError = `${parsed.reason}——链接多半被聊天工具截断或手动改坏。已载入默认示例；当前内容未被覆盖。`;
          return;
        }
        if (parsed.kind === "payload") {
          try {
            lessonSession.setShared(await unpackSource(parsed.payload));
            toast("ok", "已从分享链接还原代码");
          } catch (err) {
            shareError = `载荷无法解压（${String((err as Error).message).slice(0, 80)}）——链接多半被截断。已载入默认示例。`;
          }
          return;
        }
        // ?autorun / ?bench 由 main.ts 的验收钩子接管（此处不抢跑）
        const q = new URLSearchParams(location.search);
        if (q.has("autorun") || q.has("bench")) return;
        // 首访动线：继续上次（同课）/ 默认 bubble，采到一帧后**暂停**（不自动播）
        await lessonSession.openInitial();
      })
      .finally(() => {
        // 测试观测面（与 main.ts 的 __pilot 同域）：记录 ready 翻态瞬间的帧数——
        // E2E F8「首访 shell 先行」用它判「ready 不等首课采集」，不再靠轮询抓瞬态
        // 窗口（CI 上采集快于轮询，锚会假红，2026-10-22 实锤）。
        (window as unknown as Record<string, unknown>).__readyFrames = session.frames.length;
        ui.ready = true;
      })
      .catch((err: unknown) => {
        bootError = (err instanceof Error ? err.message : String(err)).slice(0, 200);
      });
  }
  startBoot();

  // ── 键盘仪表盘（工作态专用；输入框/编辑器内不劫持） ──────────────
  const FPS_STEPS = [2, 8, 30, 60, 120, 240];
  function typingIn(t: HTMLElement | null): boolean {
    if (!t) return false;
    return !!t.closest(".cm-editor, input, textarea, select, [contenteditable='true'], .vr-popover");
  }
  function onKey(e: KeyboardEvent): void {
    if (e.key === "Escape") {
      if (ui.focus) {
        e.preventDefault();
        setFocus(false);
        return;
      }
      ui.settingsOpen = false;
      ui.shareOpen = false;
      return;
    }
    // 专注模式 F 进 / Esc 出（输入框/编辑器内不劫持——'f' 要能正常输入；
    // 只属于执行面：mem/proto 下 F 不生效，setFocus 亦有同一守卫）
    if (ui.screen === "work" && ui.mode === "exec" && (e.key === "f" || e.key === "F") && !typingIn(e.target as HTMLElement | null)) {
      e.preventDefault();
      setFocus(!ui.focus);
      return;
    }
    if (ui.screen !== "work" || ui.mode !== "exec") return;
    if (typingIn(e.target as HTMLElement | null)) return;
    if (session.viewFrames.length === 0) return;
    const last = session.viewFrames.length - 1;
    if (e.key === " ") {
      e.preventDefault();
      if (!session.playing && session.idx >= last) seek(0);
      togglePlay();
    } else if (e.key === "ArrowLeft") {
      e.preventDefault();
      step(-1);
    } else if (e.key === "ArrowRight") {
      e.preventDefault();
      step(1);
    } else if (e.key === "Home") {
      e.preventDefault();
      seek(0);
    } else if (e.key === "End") {
      e.preventDefault();
      seek(last);
    } else if (e.key === "[" || e.key === "]") {
      e.preventDefault();
      const i = Math.max(0, FPS_STEPS.indexOf(session.fps));
      setFps(FPS_STEPS[Math.max(0, Math.min(FPS_STEPS.length - 1, i + (e.key === "]" ? 1 : -1)))]);
    }
  }

  // 工作区快捷键 / 关页兜底（2026-10-18 改造批从旧 App 迁回：Ctrl+S 保存、
  // dirty 时浏览器原生离开提示——E2E W6/W7 依赖此单点）。
  $effect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if (!workspace.active) return;
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        void saveActiveFile();
      }
    };
    const onUnload = (e: BeforeUnloadEvent): void => {
      if (workspace.dirty) { e.preventDefault(); e.returnValue = ""; }
    };
    document.addEventListener("keydown", onKey);
    window.addEventListener("beforeunload", onUnload);
    return () => {
      document.removeEventListener("keydown", onKey);
      window.removeEventListener("beforeunload", onUnload);
    };
  });

  // 离开前落盘「上次看到哪」（去抖 effect 来不及跑）
  function persistFrame(): void {
    const l = lessonSession.lesson;
    if (!l) return;
    progress.rememberFrame(l.id, l.chapId, session.idx, session.viewFrames.length);
  }
  $effect(() => {
    const onHide = (): void => { if (document.visibilityState === "hidden") persistFrame(); };
    window.addEventListener("beforeunload", persistFrame);
    document.addEventListener("visibilitychange", onHide);
    return () => {
      window.removeEventListener("beforeunload", persistFrame);
      document.removeEventListener("visibilitychange", onHide);
    };
  });

  // 专注模式 URL 单点同步（?focus=1 可分享/可直达；replaceState 不污染历史）
  $effect(() => {
    const on = ui.focus;
    if (typeof location === "undefined") return;
    const u = new URL(location.href);
    if (on) u.searchParams.set("focus", "1");
    else u.searchParams.delete("focus");
    const next = u.pathname + u.search + u.hash;
    if (next !== location.pathname + location.search + location.hash) history.replaceState(null, "", next);
  });

  // 点浮层外关闭（齿轮/分享触发器先 toggle，document 冒泡在后只做判定）
  function onDocClick(e: MouseEvent): void {
    const t = e.target as HTMLElement | null;
    if (ui.settingsOpen && !t?.closest("[data-settings-wrap]")) ui.settingsOpen = false;
    if (ui.shareOpen && !t?.closest("[data-share-wrap]")) ui.shareOpen = false;
  }

  // 诊断手册深链：组件内已落到首条；此处仅保证 refCode 有值
  $effect(() => {
    if (ui.screen === "ref" && !ui.refCode && session.catalog.length) ui.refCode = session.catalog[0].code_str;
  });
</script>

<svelte:document onclick={onDocClick} />
<svelte:window onkeydown={onKey} />

<div class="vr-shell">
  <div class="vr-app">
    <header class="vr-masthead" class:is-focus={ui.focus && ui.screen === "work"}>
      <div class="vr-brand">
        <!-- 品牌真 logo（项目自有资产，昼夜双变体随主题族切换）——设计稿里的
             方形 V 字形只是占位 glyph，不替代品牌资产。 -->
        <img class="vr-logo" src={NIGHT_THEMES.has(themeState.current) ? iconDark : iconLight} alt="Vitro" width="26" height="26" />
        <span class="vr-wordmark">Vitro</span>
        {#if ui.focus && ui.screen === "work"}
          <span class="vr-focuslabel">FOCUS / LECTURE</span>
          <span class="vr-context">
            <b>{lessonSession.title}</b>
            {#if focusScene}<span class="vr-sep">/</span><span>第 {focusSceneIdx + 1} 幕 · {focusScene.title}</span>{/if}
          </span>
        {:else}
          <span class="vr-tagline">C 执行观察台</span>
          <span class="vr-context">
            {#if ui.screen === "work"}
              <span class="vr-sep">/</span><b>{chapterLabel || "自由代码"}</b><span class="vr-sep">/</span><span>{lessonId}</span>
            {:else if ui.screen === "entry"}
              <span class="vr-sep">/</span><b>课程目录</b>
            {:else}
              <span class="vr-sep">/</span><b>诊断手册</b><span class="vr-sep">/</span><span>{ctxRef}</span>
            {/if}
          </span>
        {/if}
      </div>

      <div class="vr-head-right">
        {#if ui.focus && ui.screen === "work"}
          <span class="vr-focusbadge">专注模式</span>
          <span class="vr-focusframe">第 {session.idx + 1} / {Math.max(session.viewFrames.length, 1)} 帧</span>
          <button type="button" class="vr-btn vr-tiny" onclick={() => setFocus(false)} title="退出专注（Esc）">退出专注 Esc</button>
        {:else}
        <div class="vr-engine" aria-label="引擎状态">
          <span><span class="vr-live"></span>引擎 <b>{session.versions.engine || "…"}</b></span>
          <span class="vr-hide-sm">协议 <b>{session.versions.protocol || "…"}</b></span>
          {#if session.catalog.length}<span class="vr-hide-sm">目录 <b>{session.catalog.length}</b></span>{/if}
        </div>

        {#if ui.screen === "work"}
          <button type="button" class="vr-coursebtn" onclick={showEntry} title="课程目录（任何页面都能换课）" aria-label="课程目录">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v18H6.5A2.5 2.5 0 0 1 4 18.5z"/><path d="M4 18.5A2.5 2.5 0 0 1 6.5 16H20"/></svg>
            <span>课程</span>
          </button>
          <button type="button" class="vr-manual" onclick={() => showRef("")} title="诊断手册（E 码 / trap 详报）">
            <span class="vr-manual-full">诊断手册</span><span class="vr-manual-mini">诊断</span>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M7 17L17 7M9 7h8v8"/></svg>
          </button>
        {:else}
          <button type="button" class="vr-coursebtn" onclick={showWork} title="返回实验台" aria-label="返回实验台">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M15 6l-7 6 7 6"/></svg>
            <span>返回实验台</span>
          </button>
          {#if ui.screen === "entry"}
            <button type="button" class="vr-manual" onclick={() => showRef("")} title="诊断手册">
              <span class="vr-manual-full">诊断手册</span><span class="vr-manual-mini">诊断</span>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M7 17L17 7M9 7h8v8"/></svg>
            </button>
          {:else}
            <button type="button" class="vr-manual" onclick={showEntry} title="课程目录">
              <span class="vr-manual-full">课程目录</span><span class="vr-manual-mini">课程</span>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M7 17L17 7M9 7h8v8"/></svg>
            </button>
          {/if}
        {/if}

        <button
          type="button"
          class="vr-iconbtn"
          data-theme-toggle
          onclick={() => { void cycleTheme(); }}
          title="切换主题（五套：明亮实验室 / 奶油手账 / 绒面深蓝 / 白天（纸） / 夜航图）"
          aria-label="切换主题"
        >
          {#if NIGHT_THEMES.has(themeState.current)}
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M4.8 4.8l1.4 1.4M17.8 17.8l1.4 1.4M19.2 4.8l-1.4 1.4M6.2 17.8l-1.4 1.4"/></svg>
          {:else}
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path d="M20 14.5A8.5 8.5 0 0 1 9.5 4 8.5 8.5 0 1 0 20 14.5z"/></svg>
          {/if}
        </button>

        <div class="vr-wrap" data-settings-wrap>
          <button
            type="button"
            class="vr-iconbtn"
            data-settings
            class:is-on={ui.settingsOpen}
            title="界面设置"
            aria-haspopup="dialog"
            aria-expanded={ui.settingsOpen}
            onclick={() => (ui.settingsOpen = !ui.settingsOpen)}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><path d="M3 6h11M18 6h3M3 12h4M11 12h10M3 18h9M16 18h5"/><circle cx="16" cy="6" r="2"/><circle cx="8" cy="12" r="2"/><circle cx="14" cy="18" r="2"/></svg>
          </button>
          {#if ui.settingsOpen}
            <SettingsPopover />
          {/if}
        </div>
        {/if}
      </div>
    </header>

    {#if bootError}
      <div class="vr-banner" role="alert">
        <div>
          <b>引擎加载失败</b>
          <span>{bootError}。本页需要支持 wasm-gc 与 js-string builtins 的现代浏览器（Chrome/Edge 130+、Firefox 134+）；采集已禁用。</span>
        </div>
        <button type="button" class="vr-btn vr-tiny" onclick={startBoot}>重试</button>
      </div>
    {/if}

    {#if shareError}
      <div class="vr-banner" role="alert">
        <div><b>分享链接无法还原</b><span>{shareError}</span></div>
        <button type="button" class="vr-btn vr-tiny" onclick={() => (shareError = "")}>知道了</button>
      </div>
    {/if}

    {#if ui.screen === "work"}
      <WorkScreen bind:source={lessonSession.source} />
    {:else if ui.screen === "entry"}
      <EntryScreen />
    {:else}
      <RefScreen />
    {/if}

    {#if !(ui.focus && ui.screen === "work")}
    <footer class="vr-foot">
      <p>白箱引擎：内存映射、freed 隔离区、VM 步数、诊断全部来自引擎真实数据（memory.regions / output.delta / error_catalog / trap 帧），非装饰性 mock。</p>
      <p>课程叙述真源：<b>course/**/lesson.md</b>；课目与计数由同一数据源渲染，不在页面里手写。</p>
    </footer>
    {/if}
  </div>
</div>

{#if (!session.booted || !ui.ready) && !bootError}
  <div class="vr-boot" role="status" aria-live="polite">
    <div class="vr-boot-inner">
      <div class="vr-boot-brand">
        <img class="vr-logo" src={NIGHT_THEMES.has(themeState.current) ? iconDark : iconLight} alt="Vitro" width="26" height="26" />
        <span class="vr-wordmark">Vitro</span>
      </div>
      <p class="vr-boot-title">正在装载实验台</p>
      <p class="vr-boot-sub">wasm 引擎约 0.9 MB · 协议握手 · 课程叙述按需加载</p>
      <div class="vr-boot-bar"><i></i></div>
      <div class="vr-boot-skel"><span></span><span></span><span></span></div>
    </div>
  </div>
{/if}

<Toasts />
