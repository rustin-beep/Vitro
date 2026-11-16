<script lang="ts">
  // 分镜轨（#222 P1 第四片，2026-10-21）：工作台左栏的竖向分镜列表——
  //   幕号 / 标题 / 当前幕要点 / 帧范围 + 当前幕进度；点幕 = 跳到幕首帧。
  //
  // scene 真源 = course/…/lesson.md 的 vitri-scenes 块（lessonMd 解析）；
  // 未迁移课（scenes=[]）整段不渲染 = 回退现有长文，不造空轨。
  // 定位/进度/文案单点在 lib/scenes.ts；本组件零判据。
  import { seek, session } from "../session.svelte.ts";
  import { lessonSession } from "./lessonSession.svelte.ts";
  import { sceneIndexAt, sceneProgress, sceneRangeLabel } from "./scenes.ts";

  const scenes = $derived(lessonSession.note?.scenes ?? []);
  const n = $derived(session.viewFrames.length);
  // 未采集（n=0）不给「当前幕」：帧流还不存在，idx 0 落在第一幕坐标里会被误读
  const cur = $derived(n > 0 ? sceneIndexAt(scenes, session.idx) : -1);
</script>

{#if scenes.length > 0}
  <section class="vr-beatrail" aria-label="本课分镜">
    <div class="vr-beatrail-head">
      <h2 class="vr-label">本课分镜</h2>
      <span class="vr-meta">{scenes.length} 幕{cur >= 0 ? ` · 第 ${cur + 1} 幕` : ""}</span>
    </div>
    <ol class="vr-beatlist">
      {#each scenes as s, i (s.id)}
        <li>
          <button
            type="button"
            class="vr-beat"
            class:is-active={i === cur}
            class:is-done={i < cur}
            onclick={() => seek(s.from)}
            disabled={n === 0}
            aria-current={i === cur ? "step" : undefined}
          >
            <span class="vr-beat-no">{s.id}</span>
            <span class="vr-beat-body">
              <span class="vr-beat-title">{s.title}</span>
              {#if i === cur && s.note}<span class="vr-beat-note">{s.note}</span>{/if}
              <span class="vr-beat-range">{sceneRangeLabel(s)}{i === cur ? " · 当前" : ""}</span>
              {#if i === cur && n > 0}
                <span class="vr-beat-prog" aria-hidden="true"><span style:width="{sceneProgress(s, session.idx) * 100}%"></span></span>
              {/if}
            </span>
          </button>
        </li>
      {/each}
    </ol>
  </section>
{/if}
