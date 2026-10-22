<script lang="ts">
  // 内存模式右栏（#222 P1 内存/协议，2026-10-22）：本课叙事 + 三问 + 术语 + 动作。
  //
  // 数据全部来自现有协议帧与课程真源：
  //   - 内存：session.memory（regions / free_list / quarantine）；
  //   - 代码：lessonSession.source + frameAt(session.idx).code_line（当前行高亮）；
  //   - 三问里「谁还在指」显式标 —：memory.regions 没有别名表，不发明指针图。
  import { frameAt, session } from "../session.svelte.ts";
  import { setMode, showRef } from "../ui.svelte.ts";
  import { lessonSession } from "./lessonSession.svelte.ts";

  const mem = $derived(session.memory);
  const lessonId = $derived(lessonSession.lesson?.id ?? "自由代码");
  const freed = $derived(mem ? mem.regions.filter((r) => r.is_freed) : []);
  const allocBy = $derived.by(() => {
    if (!mem) return [];
    const m = new Map<string, number>();
    for (const r of mem.regions) {
      const k = r.alloc_by || "—";
      m.set(k, (m.get(k) ?? 0) + 1);
    }
    return [...m.entries()].map(([name, n]) => ({ name, n }));
  });

  const curLine = $derived(frameAt(session.idx)?.code_line ?? 0);
  /** 源码卡窗口：≤8 行（当前行居中）——uaf 这类短课能看全 main，算法课也不
   *  会把右栏撑到动作按钮以下（1440×900 里「查看诊断手册」要留在首屏）。 */
  const codeView = $derived.by(() => {
    const lines = lessonSession.source.split("\n");
    const MAX = 8;
    if (!curLine || lines.length <= MAX) {
      return lines.map((text, i) => ({ n: i + 1, text, cur: i + 1 === curLine }));
    }
    const start = Math.max(0, Math.min(curLine - Math.round(MAX / 2), lines.length - MAX));
    return lines.slice(start, start + MAX).map((text, i) => ({ n: start + i + 1, text, cur: start + i + 1 === curLine }));
  });
</script>

<div class="vr-side">
  <p class="vr-side-kicker">课 · {lessonId} · 内存模式</p>
  <h1 class="vr-side-title">{lessonSession.title}</h1>
  <p class="vr-side-lede">
    {freed.length
      ? "free 之后指针还在：隔离区保留块，让「再次访问」变成可指认的 trap，而不是随机崩溃。"
      : "终止态的内存账本：四轨 + 真地址 + 分配行，先把块的生死看清，再谈泄漏。"}
  </p>

  {#if mem}
    {#if freed.length > 0}
      <section class="vr-side-alert" role="status" aria-label="UAF 提示">
        <div class="vr-side-alerthead"><b>E3060</b><span>Use-After-Free</span></div>
        <p>{freed[0].name || freed[0].ty} 已释放，但仍在隔离区（{mem.quarantine.bytes} B 保留）——再次访问会命中受检窗。</p>
        <button type="button" class="vr-linkbtn" onclick={() => showRef("E3060")}>查看诊断手册 →</button>
      </section>
    {:else}
      <section class="vr-side-state" role="status">
        <span class="vr-side-dot"></span>无 freed 块——本课未触发隔离区
      </section>
    {/if}

    <section class="vr-sidecode" aria-label="当前课源码与当前行">
      <div class="vr-sidecode-head"><span>{lessonId}.c</span><span class="vr-meta">{curLine ? `当前行 ${curLine}` : "未采集"}</span></div>
      <ol class="vr-sidecode-body">
        {#each codeView as l (l.n)}
          <li class:is-cur={l.cur}><span class="no">{l.n}</span><span class="tx">{l.text}</span></li>
        {/each}
      </ol>
    </section>

    <section class="vr-side-q" aria-label="内存三问">
      <h3>内存三问</h3>
      <dl>
        <div><dt>谁分配的</dt><dd>{allocBy.map((x) => `${x.name} ×${x.n}`).join(" · ") || "—"}</dd></div>
        <div><dt>谁释放的</dt><dd>{freed.length ? `${freed.length} 块（隔离区 ${mem.quarantine.blocks} 块 / ${mem.quarantine.bytes} B）` : "0 块"}</dd></div>
        <div><dt>谁还在指</dt><dd>—（memory.regions 不含别名表）</dd></div>
      </dl>
    </section>

    <div class="vr-side-terms" aria-label="相关术语">
      <button type="button" onclick={() => showRef("E3060")}>E3060 UAF</button>
      <button type="button" onclick={() => showRef("E3061")}>E3061 double free</button>
      <span>NULL 解引用</span>
      <span>越界访问</span>
    </div>

    <div class="vr-side-actions">
      {#if freed.length > 0}
        <button type="button" class="vr-btn vr-primary" onclick={() => showRef("E3060")}>查看 E3060 诊断手册</button>
      {:else}
        <button type="button" class="vr-btn vr-primary" onclick={() => showRef()}>打开诊断手册</button>
      {/if}
      <button type="button" class="vr-btn" onclick={() => setMode("exec")}>切回执行模式</button>
    </div>

    <p class="vr-side-foot">会话结束态；时间轴上的帧级变化看「执行」模式。内存三问只答 memory.regions 能证的三件事。</p>
  {:else}
    <p class="vr-side-empty">（采集后这里给出本课的内存三问；当前会话还没有 memory.regions 帧）</p>
  {/if}
</div>
