<script lang="ts">
  // 内存地图 · P1 全页形态（#222 P1 内存/协议，2026-10-22）。
  //
  // 形态先于数字：stack / heap / global / free_list 四条轨道，块宽按真实 size
  // 比例；freed 块用红色虚线（隔离区语义）。数据只取 `memory.regions` 与
  // `free_list` 协议帧——不做帧级内存图/生命周期模板（defer #52/#53）。
  //
  // 页面化后的分工：本组件 = 证据面（统计 / 四轨 / 图例 / 真地址账本 / 读法）；
  // 右栏 MemorySide = 本课叙事与动作（三问 / 术语 / 动作）。两处都读同一份
  // session.memory，不各自算账。
  import { session } from "../session.svelte.ts";
  import { lessonSession } from "./lessonSession.svelte.ts";
  import { quarPct, tableRows } from "./memoryView.ts";
  import type { HeapRegion } from "../../js/types.ts";

  const mem = $derived(session.memory);
  const rows = $derived(mem ? tableRows(mem) : []);
  const quar = $derived(mem ? quarPct(mem) : 0);
  const lessonId = $derived(lessonSession.lesson?.id ?? "自由代码");

  /** 隔离区占比文案：非零但 < 1% 时保留三位，避免 4 B / 262144 B 被印成 0.00%。 */
  function pctText(v: number): string {
    return v > 0 && v < 1 ? `${v.toFixed(3)}%` : `${v.toFixed(2)}%`;
  }

  interface Seg {
    key: string;
    label: string;
    size: number;
    cls: string;
    title: string;
  }
  interface Track {
    id: string;
    label: string;
    segs: Seg[];
    bytes: number;
    count: number;
    empty: string;
  }

  function segOfRegion(r: HeapRegion): Seg {
    // 未知 kind 显式落 is-unknown（审查 P3：旧实现静默归 is-stack，引擎新增
    // 段类型会伪装成栈）
    const cls = r.is_freed
      ? "is-freed"
      : r.kind === "heap"
        ? "is-alloc"
        : r.kind === "global"
          ? "is-global"
          : r.kind === "stack"
            ? "is-stack"
            : "is-unknown";
    return {
      key: `${r.addr}:${r.size}:${r.name}`,
      label: r.is_freed ? `${r.name || r.ty} · freed` : `${r.name || r.ty} · ${r.size} B`,
      size: r.size,
      cls,
      title: `${r.name} · ${r.ty} · ${r.size} B @0x${r.addr.toString(16)}${r.is_freed ? " · freed（隔离中）" : ""}${r.kind === "heap" || r.kind === "global" || r.kind === "stack" ? "" : ` · 未知段 ${r.kind}`}`,
    };
  }

  const tracks = $derived.by((): Track[] => {
    if (!mem) return [];
    const pick = (kind: string): HeapRegion[] => mem.regions.filter((r) => r.kind === kind);
    const mk = (id: string, label: string, regs: HeapRegion[], empty: string): Track => ({
      id,
      label,
      segs: regs.map(segOfRegion),
      bytes: regs.reduce((s, r) => s + r.size, 0),
      count: regs.length,
      empty,
    });
    const free = mem.free_list as Array<{ addr: number; size: number }>;
    const known = new Set(["stack", "heap", "global"]);
    const unknown = mem.regions.filter((r) => !known.has(r.kind));
    const tracks: Track[] = [
      mk("stack", "stack", pick("stack"), "（空）"),
      mk("heap", "heap", pick("heap"), "0 次 malloc"),
      mk("global", "global", pick("global"), "（空）"),
      {
        id: "free_list",
        label: "free_list",
        segs: free.map((b, i) => ({
          key: `free:${b.addr}:${b.size}:${i}`,
          label: `free · ${b.size} B`,
          size: b.size,
          cls: "is-free",
          title: `空闲块 · ${b.size} B @0x${b.addr.toString(16)}（first-fit 可复用）`,
        })),
        bytes: free.reduce((s, b) => s + b.size, 0),
        count: free.length,
        empty: "无外部碎片",
      },
    ];
    // 未知 kind 单起一轨（不并进 stack/heap/global，也不静默丢块）
    if (unknown.length) tracks.push(mk("unknown", "unknown", unknown, "（无未知段）"));
    return tracks;
  });

  const stats = $derived.by(() => {
    if (!mem) return [];
    const t = (id: string): Track => tracks.find((x) => x.id === id)!;
    return [
      { label: "stack", value: `${t("stack").bytes} B · ${t("stack").count} 块` },
      { label: "heap", value: `${t("heap").bytes} B · ${t("heap").count} 块` },
      { label: "global", value: `${t("global").bytes} B · ${t("global").count} 块` },
      { label: "free_list", value: `${t("free_list").count} 块 · ${t("free_list").bytes} B` },
      { label: "quarantine", value: `${mem.quarantine.blocks} 块 · ${mem.quarantine.bytes} B` },
      { label: "budget", value: `${mem.quarantine.budget} B · ${pctText(quar)}` },
    ];
  });
