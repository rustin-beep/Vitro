<script lang="ts">
  // 运行输出块（工作态仪器最后一块）——stdout / stderr / note 三通道分域 +
  // Clang golden 徽章 + stdin 喂入行 + 返回码/步数/采集耗时统计行。
  //
  // 数据全部来自 session 层（outputs / golden / runStats / perf）；golden 判定
  // 在 lib/golden.ts 纯函数（末帧才判、改稿诚实失效）。
  // A17：note 通道的 [语义id] 徽章经 decorateBadges 装饰（输入先 esc）。
  import { feedStdin, session } from "../session.svelte.ts";
  import { decorateBadges, esc } from "../../js/util.ts";

  let showGolden = $state(false);

  const out = $derived(session.outputs);
  const bytes = (s: string): number => (s ? new TextEncoder().encode(s).length : 0);
  const emptyText = $derived(
    !session.compileOk
      ? "（编译失败——无运行输出）"
      : session.frames.length === 0 && session.perf.collectMs > 0
        ? "（零帧：程序无步进）"
        : "（尚未运行到 printf）",
  );
  const badgeClass = $derived(
    session.golden.kind === "ok" ? "is-ok" : session.golden.kind === "bad" ? "is-bad" : session.golden.kind === "pending" ? "is-warn" : "",
  );
  const ret = $derived(session.runStats && session.runStats.status === "finished" ? String(session.runStats.return_value) : "—");
</script>

<section class="vr-block" aria-label="运行输出">
  <div class="vr-blockhead">
    <h2 class="vr-label">输出</h2>
    <span class="vr-badge {badgeClass}" title="运行到末帧自动对照 Clang golden">{session.golden.label}</span>
    <span class="vr-spacer"></span>
    <span class="vr-meta">Clang golden 预置真值</span>
  </div>

  <pre class="vr-out" class:is-empty={!out.stdout}>{out.stdout || emptyText}</pre>
  {#if out.stderr}
    <pre class="vr-out is-stderr">{out.stderr}</pre>
  {/if}
  {#if out.note}
    <pre class="vr-out is-note">{@html decorateBadges(esc(out.note))}</pre>
  {/if}

  <div class="vr-channels">
    <span>stdout <b>{bytes(out.stdout)} B</b></span>
    <span>stderr <b>{bytes(out.stderr)} B</b></span>
    <span>note <b>{bytes(out.note)} B</b></span>
  </div>

  {#if session.runStats?.waiting_input}
    <div class="vr-stdin-row">
      <label for="vr-stdin">stdin</label>
      <input id="vr-stdin" type="text" bind:value={session.stdinDraft} aria-label="标准输入（喂给 scanf）" />
      <button type="button" class="vr-btn vr-tiny" onclick={feedStdin} disabled={session.collecting}>
        {session.collecting ? "续跑中…" : "喂入并续跑"}
      </button>
      <span class="vr-meta">waiting_input = true · 喂入后全量重采</span>
    </div>
  {/if}

  {#if session.golden.detail}
    <div class="vr-golden">
      <button type="button" class="vr-golden-toggle" aria-expanded={showGolden} onclick={() => (showGolden = !showGolden)}>
        {showGolden ? "收起对照真值" : "对照真值（Clang golden / Vitro stdout）"}
      </button>
      {#if showGolden}
        <pre class="vr-golden-pre">{session.golden.detail}</pre>
      {/if}
    </div>
  {/if}

  <div class="vr-statline">
    返回码 <b>{ret}</b> · VM 步 <b>{session.runStats ? String(session.runStats.steps_executed) : "—"}</b>{#if session.perf.collectMs}{" · "}采集 <b>{session.perf.collectMs} ms</b>{/if}
  </div>
</section>
