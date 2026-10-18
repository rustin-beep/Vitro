<script lang="ts">
  // 运行期 trap 示意图（教学示意，不是引擎输出）。参考态详情与工作态 trap
  // 面板共用；不同码给不同一幕，避免「所有运行期错误都套同一张图」。
  import { trapKind } from "./catalogDetail.ts";

  let { code }: { code: string } = $props();
  const kind = $derived(trapKind(code || ""));
</script>

<svg viewBox="0 0 720 190" role="img" aria-label="运行期 {code || 'trap'} 示意：{kind}">
  <defs>
    <pattern id="vr-hatch" width="6" height="6" patternUnits="userSpaceOnUse">
      <path class="dg-hatchline" d="M0 6L6 0" />
    </pattern>
  </defs>
  <line class="dg-axis" x1="36" y1="112" x2="690" y2="112" />

  {#if kind === "uaf"}
    <line class="dg-tick" x1="120" y1="106" x2="120" y2="118" />
    <line class="dg-tick" x1="300" y1="106" x2="300" y2="118" />
    <line class="dg-tick" x1="500" y1="106" x2="500" y2="118" />
    <line class="dg-tick" x1="620" y1="106" x2="620" y2="118" />
    <rect class="dg-block" x="80" y="62" width="80" height="34" />
    <text class="dg-label" x="120" y="54" text-anchor="middle">malloc(16)</text>
    <rect class="dg-freed" x="260" y="62" width="80" height="34" fill="url(#vr-hatch)" />
    <text class="dg-label" x="300" y="54" text-anchor="middle">free(p)</text>
    <path class="dg-arrow" d="M496 79H352" />
    <path class="dg-red" d="M352 79l9-4v8z" />
    <text class="dg-label" x="500" y="54" text-anchor="middle">p[0] · 再次访问</text>
    <path class="dg-red" d="M608 50h24M620 50v72" />
    <text class="dg-red-label" x="620" y="40" text-anchor="middle">E3060</text>
    <text class="dg-dim" x="120" y="136" text-anchor="middle">1 · 分配</text>
    <text class="dg-dim" x="300" y="136" text-anchor="middle">2 · 释放（块仍可读）</text>
    <text class="dg-dim" x="500" y="136" text-anchor="middle">3 · 别名仍指向它</text>
    <text class="dg-dim" x="620" y="136" text-anchor="middle">4 · 受检访问抓住</text>
  {:else if kind === "overflow"}
    <line class="dg-tick" x1="120" y1="106" x2="120" y2="118" />
    <line class="dg-tick" x1="280" y1="106" x2="280" y2="118" />
    <line class="dg-tick" x1="420" y1="106" x2="420" y2="118" />
    <line class="dg-tick" x1="560" y1="106" x2="560" y2="118" />
    <rect class="dg-block" x="120" y="62" width="160" height="34" />
    <line class="dg-tick" x1="160" y1="62" x2="160" y2="96" />
    <line class="dg-tick" x1="200" y1="62" x2="200" y2="96" />
    <line class="dg-tick" x1="240" y1="62" x2="240" y2="96" />
    <text class="dg-label" x="200" y="54" text-anchor="middle">char buf[4]</text>
    <rect class="dg-freed" x="280" y="62" width="80" height="34" fill="url(#vr-hatch)" />
    <text class="dg-label" x="420" y="54" text-anchor="middle">"0123456789" · 11 字节</text>
    <path class="dg-arrow" d="M420 79H368" />
    <path class="dg-red" d="M368 79l9-4v8z" />
    <path class="dg-red" d="M548 50h24M560 50v72" />
    <text class="dg-red-label" x="560" y="40" text-anchor="middle">E3070</text>
    <text class="dg-dim" x="120" y="136" text-anchor="middle">1 · 分配 4 字节</text>
    <text class="dg-dim" x="280" y="136" text-anchor="middle">2 · 写入越界</text>
    <text class="dg-dim" x="420" y="136" text-anchor="middle">3 · 覆盖相邻内存</text>
    <text class="dg-dim" x="560" y="136" text-anchor="middle">4 · 受检终止</text>
  {:else if kind === "double-free"}
    <line class="dg-tick" x1="150" y1="106" x2="150" y2="118" />
    <line class="dg-tick" x1="330" y1="106" x2="330" y2="118" />
    <line class="dg-tick" x1="510" y1="106" x2="510" y2="118" />
    <line class="dg-tick" x1="630" y1="106" x2="630" y2="118" />
    <rect class="dg-freed" x="100" y="62" width="100" height="34" fill="url(#vr-hatch)" />
    <text class="dg-label" x="150" y="54" text-anchor="middle">malloc(16)</text>
    <text class="dg-label" x="330" y="54" text-anchor="middle">free(p)</text>
    <path class="dg-arrow" d="M470 79H300" />
    <path class="dg-red" d="M300 79l9-4v8z" />
    <text class="dg-label" x="510" y="54" text-anchor="middle">free(p) · 第二次</text>
    <path class="dg-red" d="M618 50h24M630 50v72" />
    <text class="dg-red-label" x="630" y="40" text-anchor="middle">E3061</text>
    <text class="dg-dim" x="150" y="136" text-anchor="middle">1 · 分配</text>
    <text class="dg-dim" x="330" y="136" text-anchor="middle">2 · 释放</text>
    <text class="dg-dim" x="510" y="136" text-anchor="middle">3 · 再释放同一块</text>
    <text class="dg-dim" x="630" y="136" text-anchor="middle">4 · Double-Free 受检终止</text>
  {:else if kind === "free-type"}
    <line class="dg-tick" x1="150" y1="106" x2="150" y2="118" />
    <line class="dg-tick" x1="350" y1="106" x2="350" y2="118" />
    <line class="dg-tick" x1="540" y1="106" x2="540" y2="118" />
    <line class="dg-tick" x1="640" y1="106" x2="640" y2="118" />
    <rect class="dg-block" x="100" y="62" width="100" height="34" />
    <text class="dg-label" x="150" y="54" text-anchor="middle">int x = 5</text>
    <text class="dg-label" x="350" y="54" text-anchor="middle">free(42)</text>
    <path class="dg-arrow" d="M470 79H300" />
    <path class="dg-red" d="M300 79l9-4v8z" />
    <text class="dg-label" x="540" y="54" text-anchor="middle">free(&amp;x) · 非 malloc</text>
    <path class="dg-red" d="M628 50h24M640 50v72" />
    <text class="dg-red-label" x="640" y="40" text-anchor="middle">E3027</text>
    <text class="dg-dim" x="150" y="136" text-anchor="middle">1 · 普通变量</text>
    <text class="dg-dim" x="350" y="136" text-anchor="middle">2 · 参数不是指针</text>
    <text class="dg-dim" x="540" y="136" text-anchor="middle">3 · 指针来源不是 malloc</text>
    <text class="dg-dim" x="640" y="136" text-anchor="middle">4 · 受检终止</text>
  {:else}
    <line class="dg-tick" x1="150" y1="106" x2="150" y2="118" />
    <line class="dg-tick" x1="330" y1="106" x2="330" y2="118" />
    <line class="dg-tick" x1="520" y1="106" x2="520" y2="118" />
    <line class="dg-tick" x1="620" y1="106" x2="620" y2="118" />
    <rect class="dg-freed" x="100" y="62" width="100" height="34" fill="url(#vr-hatch)" />
    <text class="dg-label" x="150" y="54" text-anchor="middle">0x0 · NULL 页</text>
    <text class="dg-label" x="330" y="54" text-anchor="middle">int *p = NULL</text>
    <path class="dg-arrow" d="M460 79H300" />
    <path class="dg-red" d="M300 79l9-4v8z" />
    <text class="dg-label" x="520" y="54" text-anchor="middle">*p = 1 · 解引用</text>
    <path class="dg-red" d="M608 50h24M620 50v72" />
    <text class="dg-red-label" x="620" y="40" text-anchor="middle">trap</text>
    <text class="dg-dim" x="150" y="136" text-anchor="middle">1 · NULL 页（受检区）</text>
    <text class="dg-dim" x="330" y="136" text-anchor="middle">2 · 指针未初始化</text>
    <text class="dg-dim" x="520" y="136" text-anchor="middle">3 · 解引用 NULL</text>
    <text class="dg-dim" x="620" y="136" text-anchor="middle">4 · 受检终止</text>
  {/if}

  <text class="dg-dim" x="36" y="172">时间 →</text>
  <text class="dg-dim" x="690" y="172" text-anchor="end">{kind === "uaf" ? "三幕可指认：分配 → 释放 → 访问 → 受检终止" : "示意：出错路径 → 受检终止；行列与引擎原文见下"}</text>
</svg>
