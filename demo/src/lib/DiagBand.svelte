<script lang="ts">
  // 诊断带（工作态仪器顶端）：默认**单行摘要**（编译 ✓ · 运行 ✓ · golden
  // 待末帧），有异常/用户展开才显示明细——设计稿 B3 收口；编译期/运行期
  // 分栏陈述，两种红不并排（P3-5）。
  //
  // 一句话诊断条（反馈②）：编译失败时只留第一条 error：E 码 + 位置 + 消息 +
  // 「查看诊断手册 ↗」——点进参考态对应条目（真实 error_catalog 条目）。
  // trap 详报（P2-10 + 2026-10-18 反馈）：运行期受检终止**就地**给出
  // 「示意图 → 码表条目及其内容 → 引擎原文」，不再要求跳手册才能看懂；
  // 红只属运行期。
  import { session } from "../session.svelte.ts";
  import { showRef, ui } from "../ui.svelte.ts";
  import { esc, formatTrap } from "../../js/util.ts";
  import CodeCard from "./CodeCard.svelte";
  import { canonicalCode } from "./catalogDetail.ts";

  let { onjump }: { onjump?: (line: number) => void } = $props();

  let showTrace = $state(false);
  let showRaw = $state(false);

  /** trap 详报里的 E 码（formatTrap 产物）→ 诊断手册（事件委托）。 */
  function onTrapClick(e: MouseEvent): void {
    const t = (e.target as HTMLElement).closest("[data-ecode]");
    if (t) showRef(t.getAttribute("data-ecode")!);
  }

  const errCount = $derived(session.diagnostics.filter((d) => d.severity === "error").length);
  const warnCount = $derived(session.diagnostics.filter((d) => d.severity === "warning").length);
  const ecode = $derived.by(() => {
    const m = /([EW]\d{4})/.exec(session.stopped);
    return m ? m[1] : "";
  });
  const hasCode = (c: string): boolean => session.catalog.some((x) => x.code_str === c);
  const first = $derived(session.firstError);
  const firstCard = $derived(first ? session.catalog.find((c) => c.code_str === canonicalCode(first.code, hasCode)) ?? null : null);
  const trapCard = $derived(ecode ? session.catalog.find((c) => c.code_str === canonicalCode(ecode, hasCode)) ?? null : null);

  const compileCls = $derived(!session.compileOk || errCount > 0 ? "is-bad" : warnCount > 0 ? "is-warn" : "is-ok");
  const compileText = $derived(
    !session.compileOk
      ? `编译 ✗${errCount ? ` ${errCount} 错误` : ""}`
      : errCount > 0
        ? `编译 ${errCount} 错误`
        : warnCount > 0
          ? `编译 ✓ ${warnCount} 警告`
          : session.diagnostics.length > 0
            ? `编译 ✓ ${session.diagnostics.length} 提示`
            : "编译 ✓",
  );
  const runtimeCls = $derived(session.trapped || !session.compileOk ? "is-bad" : session.bpPaused || session.runStats?.waiting_input ? "is-warn" : "is-ok");
  const runtimeText = $derived(
    !session.compileOk
      ? "运行 未开始"
      : session.trapped
      ? `运行期${ecode ? ` ${ecode}` : ""}`
      : session.bpPaused
        ? "运行 · 断点暂停"
        : session.runStats?.waiting_input
          ? "运行 · 等待输入"
          : session.collecting
            ? "运行 …"
            : "运行 ✓",
  );
  const goldenCls = $derived(session.golden.kind === "ok" ? "is-ok" : session.golden.kind === "bad" ? "is-bad" : "is-warn");
  const goldenText = $derived(
    session.golden.kind === "none"
      ? "golden —"
      : session.golden.kind === "stale"
        ? "golden 已改稿"
        : session.golden.kind === "pending"
          ? "golden 待末帧"
          : session.golden.kind === "ok"
            ? "golden ✓"
            : "golden ✗",
  );
</script>

