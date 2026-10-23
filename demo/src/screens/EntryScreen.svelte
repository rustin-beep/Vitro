<script lang="ts">
  // 入口态 · 课程目录（#222 P2，设计稿 05）：路径 + 课列 + 章节面板。
  //
  // 形态：hero（主张 + 首访动线 + 「继续上次」主卡）/ 9 章横向路径 /
  // 课列（单击 = 直接在实验台打开，不再二次预览）/ 章节面板（进度 + 本章
  // 会看到 + 开课 CTA）。搜索仍只过滤当前章。
  //
  // 数据：CHAPTERS / LESSON_COUNT 来自 courseIndex（单源）；章简介是**演示
  // 文案**（CHAPTER_BLURB），不是引擎事实；课名/说明/关联全部读课程数据。
  import { CHAPTERS, KIND_LABELS, LESSON_COUNT, defaultLesson, type CourseLesson } from "../lib/courseIndex.ts";
  import { progress } from "../lib/progress.svelte.ts";
  import { ui } from "../ui.svelte.ts";
  import { lessonSession } from "../lib/lessonSession.svelte.ts";

  // 章简介：只写「这章在教什么」，不复制课名/数字（数字从数据算）。
  const CHAPTER_BLURB: Record<string, string> = {
    basic: "白箱入门的最小闭环——从 printf 到 malloc，每一课都能逐帧停。",
    sorting: "排序算法同框对照：比较与交换的次数在帧流里看得见。",
    search: "有序与无序的两条查找路径，先看边界怎么收。",
    graph: "邻接表上的 BFS / DFS / 最短路——队列与栈的现场。",
    tree: "从二叉树遍历到平衡树：递归深度就是调用栈深度。",
    structures: "链表 / 栈 / 队列 / 哈希——指针改写与容量策略。",
    string: "字符与字节的边界，KMP 的 next 表怎么长出来。",
    mathdp: "递推、记忆化与 DP 表——状态转移的每一格。",
    xlab: "扩展练习：不写课文，直接跑源码读帧流。",
  };

  let query = $state("");

  $effect(() => {
    if (ui.entryChapter) return;
    const d = defaultLesson();
    ui.entryChapter = d?.chapter.id ?? CHAPTERS[0]?.id ?? "";
  });

  const chapter = $derived(CHAPTERS.find((c) => c.id === ui.entryChapter) ?? CHAPTERS[0] ?? null);
  const chapterLessons = $derived.by(() => {
    if (!chapter) return [] as CourseLesson[];
    const q = query.trim().toLowerCase();
    if (!q) return chapter.lessons;
    return chapter.lessons.filter((l) => `${l.id} ${l.title} ${l.blurb}`.toLowerCase().includes(q));
  });
  const doneInChapter = $derived(chapter ? chapter.lessons.filter((l) => progress.isDone(l.id)).length : 0);
  const pct = $derived(chapter && chapter.lessons.length ? Math.round((doneInChapter / chapter.lessons.length) * 100) : 0);
  const last = $derived(progress.last);

  // 本章「会看到」：取前三课的标题 + 一句说明（真实课目，不手写第二份）。
  const peek = $derived((chapter?.lessons ?? []).slice(0, 3));
  const startLesson = $derived.by(() => {
    const l = chapter?.lessons ?? [];
    return l.find((x) => !progress.isDone(x.id)) ?? l[0] ?? null;
  });

  function statusOf(l: CourseLesson): string {
    // 上次停留的课优先标「进行中」——即使它已被 markDone（学习是连续的，
    // 设计稿 05 的 bubble 行就是「进行中」形态）。
    if (last?.lessonId === l.id && last.chapId === l.chapId) return "进行中";
    if (progress.isDone(l.id)) return "已完成";
    return "未开始";
  }
  function open(l: CourseLesson): void {
    void lessonSession.open(l, { autoplay: true });
  }
  function pick(chapId: string): void {
    ui.entryChapter = chapId;
  }
</script>