</script>

<section class="vr-block vr-mempage" aria-label="内存地图">
  <div class="vr-blockhead">
    <h2 class="vr-label">内存地图</h2>
    <span class="vr-spacer"></span>
    <span class="vr-meta">memory.regions · {lessonId} · 会话结束态</span>
  </div>

  {#if mem}
    <div class="vr-mem-stats is-wide">
      {#each stats as s (s.label)}<span>{s.label} <b>{s.value}</b></span>{/each}
    </div>

    <div class="vr-mem is-page">
      {#each tracks as t (t.id)}
        <div class="vr-mem-row is-page">
          <span class="vr-mem-label">{t.label}</span>
          <div class="vr-mem-track" aria-label="{t.label} 段">
            {#if t.segs.length === 0}
              <div class="vr-mem-seg is-empty" style:flex="1">{t.empty}</div>
            {:else}
              {#each t.segs as s (s.key)}
                <div class="vr-mem-seg {s.cls}" style:flex="{Math.max(s.size, 1)}" title={s.title}>
                  {s.label}
                </div>
              {/each}
            {/if}
          </div>
          <span class="vr-mem-total">{t.bytes} B · {t.count} 块</span>
        </div>
      {/each}

      <div class="vr-mem-row is-page is-quar">
        <span class="vr-mem-label">隔离区</span>
        <div class="vr-quar-wrap">
          <div class="vr-quar"><div class="vr-quar-fill" style:width="{quar}%"></div></div>
          <span class="vr-meta">{mem.quarantine.blocks} 块 / {mem.quarantine.bytes} B，预算 {mem.quarantine.budget} B（UAF 检测窗）</span>
        </div>
        <span class="vr-mem-total">{pctText(quar)}</span>
      </div>
    </div>

    <div class="vr-mem-legend">
      <span><i class="vr-swatch is-active"></i>active</span>
      <span><i class="vr-swatch is-freed"></i>freed（隔离中）</span>
      <span><i class="vr-swatch is-quar"></i>隔离区</span>
      <span class="vr-meta">宽度 = 真实 size；地址与分配行取自 memory.regions，不画推测块</span>
    </div>

    <div class="vr-mem-tablewrap">
      <table class="vr-mem-table">
        <caption>区域明细 · 真地址 · 分配行（{rows.length} 块）</caption>
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
    </div>

    <p class="vr-mem-readtitle">读法三步</p>
    <ol class="vr-mem-read">
      <li><b>先看块</b><span>宽度 = 真实 size；红色虚线块 = 已 free、正在隔离区里等复用。</span></li>
      <li><b>再看表</b><span>地址升序 + 分配行/分配者——复核泄漏与 UAF 的证据面，别只看条数。</span></li>
      <li><b>最后看代码</b><span>trap 发生时回到当前行与 golden 对照，不用「重启试试」代替归因。</span></li>
    </ol>

    <p class="vr-meta vr-mempage-foot">数据面 = memory.regions + free_list 协议帧 · 不展示帧级内存图 / 生命周期模板（defer #52/#53）</p>
  {:else}
    <p class="vr-empty">（采集后显示内存地图——malloc / free / UAF 课在这里看 freed 块与隔离区）</p>
  {/if}
</section>
