<script lang="ts">
  // 工作态 · 左仪右书（2026-10-18 反馈④：编码功能已上线，编辑器放右、仪器
  // 模式页放左——左导航右编辑的 IDE 习惯；设计稿 v4 的左右在本次对调）。
  //   左：仪器（执行 / 内存 / 协议三模式）——诊断带、时间轴、索引格、调用树、
  //       局部变量、输出（执行模式）；内存地图；引擎与协议。
  //   右：课页（课号/课名/目标 → 运行条 → 代码 → 实验参数）+ 课文。
  //
  // 状态单点：源码来自 lessonSession（App 经 bind 下发），会话态来自 session，
  // 导航态来自 ui。组件不直摸 Worker / documentElement。
  import { collect, frameAt, resetSession, session } from "../session.svelte.ts";
  import { packSource, urlLenWarning, SHARE_URL_WARN } from "../../js/share.ts";
  import { toast } from "../toasts.svelte.ts";
  import { ui, setMode } from "../ui.svelte.ts";
  import { lessonSession } from "../lib/lessonSession.svelte.ts";
  import { progress } from "../lib/progress.svelte.ts";
  import { syncSource, workspace } from "../lib/workspace.svelte.ts";
  import Editor from "../lib/Editor.svelte";
  import Timeline from "../lib/Timeline.svelte";
  import ArrayCells from "../lib/ArrayCells.svelte";
  import CallTree from "../lib/CallTree.svelte";
  import VarsList from "../lib/VarsList.svelte";
  import OutputView from "../lib/OutputView.svelte";
  import DiagBand from "../lib/DiagBand.svelte";
  import MemoryView from "../lib/MemoryView.svelte";
  import ProtoView from "../lib/ProtoView.svelte";
  import CourseNote from "../lib/CourseNote.svelte";
  import WorkspaceBar from "../lib/WorkspaceBar.svelte";
  import SessionConfig from "../lib/SessionConfig.svelte";

  let { source = $bindable("") }: { source: string } = $props();

  let editorRef: Editor | null = $state(null);
  let shareUrl = $state("");

  /** 数据面帧（末帧收尾帧沿用最近一帧有数据的帧；块头标注沿用来源）。 */
  const dataIdx = $derived(session.displayIdx);
  const dataFrame = $derived(frameAt(dataIdx));
  const heldFrom = $derived(dataIdx !== session.idx ? dataIdx : -1);
  const snaps = $derived(dataFrame?.array_snapshots ?? []);
  const n = $derived(session.viewFrames.length);
  const lesson = $derived(lessonSession.lesson);
  const errCount = $derived(session.diagnostics.filter((d) => d.severity === "error").length);
  const ended = $derived(n > 0 && session.idx >= n - 1);
  const waiting = $derived(!!session.runStats?.waiting_input);

  const kicker = $derived(
    lesson
      ? `课 ${String(lesson.ordinal).padStart(2, "0")} · ${lesson.chapLabel} · ${lesson.kind === "case" ? "case" : lesson.kind}`
      : "分享 · 自由代码",
  );
  const lede = $derived(
    lesson
      ? lesson.kind === "case"
        ? lesson.blurb
        : `「${lesson.chapLabel}」里的一课：点「运行」采集帧流，左侧逐帧看数组、调用栈与变量。`
      : "从分享链接还原的自由代码——没有预置 golden；可编辑后点「运行」重新采集。",
  );
  const elementCount = $derived(snaps.reduce((s, x) => s + x.elements.length, 0));

  const statusText = $derived(
    session.collecting
      ? "采集中 · 编译 + run + step 闭环"
      : !session.compileOk
        ? session.status || "编译失败——诊断见诊断带"
        : session.playing
        ? `播放中 · ${session.fps} 帧/秒`
        : ended
          ? "末帧 · 可拖回任意帧"
          : n > 0
            ? `已暂停 · 第 ${session.idx + 1} / ${n} 帧`
            : session.stopped
              ? session.stopped.split("\n")[0]
              : "未采集 —— 点「运行」从头采集",
  );
  const statusCls = $derived(session.playing || session.collecting ? "is-live" : ended ? "is-end" : "");

  const codeName = $derived(
    workspace.activePath
      ? workspace.activePath.split("/").pop() || workspace.activePath
      : session.currentCase?.files?.length
        ? session.currentCase.files[0].filename
        : "main.c",
  );
  const codeStatus = $derived(
    !session.compileOk
      ? `编译期 ${errCount} 错误`
      : session.diagnostics.length
        ? `${session.diagnostics.length} 条编译期诊断 · 断点 ${session.breakpoints.length}`
        : `编译期无诊断 · 断点 ${session.breakpoints.length}`,
  );
  const codeDotCls = $derived(!session.compileOk || errCount ? "is-bad" : session.diagnostics.length ? "is-warn" : "");

  const argvLabel = $derived(session.argvText.trim() || (session.currentCase?.argv?.join(" ") ?? "") || "—");
  const stdinLabel = $derived(waiting ? session.stdinDraft : "—");
  const filesLabel = $derived(
    workspace.active
      ? `${workspace.files.length} 文件`
      : session.currentCase?.files?.length
        ? `${session.currentCase.files.length} 文件`
        : "main.c ×1",
  );

  async function run(): Promise<void> {
    await collect(source, editorRef?.getBpLines() ?? []);
  }
  function reset(): void {
    lessonSession.restoreOriginal();
    resetSession();
    toast("info", "已重置：帧流清空，源码回到本课原文");
  }
  // ⚠️ 浮层开关必须在 await 之前同步置位（#184）：onDocClick（document 冒泡）
  // 的设计假设是「触发器先 toggle，冒泡判定在后」——真实点击时 Svelte 委托
  //（#app）回调栈清空后有微任务检查点，packSource 载荷小、压缩在微任务内
  // 完成，await 续体在 document 冒泡【之前】就跑——浮层开关若写在 await 后，
  // 会被随后的 onDocClick 当「点外」关掉（合成 click 单栈同步派发无检查点，
  // 故 E2E/合成事件测不出——真实输入路径盲区）。async 段只负责算 URL。
  function share(): void {
    ui.shareOpen = true;
    void doShare();
  }
  async function doShare(): Promise<void> {
    try {
      const frag = await packSource(source);
      const url = location.href.split("#")[0] + "#" + frag;
      history.replaceState(null, "", url);
      shareUrl = url;
      if (url.length > SHARE_URL_WARN) toast("info", urlLenWarning(url.length));
    } catch (err) {
      toast("err", "分享失败：" + String((err as Error).message));
      ui.shareOpen = false; // 打开失败不留空浮层
    }
  }
  async function copyShare(): Promise<void> {
    try {
      await navigator.clipboard.writeText(shareUrl);
      toast("ok", "已复制到剪贴板");
    } catch {
      toast("err", "剪贴板不可用——请在链接框中手动全选复制");
    }
  }
  function clearBpAndRun(): void {
    session.breakpoints = [];
    void run();
  }

  // 工作区缓冲同步（dirty 追踪单一同步点）+ golden 活值（改稿即诚实失效）
  $effect(() => {
    syncSource(source);
    session.liveSource = source;
  });
  // 回放跟随当前行 + vis_events 左缘标记（采集期不跟随——源码可能正被替换）
  $effect(() => {
    const line = frameAt(session.idx)?.code_line;
    if (line && line > 0 && !session.collecting) editorRef?.followLine(line);
  });
  $effect(() => {
    if (session.collecting) return;
    editorRef?.setVisLines([...session.visLines]);
  });
  // 「继续上次」记帧（去抖；播放中不写——暂停/末帧/离开时落盘）
  let saveTimer: ReturnType<typeof setTimeout> | undefined;
  $effect(() => {
    const l = lessonSession.lesson;
    const i = session.idx;
    const total = session.viewFrames.length;
    if (!l || session.playing) return;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => progress.rememberFrame(l.id, l.chapId, i, total), 700);
    return () => clearTimeout(saveTimer);
  });
