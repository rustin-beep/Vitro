<script lang="ts">
  // 编译诊断卡（F4 残留①：旧栈 run.ts renderDiagnostics / renderPpTrace 语义
  // 平移——severity 全集 error/warning/hint/info + 码 + 定位 + 消息 + 修复
  // 建议；文本插值自动转义，旧栈 esc 义务在此消失）。
  //
  // 两种出场形态：
  //   ① compileOk=false —— 卡片是编译失败的主反馈面（worker 回传诊断全集，
  //      状态行/toast 只做指引「见运行视图」）；
  //   ② compileOk=true 且 diagnostics 非空 —— warning/hint 随成功一并展示
  //      （旧栈 renderDiagnostics 在 ok 检查前调用，同语义）。
  //
  // 跳行（jumpy）：行号 > 0 的行渲染为真 button，点击经 onjump 回调上调
  // Editor.revealLine（组件不直摸编辑器实例——审阅 B-P2-11 store 正解的
  // 组件级形态：父层持有 editorRef，回调下发）。
  import { session } from "../session.svelte.ts";

  let { onjump }: { onjump?: (line: number) => void } = $props();

  let showTrace = $state(false);

  const errCount = $derived(session.diagnostics.filter((d) => d.severity === "error").length);
  const warnCount = $derived(session.diagnostics.filter((d) => d.severity === "warning").length);
  /** 采集过至少一次（perf.collectMs>0 或编译失败）——此前展示占位文案，
   *  不把「未采集」渲染成「无诊断」（两态不同义，禁混显）。 */
  const collected = $derived(session.perf.collectMs > 0 || !session.compileOk);
</script>

{#if !session.compileOk || session.diagnostics.length > 0 || collected}
  <section class="diag-card" class:failed={!session.compileOk} aria-label="编译诊断">
    <header class="dc-head">
      <span class="dc-title">编译诊断</span>
      {#if !session.compileOk}
        <span class="dc-badge err">编译失败</span>
      {/if}
      {#if errCount > 0}<span class="dc-badge err">{errCount} 错误</span>{/if}
      {#if warnCount > 0}<span class="dc-badge warn">{warnCount} 警告</span>{/if}
      {#if session.diagnostics.length > errCount + warnCount}
        <span class="dc-badge info">{session.diagnostics.length - errCount - warnCount} 提示</span>
      {/if}
    </header>

    {#if session.diagnostics.length === 0}
      {#if !session.compileOk}
        <p class="dc-empty err">编译失败（引擎未给出诊断文本——fail loud 于状态行）</p>
      {:else}
        <p class="dc-empty">无编译期诊断</p>
      {/if}
    {:else}
      <ul class="dc-list">
        {#each session.diagnostics as d, i (i)}
          <li>
            {#if d.line > 0 && onjump}
              <button type="button" class="diag {d.severity} jumpy" style:--i={i} onclick={() => onjump(d.line)} title="跳到 {d.filename || 'main.c'} 第 {d.line} 行">
                <span class="code">{d.code}</span>
                <span class="loc">{d.filename || "main.c"} 行 {d.line}:{d.column}</span>
                <span class="msg">{d.message}</span>
                {#if d.fix_suggestion}<span class="fix">✚ {d.fix_suggestion}</span>{/if}
              </button>
            {:else}
              <div class="diag {d.severity}" style:--i={i}>
                <span class="code">{d.code}</span>
                <span class="loc">{d.filename || "main.c"} 行 {d.line}:{d.column}</span>
                <span class="msg">{d.message}</span>
                {#if d.fix_suggestion}<span class="fix">✚ {d.fix_suggestion}</span>{/if}
              </div>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}

    {#if session.ppTrace.length > 0}
      <button type="button" class="dc-trace-toggle" onclick={() => (showTrace = !showTrace)} aria-expanded={showTrace}>
        宏展开轨迹（{session.ppTrace.length} 条） {showTrace ? "▾" : "▸"}
      </button>
      {#if showTrace}
        <div class="pp-trace">
          {#each session.ppTrace as t (t)}
            <div class="pp-line">{t}</div>
          {/each}
        </div>
      {/if}
    {/if}
  </section>
{:else}
  <p class="dc-idle">（点「采集帧流」后展示编译诊断）</p>
{/if}

<style>
  .diag-card { border: 1px solid var(--hairline); border-radius: 8px; background: var(--field, var(--pane)); margin: 4px 0 10px; overflow: hidden; }
  .diag-card.failed { border-color: var(--danger); }
  .dc-head { display: flex; align-items: center; gap: 8px; padding: 7px 12px; border-bottom: 1px solid var(--hairline); background: var(--pane); }
  .dc-title { font-size: 12.5px; color: var(--t2); }
  .dc-badge { font-size: 11px; padding: 1px 8px; border-radius: 10px; border: 1px solid var(--hairline); color: var(--t3); }
  .dc-badge.err { color: var(--danger); border-color: var(--danger); }
  .dc-badge.warn { color: var(--num); border-color: var(--num); }
  .dc-list { list-style: none; margin: 0; padding: 6px; max-height: 40vh; overflow: auto; }
  .dc-list li { margin: 0; }
  .diag { display: block; width: 100%; text-align: left; padding: 5px 10px; border-left: 3px solid var(--num); margin-bottom: 4px; background: var(--field, var(--pane)); border-radius: 0 6px 6px 0; border-top: 0; border-right: 0; border-bottom: 0; font: inherit; color: var(--t1); cursor: default; animation: dc-rise var(--t-base) var(--ease-out) backwards; animation-delay: min(calc(var(--i, 0) * 40ms), 280ms); }
  @keyframes dc-rise { from { opacity: 0; transform: translateY(3px); } to { opacity: 1; transform: none; } }
  .diag.jumpy { cursor: pointer; transition: background-color var(--t-fast) var(--ease-out); }
  .diag.jumpy:hover { background: var(--accent-tint); }
  .diag.jumpy .loc { text-decoration: underline dotted; text-underline-offset: 2px; }
  .diag.error { border-left-color: var(--danger); }
  .diag.warning { border-left-color: var(--num); }
  .diag.hint, .diag.info { border-left-color: var(--t3); }
  .diag .code { font-family: var(--mono); color: var(--num); margin-right: 8px; font-size: 12px; font-variant-ligatures: none; }
  .diag.error .code { color: var(--danger); }
  .diag.hint .code, .diag.info .code { color: var(--t3); }
  .diag .loc { color: var(--t3); margin-right: 8px; font-size: 11.5px; font-family: var(--mono); font-variant-ligatures: none; }
  .diag .msg { font-size: 12.5px; white-space: pre-wrap; word-break: break-word; }
  .diag .fix { display: block; margin-top: 3px; color: var(--ok); font-size: 12px; }
  .dc-empty { margin: 0; padding: 10px 12px; font-size: 12.5px; color: var(--t3); }
  .dc-empty.err { color: var(--danger); }
  .dc-idle { font-size: 12.5px; color: var(--t3); margin: 4px 0 10px; }
  .dc-trace-toggle { background: none; border: 0; color: var(--t3); font: 12px var(--mono); cursor: pointer; padding: 6px 12px; text-align: left; font-variant-ligatures: none; }
  .pp-trace { margin: 0 12px 10px; padding: 6px 8px; background: var(--editor-bg); border: 1px dashed var(--hairline); border-radius: 6px; }
  .pp-line { font: 11.5px/1.6 var(--mono); color: var(--t3); white-space: pre-wrap; font-variant-ligatures: none; }
</style>
