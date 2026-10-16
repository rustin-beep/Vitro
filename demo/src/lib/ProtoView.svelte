<script lang="ts">
  // 引擎与协议面板（F4 组件迁移：对齐旧栈 renderProto 语义——capabilities
  // 键值面 + semantic_labels 词表；字段面随 wire 演进不锁全量，文本插值
  // 自动转义替代旧栈 esc 纪律）。
  import { session } from "../session.svelte.ts";

  const capEntries = $derived(Object.entries(session.capabilities ?? {}));
  const labelCount = $derived(session.labels.length);
</script>

<div class="proto">
  <p class="desc">
    wtp 通道：wasm-gc 单出口，invoke 字符串通道（canonicalize 口径）。下方为
    <b>capabilities</b>（能力面键值）与 <b>semantic_labels</b>（受控词表）——
    contracts 结构面随 schema v0.2 台账演进，展示字段不锁全量。
  </p>

  {#if capEntries.length}
    <h3>capabilities</h3>
    <table class="cap-table">
      <tbody>
        {#each capEntries as [k, v] (k)}
          <tr><td class="k">{k}</td><td class="v">{typeof v === "object" ? JSON.stringify(v) : String(v)}</td></tr>
        {/each}
      </tbody>
    </table>
  {:else}
    <p class="muted">（capabilities 加载中或不可用…）</p>
  {/if}

  {#if labelCount}
    <h3>semantic_labels（{labelCount} 类受控词表）</h3>
    <div class="labels">
      {#each session.labels as lb (lb)}
        <span class="chip">{lb}</span>
      {/each}
    </div>
  {/if}
</div>

<style>
  .desc { font-size: 12.5px; color: var(--t2); line-height: 1.7; margin: 4px 0 10px; }
  .proto h3 { font-size: 12.5px; color: var(--t3); margin: 12px 0 6px; font-weight: normal; }
  .cap-table { width: 100%; border-collapse: collapse; font: 12px/1.6 var(--mono); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .cap-table td { padding: 3px 8px; border-bottom: 1px solid var(--hairline); vertical-align: top; }
  .cap-table .k { color: var(--accent-strong); width: 40%; }
  .cap-table .v { color: var(--t2); word-break: break-all; }
  .labels { display: flex; flex-wrap: wrap; gap: 6px; }
  .chip { font: 11px var(--mono); background: var(--accent-tint); color: var(--accent-strong); border-radius: 10px; padding: 2px 9px; font-variant-ligatures: none; }
  .muted { color: var(--t3); font-size: 12.5px; }
</style>
