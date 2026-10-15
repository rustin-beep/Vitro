<script lang="ts">
  // 数组柱（F1 试点核心验收件）——keyed each + animate:flip：交换时柱体
  // 平滑移位（手写栈里 FLIP 要 measure→invert→play 三步，框架内置白送）。
  // key 策略：值 + 同值序号（值身份保留 ⇒ 真移动；重复值不撞 key）。元素
  // 真身份（谁移到哪的结构化保证）挂 F2 的 #51 extra0/1/2 语义化。
  import { flip } from "svelte/animate";
  import { cubicOut } from "svelte/easing";
  import { frameAt, session } from "../session.svelte.ts";

  interface Bar {
    key: string;
    value: number;
    pct: number;
    hot: boolean;
  }

  // ⚠️ animate: 参数实测坑（2026-10-15）：传 $derived 变量引用**不生效**
  // （动画以 flip 无参默认 duration 0 创建）；内联表达式直接读 session
  // 字段则每次 reorder 正确求值。跳转态（单步/seek）220ms cubicOut——FLIP
  // 的场景是离散跳转；连续推进（播放/批量回放）下动画每帧被下一帧打断，
  // 且实测把 flushSync 回放拖到 12ms/帧（spike 基准 48µs 的 256×）故关闭。
  // 低速播放的移位呈现留 F5（L3）按帧间隔自适应。

  const bars = $derived.by(() => {
    const snap = frameAt(session.idx)?.array_snapshots?.[0];
    const nums = (snap?.elements ?? []).map(Number);
    const max = Math.max(...nums, 1);
    const top = Math.max(...nums);
    // 同值序号 = 前缀计数（无状态写法——派生内不做可变集合，过 autofixer；
    // n≤32，O(n²) 无感）
    return nums.map((v, i): Bar => {
      const ord = nums.slice(0, i).filter((x) => x === v).length;
      return { key: `${v}#${ord}`, value: v, pct: Math.round((Math.abs(v) / max) * 100), hot: v === top };
    });
  });
</script>

<div class="bars" aria-label="数组可视化">
  {#each bars as b (b.key)}
    <div class="bar" class:hot={b.hot} style="height:{b.pct}%" animate:flip={session.batching || session.playing ? { duration: 0 } : { duration: 220, easing: cubicOut }}>
      <span>{b.value}</span>
    </div>
  {/each}
</div>
