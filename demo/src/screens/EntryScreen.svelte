<script lang="ts">
  // 入口态 · 课程目录（设计稿 §3.2 / A-3 / A-8 / 反馈④）：
  //   - 书页式 hero：「从一行 C 开始，看见它怎么执行。」+ 首访动线 + 继续上次；
  //   - 三列：章节（计数） / 课目（id、名称、完成标记） / 叙述预览；
  //   - 点课**只换预览不跳转**（反馈④）；「在实验台打开」由读者看完再按；
  //   - 预览是真实 lesson.md 渲染（无此课 = 诚实空态，不造假课文）。
  // 搜索框是旧课程树能力的延续（111 门课需要过滤），只在章节内过滤。
  import { CHAPTERS, KIND_LABELS, LESSON_COUNT, defaultLesson, noteKeyOf, type CourseLesson } from "../lib/courseIndex.ts";
  import { progress } from "../lib/progress.svelte.ts";
  import { ui } from "../ui.svelte.ts";
  import { lessonSession } from "../lib/lessonSession.svelte.ts";
  import { loadLessonNote } from "../lib/lessonNotes.ts";
  import CourseNote from "../lib/CourseNote.svelte";
  import type { Block } from "../lib/lessonMd.ts";

  let query = $state("");
  let previewNote = $state<{ title: string; blocks: Block[] } | null>(null);
  let previewLoading = $state(false);
  let seq = 0;

  // 首访：默认章/课（bubble 所在章）
  $effect(() => {
    if (ui.entryChapter) return;
    const d = defaultLesson();
    ui.entryChapter = d?.chapter.id ?? CHAPTERS[0]?.id ?? "";
    ui.entryLesson = d?.lesson.id ?? CHAPTERS[0]?.lessons[0]?.id ?? "";
  });

  const chapter = $derived(CHAPTERS.find((c) => c.id === ui.entryChapter) ?? CHAPTERS[0] ?? null);
  const chapterLessons = $derived.by(() => {
    if (!chapter) return [] as CourseLesson[];
    const q = query.trim().toLowerCase();
    if (!q) return chapter.lessons;
    return chapter.lessons.filter((l) => `${l.id} ${l.title} ${l.blurb}`.toLowerCase().includes(q));
  });
  const lesson = $derived(chapterLessons.find((l) => l.id === ui.entryLesson) ?? chapterLessons[0] ?? null);

  // 章切换时选中第一课（不自动打开实验台）
  $effect(() => {
    if (!chapter) return;
    if (!chapter.lessons.some((l) => l.id === ui.entryLesson)) {
      ui.entryLesson = chapter.lessons[0]?.id ?? "";
    }
  });

  // 叙述预览懒加载（竞态用序号丢弃迟到结果）
  $effect(() => {
    const l = lesson;
    const my = ++seq;
    previewNote = null;
    previewLoading = false;
    if (!l) return;
    previewLoading = true;
    void loadLessonNote(noteKeyOf(l)).then((doc) => {
      if (my !== seq) return;
      previewNote = doc ? { title: l.title, blocks: doc.blocks } : null;
      previewLoading = false;
    });
  });

  const doneInChapter = $derived(chapter ? chapter.lessons.filter((l) => progress.isDone(l.id)).length : 0);
  function pct(): string {
    if (!chapter || chapter.lessons.length === 0) return "0%";
    return `${Math.round((doneInChapter / chapter.lessons.length) * 100)}%`;
  }

  function pick(chapId: string): void {
    ui.entryChapter = chapId;
  }
  async function open(l: CourseLesson): Promise<void> {
    ui.entryLesson = l.id;
    await lessonSession.open(l, { autoplay: true });
  }
  const last = $derived(progress.last);
</script>

