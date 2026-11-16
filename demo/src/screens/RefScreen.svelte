<script lang="ts">
  // 参考态 · 诊断手册（#222 P2，设计稿 06）：三问并列 + 证据链 + 右栏阅读法。
  //
  // 数据全部来自 error_catalog（session.catalog）与 lib/catalogDetail.ts 的
  // 手册附属（关联课 / 教学示例 / 别名）；不手写第二份错误文案。设计稿里
  // 「你看到的 / 更可能是 / 为什么」这种逐码诊断判断没有数据源，落地收敛为
  // **同族条目对照**（码 / 标题 / catalog 原文说明），不发明归因。
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
  const phase = $derived(card?.category || domain);
  const related = $derived(RELATED[code] ?? "");
  const example = $derived(EXAMPLES[code] ?? null);
  const showFigure = $derived(["E3060", "E3070", "E3061", "E3027"].includes(code));
  // 同族 = 同 category 的其他条目（码表真数据；最多 8 条，按码序）
  const family = $derived((session.catalog ?? []).filter((c) => c.code_str !== code && c.category === card?.category).slice(0, 8));
  const causes = $derived(card?.common_causes ?? []);

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
      <div class="vr-ref-kicker"><CodeIcon icon={card.icon} size={14} /> {phase} · {code} · {domain}</div>
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
        <span>{phase}</span>
        {#if related}<span>相关课 {related}</span>{/if}
      </div>

      <!-- 01 三问：WHERE / HOW / FIX（数据面 = 示例 + catalog 原文，不补脑） -->
      <section class="vr-ref-sec">
        <div class="vr-ref-sechead"><h2>三问</h2><span class="vr-meta">为什么是它，而不是别的码？</span></div>
        <div class="vr-ref-three">
          <div class="vr-ref-q">
            <span class="vr-ref-qtag">WHERE</span>
            <h3>源码里长什么样</h3>
            {#if example}
              <pre class="vr-ref-snippet">{example.bad}</pre>
            {:else}
              <p class="vr-ref-muted">（catalog 未附这一条的最小示例——不手写第二份代码）</p>
            {/if}
          </div>
          <div class="vr-ref-q">
            <span class="vr-ref-qtag">HOW</span>
            <h3>引擎怎么判</h3>
            <p><b>{phase}</b>阶段报告 <code>{code}</code>。诊断文本与 <code>error_catalog</code> 同源；本条说明：</p>
            <p class="vr-ref-muted">{card.explanation || "（error_catalog 未给出说明文本）"}</p>
          </div>
          <div class="vr-ref-q">
            <span class="vr-ref-qtag">FIX</span>
            <h3>怎么修</h3>
            {#if example?.fix}
              <pre class="vr-ref-snippet">{example.fix}</pre>
            {:else if causes.length > 0}
              <ul class="vr-common">{#each causes as c (c)}<li>{c}</li>{/each}</ul>
            {:else if related}
              <p class="vr-ref-muted">此条暂无最小修法示例；到关联课 <button type="button" class="vr-linkbtn" onclick={openRelated}>{related}</button> 里看可运行形态。</p>
            {:else}
              <p class="vr-ref-muted">（catalog 与手册均未附修法——保留空态，不发明建议）</p>
            {/if}
          </div>
        </div>
      </section>

      {#if causes.length > 0}
        <section class="vr-ref-sec">
          <div class="vr-ref-sechead"><h2>常见原因</h2><span class="vr-meta">来自 error_catalog.common_causes</span></div>
          <ol class="vr-ref-causes">{#each causes as c (c)}<li>{c}</li>{/each}</ol>
        </section>
      {/if}

      {#if family.length > 0}
        <section class="vr-ref-sec">
          <div class="vr-ref-sechead"><h2>同族码</h2><span class="vr-meta">同一 catalog 分组</span></div>
          <div class="vr-ref-family">
            {#each family as f (f.code_str)}
              <button type="button" class="vr-ref-famchip" class:is-active={f.code_str === code} onclick={() => (ui.refCode = f.code_str)}>
                <span class="vr-code-id">{f.code_str}</span><span>{f.title}</span>
              </button>
            {/each}
          </div>
        </section>
      {/if}

      <section class="vr-ref-sec">
        <div class="vr-ref-sechead"><h2>相关课</h2><span class="vr-meta">实验台里可复现的形态</span></div>
        {#if related}
          <button type="button" class="vr-ref-course" onclick={openRelated}>
            <span class="vr-kicker">课</span>
            <b>{related}</b>
            <span>在实验台复现这一形态 →</span>
          </button>
        {:else}
          <p class="vr-ref-muted">此条目暂无关联课——不发明链接；可直接在实验台写最小示例复现。</p>
        {/if}
      </section>

      {#if example}
        <section class="vr-ref-sec">
          <div class="vr-ref-sechead"><h2>最小复现</h2><span class="vr-meta">教学示例（非引擎输出）</span></div>
          <div class="vr-ref-repro">
            <div><span class="vr-ref-qtag is-bad">BAD · {code}</span><pre class="vr-ref-snippet">{example.bad}</pre></div>
            {#if example.fix}<div><span class="vr-ref-qtag is-ok">GOOD · 通过</span><pre class="vr-ref-snippet">{example.fix}</pre></div>{/if}
          </div>
          {#if showFigure}
            <figure class="vr-diagram">
              <TrapFigure {code} />
              <figcaption>
                {#if code === "E3060"}E3060 的三幕：块在 free 之后仍然可读，受检访问在第三次触碰时触发 trap。{:else}教学示意：错误路径与受检终止（非引擎输出；行列与死因以引擎原文为准）。{/if}
              </figcaption>
            </figure>
          {/if}
        </section>
      {/if}

      {#if family.length > 0}
        <section class="vr-ref-sec">
          <div class="vr-ref-sechead"><h2>鉴别诊断</h2><span class="vr-meta">同族条目对照（读 catalog 原文，不猜）</span></div>
          <table class="vr-ref-discrim">
            <thead><tr><th>码</th><th>标题</th><th>catalog 说明</th></tr></thead>
            <tbody>
              {#each family as f (f.code_str)}
                <tr class:is-active={f.code_str === code}>
                  <td class="vr-code-id">{f.code_str}</td>
                  <td>{f.title}</td>
                  <td>{f.explanation || "—"}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </section>
      {/if}

      <p class="vr-ref-note">条目来自 <b>error_catalog</b>（{session.catalog.length} 条）· C 卡按 lang 过滤 · 与引擎同源，不手写第二份错误文案。</p>
    </article>

    <aside class="vr-ref-side" aria-label="手册阅读法">
      <div class="vr-ref-sidebox">
        <p class="vr-kicker">怎么用这一页</p>
        <h2>先定位阶段，<br />再找最小改法。</h2>
        <p class="vr-ref-muted">不要从码开始猜。先问：这是词法、语法、类型，还是运行期？</p>
        <ol class="vr-ref-how">
          <li><b>看阶段</b><span>{phase} · {domain}</span></li>
          <li><b>看现场</b><span>{example ? "下方 WHERE 有最小源码。" : "catalog 未附源码，按说明定位。"}</span></li>
          <li><b>做最小改法</b><span>先跑通，再谈风格。</span></li>
        </ol>
      </div>

      {#if family.length > 0}
        <div class="vr-ref-sidebox">
          <p class="vr-kicker">同族码</p>
          {#each family.slice(0, 6) as f (f.code_str)}
            <button type="button" class="vr-ref-sidecode" onclick={() => (ui.refCode = f.code_str)}>
              <span class="vr-code-id">{f.code_str}</span><span>{f.title}</span>
            </button>
          {/each}
        </div>
      {/if}

      <div class="vr-ref-sidebox">
        <button type="button" class="vr-btn" onclick={showWork}>← 返回实验台</button>
        {#if related}<button type="button" class="vr-btn vr-primary" onclick={openRelated}>在实验台复现：{related} →</button>{/if}
      </div>
    </aside>
  {/if}
</main>
