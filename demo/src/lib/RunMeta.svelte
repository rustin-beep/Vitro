<script lang="ts">
  // 运行元信息面（A2/A7/A8，#140——旧栈 ret-value/steps-value 统计位、
  // stdin-row、ref-box 三块语义平移）：
  //  - 统计卡：返回码（finished 才显，否则 —）/ VM 步数（run 六字段出口）；
  //  - stdin 行：waiting_input 态出现（默认 42——旧栈 stdin-box 同值），
  //    喂入 = input.feed + 全量重采（feed 后回放从头可播，含喂入后半段）；
  //  - golden 对照：Clang golden 预置真值（CI shadow 防线对拍口径）三态 =
  //    未预置 / 编辑器已修改失效（不拿旧预期比新代码——诚实边界）/
  //    stdout·trap 对照 ✓✗。
  import { session, feedStdin } from "../session.svelte.ts";
  import { jumpToCatalog } from "../tabs.svelte.ts";
  import { formatTrap, esc } from "../../js/util.ts";

  // P2-10：trap 详报里 formatTrap 产出的 E 码徽章（@html 产物）经事件委托
  // 跳诊断手册——下划线伪链接变真通道。
  function onTrapClick(e: MouseEvent): void {
    const t = (e.target as HTMLElement).closest("[data-ecode]");
    if (t) jumpToCatalog(t.getAttribute("data-ecode")!);
  }

  let { source }: { source: string } = $props();

  const kase = $derived(session.currentCase);
  const hasRef = $derived(!!kase && (!!kase.referenceOutput || !!kase.referenceTrap));
  const stale = $derived(!!kase && source !== kase.source);
  const isTrap = $derived(session.stopped.startsWith("受检终止"));
  const goldMatch = $derived.by(() => {
    if (!kase) return false;
    if (kase.referenceKind === "stdout") return session.outputs.stdout === kase.referenceOutput;
    return (session.stopped || "").includes(kase.referenceTrap ?? "\u0000");
  });
</script>

<div class="rmeta">
  <!-- trap 详报框（行为拍板 + 位置拍板 2026-10-17：死因报告全文归位「运行」
       视图 pane 框内——左栏放全文会撑爆编辑器区；语义徽章 + E 码码表 + 结构
       标签加粗经 formatTrap） -->
  {#if isTrap}
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
    <div class="trap-full" onclick={onTrapClick} title="点击 E 码可在诊断手册中查看">{@html formatTrap(esc(session.stopped))}</div>
  {/if}
  <div class="stat-row">
    <div class="stat-card"><span class="stat-label">返回码</span><b class="stat-value">{session.runStats && session.runStats.status === "finished" ? String(session.runStats.return_value) : "—"}</b></div>
    <div class="stat-card"><span class="stat-label">VM 步数</span><b class="stat-value">{session.runStats ? String(session.runStats.steps_executed) : "—"}</b></div>
  </div>

  {#if session.runStats?.waiting_input}
    <div class="stdin-row">
      <label class="stdin-label" for="stdin-box">stdin</label>
      <textarea id="stdin-box" class="stdin-box" bind:value={session.stdinDraft} rows="1"></textarea>
      <button type="button" class="btn ghost" onclick={feedStdin} disabled={session.collecting}>
        {session.collecting ? "续跑中…" : "喂入并续跑"}
      </button>
    </div>
  {/if}

  {#if kase}
    <div class="ref-box">
      <h3 class="ref-h">与 CLANG GOLDEN 对照</h3>
      {#if !hasRef}
        <p class="muted">（本用例未预置参考值）</p>
      {:else if stale}
        <p class="muted">（编辑器内容已修改——Clang golden 对照仅对未修改的预置用例有效；可切回用例重新比对）</p>
      {:else if kase.referenceKind === "stdout"}
        <div class={goldMatch ? "verdict match" : "verdict mismatch"}>{goldMatch ? "✓ 一致" : "✗ 不一致"}</div>
        <pre class="ref-pre">Clang golden（预置真值）: {JSON.stringify(kase.referenceOutput ?? "")}
Vitro 实跑 stdout      : {JSON.stringify(session.outputs.stdout)}</pre>
      {:else}
        <div class={goldMatch ? "verdict match" : "verdict mismatch"}>{goldMatch ? `✓ 诊断类别一致（含 ${kase.referenceTrap}）` : "✗ 未复现预期诊断"}</div>
        <pre class="ref-pre">参考真值：CI 防线对该诊断类别的断言（由 wasm 宿主冒烟与 shadow 防线持续对拍）</pre>
      {/if}
    </div>
  {/if}
</div>

<style>
  .rmeta { display: flex; flex-direction: column; gap: 10px; }
  .stat-row { display: flex; gap: 12px; }
  .stat-card { flex: 0 0 auto; min-width: 120px; padding: 8px 14px; border: 1px solid var(--hairline); border-radius: 8px; background: var(--pane); display: flex; flex-direction: column; gap: 2px; }
  .stat-label { font-size: 11.5px; color: var(--t3); }
  .stat-value { font: 16px var(--mono); color: var(--t1); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .stdin-row { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border: 1px solid var(--num); border-radius: 8px; background: var(--pane); }
  .stdin-label { font: 12px var(--mono); color: var(--num); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .stdin-box { flex: 1 1 auto; min-width: 0; font: 12.5px var(--mono); color: var(--t1); background: var(--editor-bg); border: 1px solid var(--hairline); border-radius: 6px; padding: 5px 8px; resize: vertical; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .ref-box { border-top: 1px solid var(--hairline); padding-top: 8px; }
  .ref-h { font-size: 12.5px; margin: 0 0 6px; }
  .verdict { font-size: 13px; font-weight: 700; margin-bottom: 4px; }
  .verdict.match { color: var(--ok); }
  .verdict.mismatch { color: var(--danger); }
  .ref-pre { margin: 0; padding: 8px 10px; font: 11.5px var(--mono); color: var(--t2); background: var(--pane); border: 1px solid var(--hairline); border-radius: 6px; overflow: auto; white-space: pre-wrap; word-break: break-all; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  /* trap 详报框（运行视图 pane 内）：红边块 + 语义徽章对齐 + E 码码表徽章 */
  .trap-full { padding: 10px 12px; border: 1px solid var(--danger); border-radius: 8px; background: var(--danger-tint); color: var(--danger); font: 12.5px/1.7 var(--mono); white-space: pre-wrap; word-break: break-word; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .trap-full :global(.icon-svg svg) { width: 14px; height: 14px; vertical-align: -2px; }
  .trap-full :global(.tp-tag) { color: var(--t1); }
  .trap-full :global(.tp-code) { font: 11.5px var(--mono); background: var(--pane); border: 1px solid var(--danger); border-radius: 4px; padding: 0 4px; color: var(--danger); cursor: pointer; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .trap-full :global(.tp-code:hover) { background: var(--danger-tint); }
</style>