<div class="vr-diag-summary">
  <button type="button" class="vr-diag-pill" aria-expanded={ui.diagOpen} onclick={() => (ui.diagOpen = !ui.diagOpen)}>
    <span class="vr-diag-item {compileCls}"><i class="vr-diag-dot"></i>{compileText}</span>
    <span class="vr-diag-item {runtimeCls}"><i class="vr-diag-dot"></i>{runtimeText}</span>
    <span class="vr-diag-item {goldenCls}"><i class="vr-diag-dot"></i>{goldenText}</span>
    <span class="vr-chev"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg></span>
  </button>

  {#if ui.diagOpen}
    <div class="vr-diag-detail">
      <span class="vr-diag-item {compileCls}"><i class="vr-diag-dot"></i>编译期 · {session.diagnostics.length ? `${session.diagnostics.length} 条诊断` : "无诊断"}</span>
      <span class="vr-diag-item {runtimeCls}"><i class="vr-diag-dot"></i>{session.stopped || (session.frames.length ? "运行期 · 未触发异常" : "运行期 · 未采集")}</span>
      <span class="vr-diag-item {goldenCls}"><i class="vr-diag-dot"></i>{session.golden.label}</span>
    </div>
  {/if}
</div>

{#if first}
  <div class="vr-diag-error">
    <span class="vr-diag-code">{first.code}</span>
    {#if onjump && first.line > 0}
      <button type="button" class="vr-diag-loc" title="跳到 {first.filename || 'main.c'} 第 {first.line} 行" onclick={() => onjump(first.line)}>{first.filename || "main.c"} 行 {first.line}:{first.column}</button>
    {:else}
      <span class="vr-diag-loc">{first.filename || "main.c"} 行 {first.line}:{first.column}</span>
    {/if}
    <span class="vr-diag-msg">{first.message}</span>
    <button type="button" class="vr-diag-jump" onclick={() => showRef(first.code)}>查看诊断手册 ↗</button>
    {#if first.fix_suggestion}<span class="vr-diag-fix">✚ {first.fix_suggestion}</span>{/if}
  </div>
  {#if firstCard}
    <div class="vr-diag-codecard">
      <CodeCard
        code={firstCard.code_str}
        icon={firstCard.icon}
        title={firstCard.title}
        explanation={firstCard.explanation}
        causes={firstCard.common_causes ?? []}
        onopen={() => showRef(firstCard.code_str)}
      />
    </div>
  {/if}
{/if}

{#if session.diagnostics.length > 0}
  <div class="vr-diag-list">
    {#each session.diagnostics.filter((d) => d !== first) as d, i (i)}
      <div class="vr-diag-row" class:is-error={d.severity === "error"}>
        <button type="button" class="c" title="在诊断手册中查看 {d.code}" onclick={() => showRef(d.code)}>{d.code}</button>
        {#if d.line > 0}
          <button type="button" class="loc" title="跳到 {d.filename || 'main.c'} 第 {d.line} 行" onclick={() => onjump?.(d.line)}>{d.filename || "main.c"} {d.line}:{d.column}</button>
        {:else}
          <span class="loc">{d.filename || "main.c"} {d.line}:{d.column}</span>
        {/if}
        <span class="m">{d.message}</span>
        {#if d.fix_suggestion}<span class="fx">✚ {d.fix_suggestion}</span>{/if}
      </div>
    {/each}
  </div>
{/if}

{#if session.trapped}
  <div class="vr-trap" role="alert">
    <div class="vr-trap-head">
      <i class="vr-diag-dot" style="background:currentColor"></i>
      <span>运行期 {ecode || "trap"} · 受检终止</span>
      {#if ecode}
        <button type="button" class="vr-linkbtn" onclick={() => showRef(ecode)}>在诊断手册中查看 ↗</button>
      {/if}
    </div>
    <!-- 先图标后码表：码表卡片（图标 + 码 + 标题，点击进详情）→ 短信息
         （说明 + 常见原因）→ 引擎原文。2026-10-18 反馈③：错误输出要能看到
         `icons-preview` 里的码表图标与码表内容，而不是一张自绘示意图。 -->
    {#if trapCard}
      <div class="vr-trap-codecard">
        <CodeCard
          code={trapCard.code_str}
          icon={trapCard.icon}
          title={trapCard.title}
          explanation={trapCard.explanation}
          causes={trapCard.common_causes ?? []}
          onopen={() => showRef(trapCard.code_str)}
        />
      </div>
    {:else}
      <p class="vr-trap-nocode">（该 trap 未映射到 error_catalog 条目——不编造码表内容；引擎原文见下。）</p>
    {/if}
    <details class="vr-trap-raw" bind:open={showRaw}>
      <summary>引擎原文（时间轴 / 原因 / 行列）</summary>
      <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions, a11y_no_noninteractive_element_interactions -->
      <pre class="vr-trap-body" onclick={onTrapClick} title="点击 E 码在诊断手册中查看">{@html formatTrap(esc(session.stopped))}</pre>
    </details>
  </div>
{/if}

{#if session.ppTrace.length > 0}
  <div class="vr-pp">
    <button type="button" class="vr-pp-toggle" aria-expanded={showTrace} onclick={() => (showTrace = !showTrace)}>
      宏展开轨迹（{session.ppTrace.length} 条） {showTrace ? "▾" : "▸"}
    </button>
    {#if showTrace}
      <pre class="vr-pp-body">{session.ppTrace.join("\n")}</pre>
    {/if}
  </div>
{/if}
