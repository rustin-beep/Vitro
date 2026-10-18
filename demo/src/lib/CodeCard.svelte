<script lang="ts">
  // 诊断卡（工作态就地显示，2026-10-18 反馈③）：码表图标 + 码 + 标题 → 点击
  // 进参考态详情；下面是码表的**短信息**（说明 + 常见原因），不把手册全文
  // 摊在运行页。数据来自 error_catalog，图标来自 js/icons.ts。
  import CodeIcon from "./CodeIcon.svelte";

  let {
    code,
    icon,
    title,
    explanation,
    causes = [],
    onopen,
  }: {
    code: string;
    icon: string;
    title: string;
    explanation: string;
    causes?: string[];
    onopen: () => void;
  } = $props();
</script>

<div class="vr-codecard-wrap">
  <button type="button" class="vr-codecard" onclick={onopen} title="打开 {code} 的详细诊断页">
    <CodeIcon {icon} size={22} />
    <span class="vr-codecard-code">{code}</span>
    <b>{title}</b>
    <span class="vr-codecard-go">详细页 ↗</span>
  </button>
  {#if explanation}<p class="vr-codecard-short">{explanation}</p>{/if}
  {#if causes.length}
    <ul class="vr-codecard-causes">
      {#each causes as c (c)}<li>{c}</li>{/each}
    </ul>
  {/if}
</div>
