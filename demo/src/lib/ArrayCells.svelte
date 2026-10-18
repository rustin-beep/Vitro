<script lang="ts">
  // 数组索引格（设计稿 P1-5 / P2-6 / B1 收口）：
  //   - 5 个固定槽位按 **index keyed**，值只改格内文本——重复值与 0 都有
  //     固定位置，不做跨格 FLIP（旧 ArrayBars 按值 keying 的 NaN#0 崩溃面在
  //     结构上消失）；
  //   - 格底 4px 琥珀量感条，高度按 |v|/max 归一化（丢量感的补丁）；
  //   - 「当前比较」自动指认（本稿新增）：解析当前行 `a[expr]`，用局部变量
  //     求值下标——a[j+1] 在 j=1 时指到 a[2]，不需要手写高亮规则；
  //   - 「已就位」由 golden 输出反推（与末位对齐的最长后缀），非硬编码。
  import { session } from "../session.svelte.ts";
  import { goldenNumbers } from "./golden.ts";
  import type { ArraySnapshot, StepPayload } from "../../js/types.ts";

  let { snap, frame, source, before, heldFrom = -1 }: { snap: ArraySnapshot; frame: StepPayload | undefined; source: string; before: StepPayload | undefined; heldFrom?: number } = $props();

  const elements = $derived(snap?.elements ?? []);
  const nums = $derived(elements.map(Number));
  const numeric = $derived(elements.length > 0 && nums.every((n) => Number.isFinite(n)));
  const maxAbs = $derived(Math.max(...nums.map((n) => Math.abs(n)), 1));

  /** 上一个可视帧的同名快照（变化闪烁的判定基准）。 */
  const prevEls = $derived(before?.array_snapshots?.find((s) => s.name === snap.name)?.elements ?? null);
  const changed = $derived.by(() => {
    const s = new Set<number>();
    if (!prevEls || prevEls.length !== elements.length) return s;
    elements.forEach((v, i) => { if (v !== prevEls[i]) s.add(i); });
    return s;
  });

  /** 当前行出现的 `name[...]` 下标（局部变量求值；解析不了就不猜）。 */
  const focus = $derived.by(() => {
    const line = frame?.code_line ?? 0;
    const text = line > 0 ? (source.split("\n")[line - 1] ?? "") : "";
    if (!text || !snap.name) return [] as number[];
    const esc = snap.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`${esc}\\s*\\[([^\\]]+)\\]`, "g");
    const out: number[] = [];
    const vars = new Map((frame?.local_vars ?? []).map((v) => [v.name, Number(v.value)]));
    for (const m of text.matchAll(re)) {
      const expr = m[1].replace(/\s+/g, "");
      if (!expr) continue;
      // 只认 常量 / 标识符 / 标识符±常量（a[j]、a[j+1]、a[0]、a[n-1]）
      const toks = expr.match(/^([A-Za-z_]\w*|\d+)(?:([+-])(\d+))?$/);
      if (!toks) continue;
      const base = /^\d+$/.test(toks[1]) ? Number(toks[1]) : vars.get(toks[1]);
      if (base == null || !Number.isFinite(base)) continue;
      const idx = toks[2] ? base + (toks[2] === "-" ? -1 : 1) * Number(toks[3]) : base;
      if (Number.isInteger(idx) && idx >= 0 && idx < elements.length) out.push(idx);
    }
    return [...new Set(out)].sort((a, b) => a - b);
  });

  /** 「已就位」= 与 golden 末位一致的**后缀**（排序课才有；非排序课不标）。 */
  const sortedFrom = $derived.by(() => {
    const g = goldenNumbers(session.currentCase);
    if (!g || !numeric || g.length !== nums.length) return nums.length;
    let last = -1;
    for (let i = 0; i < nums.length; i += 1) if (nums[i] !== g[i]) last = i;
    return last + 1;
  });

  const metaText = $derived(
    (heldFrom >= 0 ? `末帧收尾 · 沿用第 ${heldFrom + 1} 帧 · ` : "") +
      (focus.length > 0
        ? "当前比较 " + focus.map((i) => `${snap.name}[${i}]`).join(" / ")
        : "本帧无下标访问"),
  );
</script>

<section class="vr-block" aria-label="数组可视化">
  <div class="vr-blockhead">
    <h2 class="vr-label">数组 {snap?.name ?? "?"} · {snap?.element_ty ?? "?"}[{elements.length}]</h2>
    <span class="vr-spacer"></span>
    <span class="vr-meta">{metaText}</span>
  </div>

  {#if elements.length === 0}
    <p class="vr-empty">（此帧无数组快照）</p>
  {:else}
    <div class="vr-cells" role="list" aria-label="数组 {snap.name} 的索引格">
      {#each elements as v, i (i)}
        <div
          class="vr-cell"
          class:is-current={focus.includes(i)}
          class:is-sorted={i >= sortedFrom}
          class:is-swap={changed.has(i)}
          class:is-text={!numeric}
          role="listitem"
          aria-label="{snap.name}[{i}] = {v}"
        >
          <span class="vr-idx">{snap.name}[{i}]</span>
          <span class="vr-val">{v}</span>
          {#if numeric}
            <span class="vr-bar" style:height="{Math.round(Math.max((Math.abs(nums[i]) / maxAbs) * 16, 2))}px"></span>
          {/if}
        </div>
      {/each}
    </div>
    <div class="vr-arrayfoot">
      <span class="vr-legend"><i class="is-cur"></i>当前比较</span>
      <span class="vr-legend"><i class="is-sorted"></i>已就位</span>
      <span class="vr-note-mini">索引固定；交换时看格内值的变化。</span>
    </div>
  {/if}
</section>
