<script lang="ts">
  // 内存地图（F4 组件迁移，审阅 C-P2-6 处方）：keyed each + animate:flip +
  // out:fade——旧栈 bandRender 手写 keyed（data-key :not(.out) 查询）+
  // animationend + 260ms 魔数定时器三件套（全在重造框架免费给的东西；
  // 定时器与 CSS 时长双源的漂移面在此消失，退场时长 = 单一常量）。
  // 纯变换在 memoryView.ts（heapSpanOf 物理保留 js/memory.ts，E-08 落点）。
  import { flip } from "svelte/animate";
  import { fade } from "svelte/transition";
  import { session } from "../session.svelte.ts";
  import { fullBandEntries, heapBandEntries, heapZoomLabel, memStats, quarPct, tableRows } from "./memoryView.ts";

  const OUT_MS = 140; // 退场时长单一常量（旧栈 260 魔数 = CSS --t-fast 手抄副本的漂移面）

  const mem = $derived(session.memory);
  const full = $derived(mem ? fullBandEntries(mem) : []);
  const heap = $derived(mem ? heapBandEntries(mem) : []);
  const stats = $derived(mem ? memStats(mem) : []);
  const rows = $derived(mem ? tableRows(mem) : []);
  const zoomLabel = $derived(mem ? heapZoomLabel(mem) : "");
  const quar = $derived(mem ? quarPct(mem) : 0);
</script>

{#if mem}
  <div class="mstats">
    {#each stats as s (s.label)}
      <span><b>{s.label}</b> {s.value}</span>
    {/each}
  </div>

  <div class="band full">
    {#each full as e (e.key)}
      <div class="blk {e.cls}" style="left:{e.left * 100}%; width:{e.width * 100}%" title={e.title}
        animate:flip={{ duration: OUT_MS }}
        out:fade={{ duration: OUT_MS }}></div>
    {/each}
  </div>

  <div class="zoom-label">{zoomLabel}</div>
  <div class="band heap">
    {#each heap as e (e.key)}
      <div class="blk {e.cls}" style="left:{e.left * 100}%; width:{e.width * 100}%" title={e.title}
        animate:flip={{ duration: OUT_MS }}
        out:fade={{ duration: OUT_MS }}></div>
    {/each}
  </div>

  <div class="quar">
    <div class="quar-fill" style="width:{quar}%" ></div>
  </div>
  <p class="quar-label">quarantine（UAF 检测窗）：{mem.quarantine.blocks} 块 / {mem.quarantine.bytes} B，预算 {mem.quarantine.budget} B</p>

  <table class="mtable">
    <thead>
      <tr><th>地址</th><th>大小</th><th>名称</th><th>类型</th><th>段</th><th>状态</th><th>分配行</th><th>来源</th></tr>
    </thead>
    <tbody>
      {#each rows as r (r.addrHex + ":" + r.name)}
        <tr class:freed={r.freed}>
          <td>{r.addrHex}</td><td>{r.size}</td><td>{r.name}</td><td>{r.ty}</td><td>{r.kind}</td>
          <td>{r.freed ? "freed（隔离中）" : "活跃"}</td><td>{r.allocLine}</td><td>{r.allocBy}</td>
        </tr>
      {/each}
    </tbody>
  </table>
{:else}
  <p class="muted">（采集后显示内存地图——malloc/free/UAF 课点在此观察 freed 块与隔离区）</p>
{/if}

<style>
  .mstats { display: flex; gap: 14px; flex-wrap: wrap; font-size: 12px; color: var(--t3); margin-bottom: 8px; }
  .mstats b { color: var(--t2); font-weight: normal; }
  .band { position: relative; height: 34px; background: var(--editor-bg); border: 1px solid var(--hairline); border-radius: 6px; overflow: hidden; margin: 4px 0; }
  .band.heap { height: 44px; }
  .blk { position: absolute; top: 3px; bottom: 3px; border-radius: 3px; font-size: 9px; overflow: hidden; }
  .blk.k-global { background: var(--accent-tint); border: 1px solid var(--accent); }
  .blk.k-heap { background: color-mix(in srgb, var(--ok) 30%, transparent); border: 1px solid var(--ok); }
  .blk.k-stack { background: color-mix(in srgb, var(--num) 30%, transparent); border: 1px solid var(--num); }
  .blk.k-unknown { background: var(--hairline); border: 1px dashed var(--t3); }
  .blk.freed { opacity: 0.45; border-style: dashed; }
  .zoom-label { font: 11px var(--mono); color: var(--t3); margin: 4px 0 2px; font-variant-ligatures: none; }
  .quar { height: 8px; background: var(--field); border-radius: 4px; overflow: hidden; margin: 6px 0 2px; }
  .quar-fill { height: 100%; background: var(--num); transition: width var(--t-fast) var(--ease-out); }
  .quar-label { font-size: 11.5px; color: var(--t3); margin: 2px 0 8px; }
  .mtable { width: 100%; border-collapse: collapse; font: 12px/1.5 var(--mono); margin-top: 6px; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .mtable th, .mtable td { text-align: left; padding: 3px 8px; border-bottom: 1px solid var(--hairline); }
  .mtable th { color: var(--t3); font-weight: normal; }
  .mtable tr.freed td { color: var(--t3); }
  .muted { color: var(--t3); font-size: 12.5px; }
</style>