<main>
  <section class="vr-entry-hero">
    <div class="vr-kicker">课程目录 · {CHAPTERS.length} 章 · {LESSON_COUNT} 门课 · 数据来自引擎实跑用例与算法目录</div>
    <h1>从一行 C 开始，<br />看见它怎么执行。</h1>
    <p class="vr-lede">这不是播放动画的演示页。左边是 VM 真实的数组、调用栈和帧流，右边是你写的 C；每一步都能停下来读。</p>
    <div class="vr-firstvisit">
      <b>第一次来？</b>
      <button type="button" class="vr-cta" onclick={() => void lessonSession.openById("hello", "basic")}>先看 hello（3 分钟）</button>
      <span>或</span>
      <button type="button" class="vr-cta" onclick={() => void lessonSession.openById("bubble", "basic")}>直接看 bubble 怎么排序</button>
      <span>· 不需要安装</span>
    </div>
    {#if last}
      <button type="button" class="vr-continue" onclick={() => void lessonSession.resumeLast()}>
        <b>继续上次</b>
        <span>{last.title}</span>
        <span class="vr-frame">第 {last.frame + 1} / {Math.max(last.total, 1)} 帧</span>
        <span>→</span>
      </button>
    {/if}
  </section>

  <div class="vr-entry-grid">
    <nav class="vr-chapters" aria-label="章节">
      <h2>章节</h2>
      {#each CHAPTERS as c (c.id)}
        <button type="button" class="vr-chapter" class:is-active={chapter?.id === c.id} onclick={() => pick(c.id)}>
          <span>{c.label}</span>
          <span class="vr-count">{c.lessons.filter((l) => progress.isDone(l.id)).length}/{c.lessons.length}</span>
        </button>
      {/each}
    </nav>

    <section class="vr-lessons" aria-label="课目">
      <div class="vr-lesson-head">
        <h2>{chapter?.label ?? "课程"}</h2>
        <span class="vr-meta">{chapter?.lessons.length ?? 0} 课</span>
      </div>
      <p class="vr-grain-note" style="margin:2px 0 6px">每门课都带源码：点「在实验台打开」即采集帧流；有叙述的课先读右侧预览。</p>
      <div class="vr-progress"><i style:width={pct()}></i></div>
      <input class="vr-search" type="search" placeholder="本章搜索课名 / id / 关键词…" aria-label="搜索本章课程" bind:value={query} />
      {#each chapterLessons as l (`${l.kind}/${l.famId ?? ""}/${l.id}`)}
        <button
          type="button"
          class="vr-lesson-row"
          class:is-active={lesson?.id === l.id}
          class:is-done={progress.isDone(l.id)}
          onclick={() => (ui.entryLesson = l.id)}
          ondblclick={() => void open(l)}
          title={l.blurb || l.title}
        >
          <span class="vr-id">{l.id}</span>
          <span class="vr-name">{l.title}{#if l.kind === "case"}<span class="vr-tag">实跑</span>{/if}</span>
          <span class="vr-mark" aria-label={progress.isDone(l.id) ? "已完成" : "未读"}>{progress.isDone(l.id) ? "✓" : "·"}</span>
        </button>
      {:else}
        <p class="vr-empty">{query.trim() ? "本章无匹配课程——清除搜索或切换章节。" : "（本章暂无课目）"}</p>
      {/each}
    </section>

    <aside class="vr-preview" aria-label="课目预览">
      {#if lesson}
        <div class="vr-kicker">课 {String(lesson.ordinal).padStart(2, "0")} · {lesson.chapLabel} · {KIND_LABELS[lesson.kind]}</div>
        <h3>{lesson.title}</h3>
        {#if lesson.blurb}<p class="vr-blurb">{lesson.blurb}</p>{/if}
        {#if previewLoading}
          <p class="vr-note-empty">（正在读取课文…）</p>
        {:else if previewNote}
          <CourseNote title={previewNote.title} blocks={previewNote.blocks} />
        {:else}
          <p class="vr-note-empty">此课尚无叙述真源（<code>course/{lesson.chapId}/{lesson.id}/lesson.md</code> 未入库）——源码仍可在实验台跑。</p>
        {/if}
        <button type="button" class="vr-btn vr-open" onclick={() => void open(lesson)}>在实验台打开 →</button>
        <span class="vr-meta">打开即采集帧流 · 自动播放</span>
      {:else}
        <p class="vr-note-empty">（点左侧课目查看预览）</p>
      {/if}
    </aside>
  </div>
</main>
