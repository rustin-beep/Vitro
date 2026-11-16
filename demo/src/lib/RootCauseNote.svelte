<script lang="ts">
  // 根因提示（#470 批三，FE 报告 §② 反向差集）：当前数据面帧的
  // root_cause_hint（引擎认知推理面）——category + 一句话 + 相关行 + 修复建议。
  // 帧级提示，跟随 displayIdx（末帧收尾沿用前一帧快照时与数组/变量同帧）。
  // 无 hint 不渲染（存在性纪律：不发明空卡片）；字段缺失逐项不显示。
  // 批四：plan.enter == "diag:<category>"（根因首现帧）时卡片入场（rise 动画
  // 归宿主执行器；reduced-motion 由 app.css 全局规则切断）。
  import { frameAt, session } from "../session.svelte.ts";

  const at = $derived(session.displayIdx);
  const hint = $derived(frameAt(at)?.root_cause_hint ?? null);
  const entering = $derived((session.planAt(at)?.enter ?? "").startsWith("diag:"));
</script>

{#if hint}
  <section
    class="vr-block vr-rootcause"
    class:is-enter={entering}
    aria-label="根因提示"
    data-rootcause={hint.category}
    data-enter={entering ? session.planAt(at)?.enter : undefined}
  >
    <div class="vr-blockhead">
      <h2 class="vr-label">根因提示 · {hint.category}</h2>
      <span class="vr-spacer"></span>
      {#if hint.related_lines.length > 0}
        <span class="vr-meta">相关行 {hint.related_lines.join(" / ")}</span>
      {/if}
    </div>
    <p class="vr-rootcause-line">{hint.one_liner}</p>
    {#if hint.suggested_fix_desc}
      <p class="vr-rootcause-fix">✚ {hint.suggested_fix_desc}{#if hint.suggested_fix_line !== null}（源码 L{hint.suggested_fix_line}）{/if}</p>
    {/if}
  </section>
{/if}
