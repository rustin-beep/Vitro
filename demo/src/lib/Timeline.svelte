<script lang="ts">
  // 执行时间轴（设计稿 P1-1 / P2-9 / P3-3 / A-5 / B-1）：
  //   - 双刻度：语句级按 5 帧一刻度、指令级按 50 条一刻度；指针/已播放段
  //     与画面帧同源（session.viewFrames）；
  //   - 末帧终态三件套：指针 100% + 按钮「⟲ 重播」+ endflag 实心 + 状态行；
  //   - 交换刻度（本稿新增）：数组快照发生变化的帧在轴下打一枚小琥珀刻，
  //     一眼看见「交换发生在哪几帧」；
  //   - 悬停读数（本稿新增）：指针扫过标尺时给「第 k 帧 · line L · 语句」，
  //     点击即跳——仪器刻度尺而不是盲拖；
  //   - 键盘仪表盘：空格播放/暂停、←/→ 单步、Home/End 首末帧（全局键盘
  //     处理在 App，本块只给提示）。
  import { seek, session, setFps, setGran, step, togglePlay } from "../session.svelte.ts";
  import { lessonSession } from "./lessonSession.svelte.ts";
  import { sceneBand, sceneIndexAt, sceneRangeLabel } from "./scenes.ts";

  const FPS_STEPS = [2, 8, 30, 60, 120, 240];
  const FPS_NOTE: Record<number, string> = { 2: " · 很慢", 8: " · 默认", 30: " · 快", 60: " · 高速", 120: " · 极快", 240: " · 极快" };

  let { source }: { source: string } = $props();

  const n = $derived(session.viewFrames.length);
  const idx = $derived(Math.min(session.idx, Math.max(n - 1, 0)));
  const pct = $derived(n > 1 ? (idx / (n - 1)) * 100 : 0);
  const ended = $derived(n > 0 && idx >= n - 1);

  // 本课分镜（scene 真源 = lesson.md；未迁移课 = []，整条分幕面不渲染）。
  // 未采集（n=0）时不给「当前幕」：帧流还不存在，idx 0 落在第一幕坐标里
  // 会被误读成「已到第 1 幕」。
  const scenes = $derived(lessonSession.note?.scenes ?? []);
  const cur = $derived(n > 0 ? sceneIndexAt(scenes, idx) : -1);
  const bands = $derived(scenes.map((s) => ({ id: s.id, ...sceneBand(s, n) })));

  // 刻度步长按**标尺实际宽度**自适应：固定 5 帧在 540 帧的长程序里会把
  // 108 个刻度标签糊成一条黑带（390 实测）。目标 ≈ 每 48px 一个标签，
  // 步长从 1/2/5/10/20/25/50/100… 的整齐数列里取。
  let rulerW = $state(0);
  const tickStep = $derived.by(() => {
    if (n <= 1) return 1;
    const want = Math.max(4, Math.min(12, Math.floor((rulerW || 560) / 48)));
    const raw = Math.ceil((n - 1) / want);
    const nice = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000, 10000];
    return nice.find((s) => s >= raw) ?? raw;
  });
  const ticks = $derived.by(() => {
    if (n === 0) return [] as Array<{ i: number; at: number; major: boolean }>;
    const out: Array<{ i: number; at: number; major: boolean }> = [];
    for (let i = 0; i < n; i += tickStep) out.push({ i, at: n > 1 ? (i / (n - 1)) * 100 : 0, major: true });
    return out;
  });

  /** 交换刻度：相邻可视帧的数组元素文本发生变化 → 该帧打刻。
   *  长程序里交换可能上千次——超过 80 枚就不画（避免刻度带变噪点带）。 */
  const events = $derived.by(() => {
    const frames = session.viewFrames;
    if (frames.length < 2) return [] as number[];
    const out: number[] = [];
    let prevSig = "";
    frames.forEach((f, i) => {
      const sig = (f.array_snapshots ?? []).map((s) => s.name + ":" + s.elements.join(",")).join("|");
      if (i > 0 && sig !== prevSig && sig !== "") out.push(i);
      prevSig = sig;
    });
    return out.length > 80 ? [] : out;
  });

  const lineText = $derived.by(() => {
    const f = session.viewFrames[idx];
    if (!f) return "";
    if (!(f.code_line > 0)) return "程序收尾 · 无当前语句";
    const text = source.split("\n")[f.code_line - 1]?.trim() ?? "";
    return `line ${f.code_line}${text ? " · " + text : ""}`;
  });

  // ── 悬停读数 ──────────────────────────────────────────────
  let hover = $state<{ x: number; i: number } | null>(null);
  function frameAtX(px: number, width: number): number {
    if (width <= 0 || n === 0) return 0;
    const ratio = Math.max(0, Math.min(1, px / width));
    return Math.round(ratio * (n - 1));
  }
  const hoverInfo = $derived.by(() => {
    if (!hover || n === 0) return null;
    const f = session.viewFrames[hover.i];
    if (!f) return null;
    const text = source.split("\n")[f.code_line - 1]?.trim() ?? "";
    return { i: hover.i, line: f.code_line, text };
  });

  function playLabel(): string {
    if (session.playing) return "❚❚ 暂停";
    if (ended) return "⟲ 重播";
    if (idx > 0) return "▶ 继续";
    return "▶ 播放";
  }
  function onPlay(): void {
    if (session.playing) { togglePlay(); return; }
    if (ended) seek(0);
    togglePlay();
  }
  const playTitle = $derived(session.playing ? "暂停（空格）" : ended ? "从第一帧重播（空格）" : "从当前帧播放（空格）");
  const playIcon = $derived(session.playing ? "pause" : ended ? "replay" : "play");
