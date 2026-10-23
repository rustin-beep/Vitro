<script lang="ts">
  // 本幕讲解 + 展开全文（#222 P1 第六片，2026-10-21）：把「课文」从一整篇
  // 长文改成「当前幕的一句要点 + 可展开的全文」——读与看的粒度对齐到幕。
  //
  // 口径：
  //   - scene 课程的课文默认折叠（details 未 open），首屏末段不再是一篇长文；
  //   - 本幕卡片只读 lesson.md 真源的 scene 字段（title/note/lines）——不手写
  //     第二份讲解；
  //   - 无 scene 的课（scenes=[]）100% 回退现有长文（不折、不造空卡片）；
  //   - 全文仍是 CourseNote 同一渲染面（E-08 golden 与 W9 的 `.vr-note-page h2`
  //     锚不受折叠影响——details 内容始终在 DOM；本幕卡片是 `.vr-note-page` 的
  //     **兄弟**节点，不入侵课文结构）。
  import { session } from "../session.svelte.ts";
  import { lessonSession } from "./lessonSession.svelte.ts";
  import { sceneIndexAt, sceneKicker } from "./scenes.ts";
  import CourseNote from "./CourseNote.svelte";

  const note = $derived(lessonSession.note);
  const scenes = $derived(lessonSession.scenes);
  const n = $derived(session.viewFrames.length);
  const cur = $derived(n > 0 ? sceneIndexAt(scenes, session.idx) : -1);
  const s = $derived(cur >= 0 ? scenes[cur] : null);
  const hasScenes = $derived(scenes.length > 0);

  /** 全文展开态（默认折叠；换课回折叠）。 */
  let open = $state(false);
  const lessonId = $derived(lessonSession.lesson?.id ?? "");
  $effect(() => {
    // 依赖 lessonId：换课即回折叠（读到 id 才触发）
    if (lessonId) open = false;
  });
</script>

{#if note}
  {#if hasScenes}
    {#if s}
      <section class="vr-scenenote" aria-label="本幕讲解">
        <div class="vr-scenenote-head">
          <span class="vr-label">本幕讲解</span>
          <span class="vr-meta">{sceneKicker(s, cur, scenes.length)} · 源码 L{s.lines[0]}–L{s.lines[1]}</span>
        </div>
        <h2 class="vr-scenenote-title">{s.title}</h2>
        {#if s.note}<p class="vr-scenenote-note">{s.note}</p>{/if}
      </section>
    {:else}
      <p class="vr-scenenote-hint">未采集或当前帧不在任何一幕内——下方可展开本课全文；点分镜轨任一幕回到该幕讲解。</p>
    {/if}
    <article class="vr-note vr-note-page" aria-label="课文全文">
      <details class="vr-notefull" bind:open>
        <summary>展开全文（本课叙述 · {note.blocks.length} 块）</summary>
        <CourseNote title={note.title} blocks={note.blocks} page />
      </details>
    </article>
  {:else}
    <article class="vr-note vr-note-page" aria-label="课文">
      <CourseNote title={note.title} blocks={note.blocks} page />
    </article>
  {/if}
{/if}
