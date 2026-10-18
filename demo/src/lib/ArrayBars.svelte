<script lang="ts">
  // 数组柱（F4 修正：单组件单数组，props 进 snapshot——审阅 C-P0：旧栈
  // renderArrayViz 渲染全部匹配数组，试点首版只消费 array_snapshots[0]，
  // 照搬会让多数组课例静默丢第二组柱。父层按 snap.name keyed each 多实例。
  //
  // key 策略（2026-10-18 二修）：**原始元素文本 + 同值序号**。前版拿
  // Number(元素) 做 key 的输入——char 数组元素是 "'a'" 形态文本，Number 化
  // 为 NaN，NaN===NaN 恒 false 使同值序号恒 0，key 全撞 `NaN#0` →
  // each_key_duplicate 每帧崩（string_match_bf 等字符课实测 ×11）。原始
  // 文本用 === 比较语义正常，前缀计数恢复唯一性。
  //
  // 形态分流（P2-6）：全数值数组 = 柱高 |v|/max（0 值给 6% 底高——否则
  // 0/1 密集数组里 0 元素 pct=0 消失，「元素在」不可感知）；非数值数组
  // （char/字符串/struct 文本）= 等高字符格，柱高语义对它们无意义。
  //
  // ⚠️ animate: 参数实测坑（2026-10-15）：传 $derived 变量引用**不生效**
  // （动画以 flip 无参默认 duration 0 创建）；内联表达式直接读 session
  // 字段则每次 reorder 正确求值。跳转态（单步/seek）220ms cubicOut——FLIP
  // 的场景是离散跳转；连续推进（播放/批量回放）下动画每帧被下一帧打断，
  // 且实测把 flushSync 回放拖到 12ms/帧（spike 基准 48µs 的 256×）故关闭。
  // 低速播放的移位呈现留 F5（L3）按帧间隔自适应。
  import { flip } from "svelte/animate";
  import { cubicOut } from "svelte/easing";
  import { session } from "../session.svelte.ts";
  import type { ArraySnapshot } from "../../js/types.ts";

  interface Bar {
    key: string;
    label: string; // 原始元素文本（char 课去成对引号显示字符本体）
    pct: number;
    hot: boolean;
    text: boolean; // true = 非数值数组（等高格形态）
  }

  let { snap }: { snap: ArraySnapshot } = $props();

  const bars = $derived.by(() => {
    const strs = (snap?.elements ?? []).map((x) => String(x ?? ""));
    const nums = strs.map(Number);
    const numeric = nums.every((n) => !Number.isNaN(n));
    const max = Math.max(...nums, 1);
    const top = Math.max(...nums);
    // 同值序号 = 前缀计数（无状态写法——派生内不做可变集合，过 autofixer；
    // n≤32，O(n²) 无感）
    return strs.map((s, i): Bar => {
      const ord = strs.slice(0, i).filter((x) => x === s).length;
      const label = /^'(.*)'$/.exec(s)?.[1] ?? s;
      const pct = numeric ? Math.max(Math.round((Math.abs(nums[i]) / max) * 100), 6) : 40;
      return { key: `${s}#${ord}`, label, pct, hot: numeric && nums[i] === top, text: !numeric };
    });
  });
</script>

<div class="bars" class:textmode={bars.length > 0 && bars[0].text} aria-label="数组 {snap?.name ?? ''} 可视化">
  {#each bars as b (b.key)}
    <div class="bar" class:hot={b.hot} style="height:{b.pct}%" animate:flip={session.batching || session.playing ? { duration: 0 } : { duration: 220, easing: cubicOut }}>
      <span>{b.label}</span>
    </div>
  {/each}
</div>

<style>
  /* 非数值（字符格）形态：等高格 + 居中字符，无柱高语义（主样式
     .bars/.bar 在 app.css——柱状底座共用，此处只覆写形态差异） */
  .bars.textmode .bar { background: var(--accent-tint); border: 1px solid var(--accent); align-items: center; }
  .bars.textmode .bar span { margin: 0; color: var(--accent-strong); }
  .bars.textmode .bar.hot { background: var(--accent-fill); }
  .bars.textmode .bar.hot span { color: var(--on-accent, #fff); }
</style>