</script>

<section class="vr-block vr-timeline" class:is-ended={ended} class:is-playing={session.playing} aria-label="执行时间轴">
  <div class="vr-blockhead">
    <h2 class="vr-label">执行时间轴</h2>
    <span class="vr-meta">{n ? `第 ${idx + 1} / ${n} 帧` : "未采集"}</span>
    <div class="vr-timeline-tools">
      <div class="vr-seg vr-grain" role="group" aria-label="粒度">
        <button type="button" class:is-active={session.gran === "stmt"} onclick={() => setGran("stmt")}>语句级</button>
        <button type="button" class:is-active={session.gran === "insn"} onclick={() => setGran("insn")}>指令级</button>
      </div>
      <select class="vr-select" aria-label="播放速度（帧/秒）" value={session.fps} onchange={(e) => setFps(Number(e.currentTarget.value))}>
        {#each FPS_STEPS as f (f)}
          <option value={f}>{f} 帧/秒{FPS_NOTE[f] ?? ""}</option>
        {/each}
      </select>
    </div>
  </div>

  {#if scenes.length > 0}
    <div class="vr-beats" role="group" aria-label="本课分镜">
      {#each scenes as s, i (s.id)}
        <button
          type="button"
          class="vr-beat"
          class:is-active={i === cur}
          class:is-done={i < cur}
          onclick={() => seek(s.from)}
          disabled={n === 0}
          title="{s.title} · {sceneRangeLabel(s)}"
          aria-current={i === cur ? "step" : undefined}
        >
          <span class="vr-beat-no">{s.id}</span>{s.title}
        </button>
      {/each}
    </div>
    {#if cur >= 0}
      <p class="vr-beats-note">
        <b>{scenes[cur].title}</b>
        {#if scenes[cur].note} · {scenes[cur].note}{/if}
        <span class="vr-beat-range">{sceneRangeLabel(scenes[cur])}</span>
      </p>
    {/if}
  {/if}

  {#if n > 0 && bands.length > 0}
    <div class="vr-bands" aria-hidden="true">
      {#each bands as b, i (b.id)}
        <span class="vr-band" class:is-active={i === cur} class:is-done={i < cur} style:left="{b.left}%" style:width="{b.width}%"></span>
      {/each}
    </div>
  {/if}

  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="vr-ruler"
    bind:clientWidth={rulerW}
    onmousemove={(e) => {
      const r = e.currentTarget.getBoundingClientRect();
      hover = { x: e.clientX - r.left, i: frameAtX(e.clientX - r.left, r.width) };
    }}
    onmouseleave={() => (hover = null)}
  >
    <div class="vr-axis"></div>
    <div class="vr-ticks">
      {#each ticks as t (t.i)}
        <span class="vr-tick is-major" style:left="{t.at}%"></span>
        <span class="vr-tick-label" class:is-first={t.i === 0} style:left="{t.at}%">{t.i}</span>
      {/each}
    </div>
    <div class="vr-played" style:width="{pct}%"></div>
    {#each events as ev (ev)}
      <span class="vr-event" class:is-current={ev === idx} style:left="{n > 1 ? (ev / (n - 1)) * 100 : 0}%" title="第 {ev + 1} 帧 · 数组值发生变化"></span>
    {/each}
    <div class="vr-pointer" style:left="{pct}%"></div>
    <div class="vr-endflag"><span>{Math.max(n - 1, 0)}</span></div>
    {#if hoverInfo}
      <div class="vr-scrub" style:left="{n > 1 ? Math.max(3, Math.min(97, (hoverInfo.i / (n - 1)) * 100)) : 50}%">
        第 <b>{hoverInfo.i + 1}</b> 帧 · line {hoverInfo.line}{hoverInfo.text ? ` · ${hoverInfo.text.slice(0, 34)}` : ""}
      </div>
    {/if}
    <input
      class="vr-seek"
      type="range"
      min="0"
      max={Math.max(n - 1, 0)}
      value={idx}
      oninput={(e) => seek(Number(e.currentTarget.value))}
      disabled={n === 0}
      aria-label="帧滑条" title="拖动到任意帧"
    />
  </div>
  <p class="vr-grain-note">
    {#if session.gran === "stmt"}语句级：一帧 = 一条可读语句；时间轴与画面帧同源。{:else}指令级：一帧 = 一条 VM 指令（共 {n} 条）；画面按语句边界取样。{/if}
  </p>

  <div class="vr-transport">
    <button type="button" class="vr-iconbtn vr-transport-btn" onclick={() => seek(0)} disabled={n === 0} title="第一帧（Home）" aria-label="第一帧">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M6 5v14M18 6l-9 6 9 6z"/></svg>
    </button>
    <button type="button" class="vr-iconbtn vr-transport-btn" onclick={() => step(-1)} disabled={n === 0} title="上一帧（←）" aria-label="上一帧">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M15 6l-7 6 7 6z"/></svg>
    </button>
    <button type="button" class="vr-btn vr-primary vr-playbtn" data-act="play" onclick={onPlay} disabled={n === 0} title={playTitle} aria-label={playTitle}>
      {#if playIcon === "pause"}
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5h3v14H8zM13 5h3v14h-3z"/></svg>
      {:else if playIcon === "replay"}
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M4 5v5h5"/><path d="M4.5 10a8 8 0 1 1 1.2 6"/></svg>
      {:else}
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5.5v13l10-6.5z"/></svg>
      {/if}
      {playLabel()}
    </button>
    <button type="button" class="vr-iconbtn vr-transport-btn" onclick={() => step(1)} disabled={n === 0} title="下一帧（→）" aria-label="下一帧">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M9 6l7 6-7 6z"/></svg>
    </button>
    <button type="button" class="vr-iconbtn vr-transport-btn" onclick={() => seek(n - 1)} disabled={n === 0} title="末帧（End）" aria-label="末帧">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M18 5v14M6 6l9 6-9 6z"/></svg>
    </button>
    <span class="vr-readout">{lineText || "—"}</span>
    <span class="vr-endnote">末帧 {Math.max(n - 1, 0)}</span>
  </div>

  <div class="vr-keys" aria-hidden="true">
    <span><kbd class="vr-kbd">空格</kbd>播放/暂停</span>
    <span><kbd class="vr-kbd">←</kbd><kbd class="vr-kbd">→</kbd>单步</span>
    <span><kbd class="vr-kbd">Home</kbd><kbd class="vr-kbd">End</kbd>首/末帧</span>
    <span><kbd class="vr-kbd">[</kbd><kbd class="vr-kbd">]</kbd>速度</span>
  </div>
</section>
