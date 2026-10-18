<script lang="ts">
  // 参考态 · 诊断手册（2026-10-18 前端改造）——左码表 / 右详情 / trap 示意。
  //
  // 数据全部来自 error_catalog（session.catalog）：标题、说明、常见原因；
  // 不手写第二份错误文案（条目标题与码表同源）。trap 示意与运行期诊断面板
  // 共用 TrapFigure（教学示意，非引擎输出）；关联课/示例/码别名在
  // lib/catalogDetail.ts 单源，工作态与参考态不各持一份。
  import { session } from "../session.svelte.ts";
  import { showWork, ui } from "../ui.svelte.ts";
  import { lessonSession } from "../lib/lessonSession.svelte.ts";
  import RefIndex from "../lib/RefIndex.svelte";
  import TrapFigure from "../lib/TrapFigure.svelte";
  import CodeIcon from "../lib/CodeIcon.svelte";
  import { EXAMPLES, RELATED, canonicalCode } from "../lib/catalogDetail.ts";

  const hasCode = (c: string): boolean => session.catalog.some((x) => x.code_str === c);
  const canonical = (c: string): string => canonicalCode(c, hasCode);

  const card = $derived(session.catalog.find((c) => c.code_str === canonical(ui.refCode)) ?? session.catalog[0] ?? null);
  const code = $derived(card?.code_str ?? "");
  const domain = $derived(code.startsWith("W") ? "警告" : code.startsWith("E3") ? "运行期" : "编译期");
  const related = $derived(RELATED[code] ?? "");
  const example = $derived(EXAMPLES[code] ?? null);
  const showFigure = $derived(["E3060", "E3070", "E3061", "E3027"].includes(code));

  // 目录就绪后归一化：W↔E 别名先落到真实条目；仍无此码才落首条
  $effect(() => {
    if (!session.catalog.length) return;
    const want = canonical(ui.refCode);
    if (want !== ui.refCode && session.catalog.some((c) => c.code_str === want)) {
      ui.refCode = want;
      return;
    }
    if (!session.catalog.some((c) => c.code_str === ui.refCode)) {
      ui.refCode = session.catalog[0].code_str;
    }
  });

  function openRelated(): void {
    if (related) void lessonSession.openById(related, "basic");
  }
</script>

<main class="vr-ref-main">
  <RefIndex />

  {#if !card}
    <article class="vr-ref-detail">
      <p class="vr-ref-empty">（诊断目录未载——引擎未就绪或 error_catalog 拉取失败。刷新页面重试；手册条目与码表同源，不在页面里手写第二份文案。）</p>
    </article>
  {:else}
    <article class="vr-ref-detail" aria-label="{code} {card.title}">
      <div class="vr-ref-kicker"><CodeIcon icon={card.icon} size={14} /> {card.category || domain} · {code} · {domain}</div>
      <h1>{card.title}</h1>
      <p class="vr-ref-lead">{card.explanation}</p>

      <div class="vr-ref-status">
        {#if domain === "编译期"}
          <span class="is-bad">编译期 {code}</span><span>运行期 未开始</span>
        {:else if domain === "运行期"}
          <span class="is-ok">编译期 通过</span><span class="is-bad">运行期 {code}</span>
        {:else}
          <span class="is-ok">编译期 通过</span><span>运行期 通过</span><span class="is-bad">{code} 警告</span>
        {/if}
        {#if related}<span>关联课 {related}</span>{/if}
        <span>{card.category || "未分类"}</span>
      </div>

      {#if showFigure}
        <figure class="vr-diagram">
          <TrapFigure {code} />
          <figcaption>
            {#if code === "E3060"}E3060 的三幕：块在 free 之后仍然可读，受检访问在第三次触碰时触发 trap。{:else}教学示意：错误路径与受检终止（非引擎输出；行列与死因以引擎原文为准）。{/if}
          </figcaption>
        </figure>
      {/if}

      {#if !card.explanation}
        <h2>为什么会发生</h2>
        <p>（error_catalog 未给出说明文本）</p>
      {/if}

      {#if card.common_causes?.length}
        <h2>常见原因</h2>
        <ul class="vr-common">
          {#each card.common_causes as c (c)}<li>{c}</li>{/each}
        </ul>
      {/if}

      {#if example}
        <h2>示例</h2>
        <pre>{example.bad}</pre>
        {#if example.fix}
          <h2>怎么修</h2>
          <pre>{example.fix}</pre>
        {/if}
      {/if}

      <div class="vr-ref-links">
        <button type="button" onclick={showWork}>← 返回执行</button>
        {#if related}<button type="button" onclick={openRelated}>在实验台复现：{related} →</button>{/if}
        {#if !related && code !== "E3060"}<span class="vr-ref-note">此条目暂无关联课</span>{/if}
      </div>

      <p class="vr-ref-note">条目来自 <b>error_catalog</b>（{session.catalog.length} 条）；图示与码表同源，不手写第二份错误文案。</p>
    </article>
  {/if}
</main>
