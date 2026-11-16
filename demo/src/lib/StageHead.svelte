<script lang="ts">
  // 幕头（#222 P1 第三片，2026-10-21）：把「当前幕」钉在代码上方——
  //   幕号 / 帧范围 / 源码行范围 + 幕标题 + 一句要点 + 上一幕/下一幕。
  //
  // scene 真源 = course/…/lesson.md 的 vitri-scenes 块（lessonMd 解析）；
  // 无 scene 的课（scenes=[]）整段不渲染 = 回退现有长文，不造空幕头。
  // 定位与文案单点在 lib/scenes.ts（sceneIndexAt / sceneKicker），本组件零判据。
  import { seek, session } from "../session.svelte.ts";
  import { lessonSession } from "./lessonSession.svelte.ts";
  import { sceneIndexAt, sceneKicker } from "./scenes.ts";

  const scenes = $derived(lessonSession.note?.scenes ?? []);
  const n = $derived(session.viewFrames.length);
  // 未采集（n=0）不出幕头：帧流还不存在，idx 0 落在第一幕坐标里会被误读成「已到第 1 幕」
  const cur = $derived(n > 0 ? sceneIndexAt(scenes, session.idx) : -1);
  const s = $derived(cur >= 0 ? scenes[cur] : null);
</script>

{#if s}
  <section class="vr-stagehead" aria-label="本幕">
    <div class="vr-stagehead-text">
      <div class="vr-stagehead-kicker">{sceneKicker(s, cur, scenes.length)} · 源码 L{s.lines[0]}–L{s.lines[1]}</div>
      <h2 class="vr-stagehead-title">{s.title}</h2>
      {#if s.note}<p class="vr-stagehead-note">{s.note}</p>{/if}
    </div>
    <div class="vr-stagehead-nav">
      <button type="button" class="vr-btn vr-tiny" disabled={cur <= 0} onclick={() => seek(scenes[cur - 1].from)} title="跳到上一幕开头">上一幕</button>
      <button type="button" class="vr-btn vr-tiny" disabled={cur >= scenes.length - 1} onclick={() => seek(scenes[cur + 1].from)} title="跳到下一幕开头">下一幕</button>
    </div>
  </section>
{/if}