</script>

<main class="vr-bench">
  <section class="vr-instrument" aria-label="执行仪器">
    <nav class="vr-modes" aria-label="仪器模式">
      <button type="button" class="vr-mode" class:is-active={ui.mode === "exec"} onclick={() => setMode("exec")}>执行</button>
      <button type="button" class="vr-mode" class:is-active={ui.mode === "mem"} onclick={() => setMode("mem")}>内存</button>
      <button type="button" class="vr-mode" class:is-active={ui.mode === "proto"} onclick={() => setMode("proto")}>协议</button>
      <span class="vr-mode-meta">{session.gran === "insn" ? "指令级" : "语句级"}</span>
    </nav>

    {#if ui.mode === "exec"}
      <DiagBand onjump={(ln) => editorRef?.revealLine(ln)} />
      <Timeline {source} />
      {#if snaps.length > 0}
        {#each snaps as s, si (s.name + "#" + si)}
          <ArrayCells snap={s} frame={dataFrame} before={dataIdx > 0 ? frameAt(dataIdx - 1) : undefined} heldFrom={heldFrom} {source} />
        {/each}
      {:else}
        <section class="vr-block" aria-label="数组可视化">
          <div class="vr-blockhead"><h2 class="vr-label">数组</h2><span class="vr-spacer"></span><span class="vr-meta">本帧无数组快照</span></div>
          <p class="vr-empty">{n ? "（此帧没有数组下标访问）" : "（采集后显示数组索引格）"}</p>
        </section>
      {/if}
      <CallTree tree={session.tree} idx={session.idx} {source} />
      <VarsList idx={dataIdx} heldFrom={heldFrom} />
      <OutputView />
    {:else if ui.mode === "mem"}
      <MemoryView />
    {:else}
      <ProtoView />
    {/if}
  </section>

  <div class="vr-left">
    <section class="vr-page" aria-label="课页">
      <div class="vr-kicker">{kicker}</div>
      <h1 class="vr-title">{lessonSession.title}</h1>
      <p class="vr-lede">
        {lede}
        <span class="vr-stat">{n ? `${n} 帧` : "未采集"}</span> ·
        <span class="vr-stat">{elementCount} 个元素</span> ·
        <span class="vr-stat">{session.golden.label}</span>
      </p>

      <div class="vr-runbar">
        <button
          type="button"
          class="vr-btn vr-primary"
          data-act="run"
          onclick={run}
          disabled={session.collecting || !session.booted}
          title={session.booted ? "从头采集帧流（编译 + run + step 闭环）" : "引擎未就绪——装载失败，见顶部横幅"}
        >
          <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5.5v13l10-6.5z"/></svg>
          {session.collecting ? "采集中…" : "运行"}
        </button>

        <div class="vr-wrap" data-share-wrap>
          <button type="button" class="vr-btn" data-act="share" aria-haspopup="dialog" aria-expanded={ui.shareOpen} onclick={share} disabled={session.collecting}>分享</button>
          {#if ui.shareOpen}
            <div class="vr-popover" role="dialog" aria-label="分享链接">
              <div class="vr-pophead">
                <span>分享链接</span>
                <button type="button" class="vr-iconbtn" aria-label="关闭分享" onclick={() => (ui.shareOpen = false)}>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>
                </button>
              </div>
              <input class="vr-search vr-share-input" readonly value={shareUrl} onfocus={(e) => e.currentTarget.select()} aria-label="分享链接" />
              <div class="vr-poprow">
                <span class="vr-popnote" style="margin:0">{shareUrl.length} 字符 · {shareUrl.length > SHARE_URL_WARN ? "超长，聊天工具可能截断" : "只含源码"}</span>
                <button type="button" class="vr-btn vr-tiny" onclick={copyShare}>复制</button>
              </div>
              <p class="vr-popnote">不上传、不经第三方。链接坏了会<b>明确报错</b>，不静默退回默认示例。</p>
            </div>
          {/if}
        </div>

        <button type="button" class="vr-btn" data-act="reset" onclick={reset} disabled={session.collecting} title="清空帧流并把源码回到本课原文">重置</button>
        <span class="vr-status {statusCls}" aria-live="polite">{statusText}</span>
      </div>

      {#if session.bpPaused}
        <div class="vr-banner is-amber" role="status">
          <div><b>断点暂停</b><span>{session.stopped.replace(/^⏸\s*/, "")} —— 第 {session.idx + 1} / {Math.max(n, 1)} 帧</span></div>
          <button type="button" class="vr-btn vr-tiny" onclick={clearBpAndRun}>清除断点并重采</button>
        </div>
      {/if}

      <div class="vr-code">
        <div class="vr-codehead">
          <span>{codeName}</span>
          <span><span class="vr-dot {codeDotCls}"></span>{codeStatus}</span>
        </div>
        <div class="vr-codebody">
          <Editor bind:source bind:this={editorRef} disabled={session.collecting || waiting} />
        </div>
      </div>

      <div class="vr-params">
        <span class="vr-params-label">实验参数</span>
        <button type="button" class="vr-chip" class:is-on={!!session.argvText.trim()} onclick={() => (ui.paramsOpen = true)} title="命令行参数（argv）">argv {argvLabel}</button>
        <button type="button" class="vr-chip" class:is-on={waiting} onclick={() => (ui.paramsOpen = true)} title="标准输入（stdin）">stdin {stdinLabel}</button>
        <span class="vr-chip" title="编译单元">文件 {filesLabel}</span>
        <WorkspaceBar onswitch={(_p, src) => (source = src)} />
        <button type="button" class="vr-linkbtn" aria-expanded={ui.paramsOpen} onclick={() => (ui.paramsOpen = !ui.paramsOpen)}>{ui.paramsOpen ? "收起" : "展开"}</button>
      </div>
      {#if ui.paramsOpen}
        <SessionConfig />
      {/if}
    </section>

    <article class="vr-note vr-note-page" aria-label="课文">
      {#if lessonSession.note}
        <CourseNote title={lessonSession.note.title} blocks={lessonSession.note.blocks} page />
      {:else}
        <p class="vr-note-empty">
          {lesson ? `此课尚无叙述真源（course/${lesson.chapId}/${lesson.id}/lesson.md 未入库）——源码可直接运行；叙述入库后此处自动出现课文。` : "分享的代码没有课文——它是别人写好的一段 C，直接运行读帧流即可。"}
        </p>
      {/if}
    </article>
  </div>
</main>