<main class="vr-entrypage">
  <section class="vr-entry-hero">
    <div class="vr-entry-herotext">
      <div class="vr-kicker">课程目录 · {CHAPTERS.length} 章 · {LESSON_COUNT} 门课 · 全部可执行</div>
      <h1>从一行 C 开始，<br />看见它怎么执行。</h1>
      <p class="vr-lede">这不是播放动画的演示页。左边是 VM 真实的数组、调用栈和帧流，右边是你写的 C；每一步都能停下来读。</p>
      <div class="vr-firstvisit">
        <b>第一次来？</b>
        <button type="button" class="vr-cta" onclick={() => void lessonSession.openById("hello", "basic")}>先看 hello（3 分钟）</button>
        <span>或</span>
        <button type="button" class="vr-cta" onclick={() => void lessonSession.openById("bubble", "basic")}>直接看 bubble 怎么排序</button>
      </div>
    </div>

    {#if last}
      <button type="button" class="vr-continue" onclick={() => void lessonSession.resumeLast()}>
        <span class="vr-continue-head"><span>继续上次</span><span class="vr-meta">{last.chapId}</span></span>
        <b>{last.title}</b>
        <span class="vr-continue-meta">{last.total > 1 ? `第 ${last.frame + 1} / ${last.total} 帧` : `第 ${last.frame + 1} 帧`} · 停在这</span>
        <span class="vr-continue-cta">继续这一帧 →</span>
      </button>
    {/if}
  </section>

  <nav class="vr-path" aria-label="章路径">
    {#each CHAPTERS as c (c.id)}
      <button type="button" class="vr-chapter" class:is-active={chapter?.id === c.id} onclick={() => pick(c.id)}>
        <span>{c.label}</span>
        <span class="vr-count">{c.lessons.filter((l) => progress.isDone(l.id)).length}/{c.lessons.length}</span>
      </button>
    {/each}
  </nav>

  <div class="vr-entry-grid">
    <section class="vr-lessons" aria-label="课目">
      <div class="vr-lesson-head">
        <h2>{chapter?.label ?? "课程"}</h2>
        <span class="vr-meta">{chapter?.lessons.length ?? 0} 课 · 全部可逐帧停</span>
      </div>
      <div class="vr-progress"><i style:width="{pct}%"></i></div>
      <input class="vr-search" type="search" placeholder="本章搜索课名 / id / 关键词…" aria-label="搜索本章课程" bind:value={query} />
      {#each chapterLessons as l (`${l.kind}/${l.famId ?? ""}/${l.id}`)}
        <button
          type="button"
          class="vr-lesson-row"
          class:is-active={last?.lessonId === l.id}
          class:is-done={progress.isDone(l.id)}
          onclick={() => open(l)}
          title={`打开：${l.title}`}
        >
          <span class="vr-ord">{String(l.ordinal).padStart(2, "0")}</span>
          <span class="vr-lesson-main">
            <span class="vr-lesson-line">
              <span class="vr-id">{l.id}</span>
              <span class="vr-name">{l.title}</span>
              <span class="vr-tag">{KIND_LABELS[l.kind]}</span>
            </span>
            <span class="vr-blurb">{l.blurb || "（无一句话说明）"}</span>
          </span>
          <span class="vr-lesson-state" class:is-done={progress.isDone(l.id)} class:is-live={statusOf(l) === "进行中"}>{statusOf(l)}</span>
          <span class="vr-arrow" aria-hidden="true">→</span>
        </button>
      {:else}
        <p class="vr-empty">{query.trim() ? "本章无匹配课程——清除搜索或切换章节。" : "（本章暂无课目）"}</p>
      {/each}
    </section>

    <aside class="vr-chapterpanel" aria-label="本章">
      {#if chapter}
        <div class="vr-kicker">本章 · {chapter.label}</div>
        <h2>先看见执行，<br />再学语法。</h2>
        <p class="vr-chapterpanel-lede">{CHAPTER_BLURB[chapter.id] ?? "这一章只做一件事：把「代码 → 帧 → 内存」的因果链走一遍。"}</p>

        <div class="vr-chapterpanel-prog">
          <div class="vr-progress"><i style:width="{pct}%"></i></div>
          <span class="vr-meta">{doneInChapter} / {chapter.lessons.length} 已完成</span>
        </div>

        <h3 class="vr-chapterpanel-h">本章会看到</h3>
        <ol class="vr-peek">
          {#each peek as l (l.id)}
            <li>
              <span class="vr-peek-id">{l.id}</span>
              <span class="vr-peek-title">{l.title}</span>
              <span class="vr-peek-blurb">{l.blurb || "直接跑源码读帧流。"}</span>
            </li>
          {/each}
        </ol>

        {#if startLesson}
          <button type="button" class="vr-btn vr-primary vr-chapterpanel-cta" onclick={() => open(startLesson)}>
            从 {startLesson.id} 开始 →
          </button>
          <span class="vr-meta">打开即采集帧流 · 自动播放</span>
        {/if}
      {/if}
    </aside>
  </div>
</main>
