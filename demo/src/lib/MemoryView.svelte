<script lang="ts">
  // 内存地图（设计稿「内存」模式 + P2-10）：形态先于数字——stack / heap /
  // global 三条轨道，块宽按真实 size 比例；freed 块用红色虚线 + 隔离区语义
  // （真数据 memory.regions，不展示假地址/假字节数）。
  // 明细表收进折叠段（白箱证据仍在，不抢首屏）。
  import { session } from "../session.svelte.ts";
  import { showRef } from "../ui.svelte.ts";
  import { memStats, quarPct, tableRows } from "./memoryView.ts";
  import type { HeapRegion } from "../../js/types.ts";

  const mem = $derived(session.memory);
  const stats = $derived(mem ? memStats(mem) : []);
  const quar = $derived(mem ? quarPct(mem) : 0);
  const rows = $derived(mem ? tableRows(mem) : []);
  const freed = $derived(mem ? mem.regions.filter((r) => r.is_freed) : []);

  type Track = { id: "stack" | "heap" | "global"; label: string; regions: HeapRegion[]; total: number };
  const tracks = $derived.by((): Track[] => {
    if (!mem) return [];
    const pick = (kind: string): HeapRegion[] => mem.regions.filter((r) => r.kind === kind);
    return [
      { id: "stack", label: "stack", regions: pick("stack"), total: pick("stack").reduce((s, r) => s + r.size, 0) },
      { id: "heap", label: "heap", regions: pick("heap"), total: pick("heap").reduce((s, r) => s + r.size, 0) },
      { id: "global", label: "global", regions: pick("global"), total: pick("global").reduce((s, r) => s + r.size, 0) },
    ];
  });
  function segClass(t: Track, r: HeapRegion): string {
    if (r.is_freed) return "is-freed";
    return t.id === "heap" ? "is-alloc" : t.id === "global" ? "is-global" : "is-stack";
  }
  function segLabel(t: Track, r: HeapRegion): string {
    if (r.is_freed) return `${r.name || r.ty} · freed`;
    return t.id === "heap" ? `${r.name || r.ty} · ${r.size} B` : `${r.name || r.ty} · ${r.size} B`;
  }
</script>

<section class="vr-block" aria-label="内存地图">
  <div class="vr-blockhead">
    <h2 class="vr-label">内存地图</h2>
    <span class="vr-spacer"></span>
    <span class="vr-meta">memory.regions · 会话结束态</span>
  </div>

  {#if mem}
    <div class="vr-mem-stats">
      {#each stats as s (s.label)}<span>{s.label} <b>{s.value}</b></span>{/each}
    </div>

    <div class="vr-mem">
      {#each tracks as t (t.id)}
        <div class="vr-mem-row">
          <span>{t.label}</span>
          <div class="vr-mem-track" aria-label="{t.label} 段">
            {#if t.regions.length === 0}
              <div class="vr-mem-seg is-empty" style:flex="1">{t.id === "heap" ? "0 次 malloc" : "（空）"}</div>
            {:else}
              {#each t.regions.slice(0, 8) as r, ri (`${r.addr}:${r.name}#${ri}`)}
                <div class="vr-mem-seg {segClass(t, r)}" style:flex="{Math.max(r.size, 1)}" title="{r.name || r.ty} · {r.size} B @0x{r.addr.toString(16)}{r.is_freed ? ' · freed（隔离中）' : ''}">
                  {segLabel(t, r)}
                </div>
              {/each}
              {#if t.regions.length > 8}
                <div class="vr-mem-seg is-empty" style:flex="1">+{t.regions.length - 8} 块</div>
              {/if}
            {/if}
          </div>
        </div>
      {/each}
    </div>

    {#if freed.length > 0}
      <div class="vr-mem-row" style="margin-top:7px">
        <span></span>
        <p class="vr-mem-ptr">别名 ──▶ freed 块（{freed.map((r) => r.name || r.ty).join(" / ")}）· 再次访问触发 E3060</p>
      </div>
      <button type="button" class="vr-state-link" onclick={() => showRef("E3060")}>查看 E3060 详情 ↗</button>
    {/if}

    <div class="vr-mem-row is-quar" style="margin-top:8px">
      <span>隔离区</span>
      <div>
        <div class="vr-quar"><div class="vr-quar-fill" style:width="{quar}%"></div></div>
        <span class="vr-meta">{mem.quarantine.blocks} 块 / {mem.quarantine.bytes} B，预算 {mem.quarantine.budget} B（UAF 检测窗）</span>
      </div>
    </div>

    <details class="scfg">
      <summary>区域明细（{rows.length} 块 · 真地址）</summary>
      <table class="vr-mem-table">
        <thead><tr><th>地址</th><th>大小</th><th>名称</th><th>类型</th><th>段</th><th>状态</th><th>分配行</th><th>来源</th></tr></thead>
        <tbody>
          {#each rows as r, ri (`${r.addrHex}:${r.name}#${ri}`)}
            <tr class:is-freed={r.freed}>
              <td>{r.addrHex}</td><td>{r.size}</td><td>{r.name}</td><td>{r.ty}</td><td>{r.kind}</td>
              <td>{r.freed ? "freed（隔离中）" : "活跃"}</td><td>{r.allocLine}</td><td>{r.allocBy}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </details>
  {:else}
    <p class="vr-empty">（采集后显示内存地图——malloc / free / UAF 课在这里看 freed 块与隔离区）</p>
  {/if}
</section>
