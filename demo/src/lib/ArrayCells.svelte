<script lang="ts">
  // 数组索引格（设计稿 P1-5 / P2-6 / B1 收口；D1 事件驱动，2026-10-29，refs #122）：
  //   - 5 个固定槽位按 **index keyed**，值只改格内文本——重复值与 0 都有
  //     固定位置，不做跨格 FLIP（旧 ArrayBars 按值 keying 的 NaN#0 崩溃面在
  //     结构上消失）；
  //   - 格底 4px 琥珀量感条，高度按 |v|/max 归一化（丢量感的补丁）；
  //   - 「当前比较」自动指认：解析当前行 `a[expr]`，用局部变量求值下标——
  //     a[j+1] 在 j=1 时指到 a[2]，不需要手写高亮规则；
  //   - **「本帧交换」事件优先**（D1）：ty=2 事件的 extras = j/j+1，两格静态
  //     高亮 + 一道连线 + WAAPI 脉冲（脉冲受动效预算管辖；静态语义恒在）。
  //     无事件时才回落到「相邻帧快照差分闪烁」兜底——差分只是猜测，事件是
  //     引擎说的原话（动效不撒谎：不插值数据，只指示身份与状态）；
  //   - 「已就位」由 golden 输出反推（与末位对齐的最长后缀），非硬编码。
  import { session } from "../session.svelte.ts";
  import { goldenNumbers } from "./golden.ts";
  import { motion, pulse } from "./motion.svelte.ts";
  import { swapPairs, type SwapPair } from "./visEvents.ts";
  import type { ArraySnapshot, StepPayload } from "../../js/types.ts";

  let { snap, frame, source, before, heldFrom = -1, frameIdx = undefined }: { snap: ArraySnapshot; frame: StepPayload | undefined; source: string; before: StepPayload | undefined; heldFrom?: number; frameIdx?: number | undefined } = $props();

  const elements = $derived(snap?.elements ?? []);
  const nums = $derived(elements.map(Number));
  // 元素类型判据（#288-②）：char 数组恒走字符格——旧判据按「元素能否解析成
  // 数字」猜类型，而引擎对 char 的不可打印字节（NUL='\n' 等）回传裸数字
  // （"0"），全 NUL 的 char 数组于是整个降级成数字格，与 int 数组肉眼不可
  // 区分。element_ty 引擎已给对，不必再猜；数字解析守卫保留给 element_ty
  // 未知（"?"）的快照。
  const isChar = $derived(snap?.element_ty === "char");
  const numeric = $derived(elements.length > 0 && !isChar && nums.every((n) => Number.isFinite(n)));
  const maxAbs = $derived(Math.max(...nums.map((n) => Math.abs(n)), 1));

  /** char 数组格子的显示文本：可打印字节引擎已回传 'c' 形态；不可打印
   *  （含 NUL 终止符）回传裸数字——按 C 转义形态补引号渲染（0 → '\0'、
   *  10 → '\n'、其余 → '\xHH'），同一数组内不再 '0' 与裸 0 混排。引擎
   *  协议面（裸数字）保持现状，消费侧转义（#288-② 处置）。 */
  const C_ESCAPES: Record<number, string> = { 0: "\\0", 7: "\\a", 8: "\\b", 9: "\\t", 10: "\\n", 11: "\\v", 12: "\\f", 13: "\\r" };
  function charCellText(v: string): string {
    if (!/^-?\d+$/.test(v)) return v; // 'c' 等既有形态原样
    const b = Number(v) & 0xff; // i8 负值按无符号字节解释（-1 → 0xFF）
    return "'" + (C_ESCAPES[b] ?? "\\x" + b.toString(16).padStart(2, "0")) + "'";
  }

  /** 上一个可视帧的同名快照（无事件时的差分兜底基准）。 */
  const prevEls = $derived(before?.array_snapshots?.find((s) => s.name === snap.name)?.elements ?? null);
  const changed = $derived.by(() => {
    const s = new Set<number>();
    if (!prevEls || prevEls.length !== elements.length) return s;
    elements.forEach((v, i) => { if (v !== prevEls[i]) s.add(i); });
    return s;
  });

  /** 本帧 ty=2 交换对（extras 越界/-1 哨兵在纯函数层已剔除）。
   *  帧号必须取**数据面帧**（WorkScreen 的 displayIdx）——末帧收尾沿用前一
   *  帧快照时，事件也要对同一帧，否则会拿 A 帧的事件指 B 帧的格子。 */
  const pairList = $derived.by((): SwapPair[] => {
    if (frameIdx === undefined || frameIdx < 0 || elements.length === 0) return [];
    return swapPairs(session.eventsAt(frameIdx), elements.length, snap.name);
  });
  const pairCells = $derived(new Set(pairList.flatMap((p) => [p.a, p.b])));
  const hasSwapEvent = $derived(pairList.length > 0);
  const firstPair = $derived<SwapPair | null>(pairList[0] ?? null);

  /** 当前行出现的 `name[...]` 下标（局部变量求值；解析不了就不猜）。
   *  交换帧不参与「当前比较」指认——赋值行里的 a[j] 不是比较式。 */
  const focus = $derived.by(() => {
    if (hasSwapEvent) return [] as number[];
    const line = frame?.code_line ?? 0;
    const text = line > 0 ? (source.split("\n")[line - 1] ?? "") : "";
    if (!text || !snap.name) return [] as number[];
    const esc = snap.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`${esc}\\s*\\[([^\\]]+)\\]`, "g");
    const out: number[] = [];
    const vars = new Map((frame?.local_vars ?? []).map((v) => [v.name, Number(v.value)]));
    for (const m of text.matchAll(re)) {
      const expr = (m[1] ?? "").replace(/\s+/g, "");
      if (!expr) continue;
      // 只认 常量 / 标识符 / 标识符±常量（a[j]、a[j+1]、a[0]、a[n-1]）
      const toks = expr.match(/^([A-Za-z_]\w*|\d+)(?:([+-])(\d+))?$/);
      if (!toks) continue;
      const baseTok = toks[1];
      if (baseTok === undefined) continue;
      const base = /^\d+$/.test(baseTok) ? Number(baseTok) : vars.get(baseTok);
      if (base == null || !Number.isFinite(base)) continue;
      const off = toks[3];
      const idx = toks[2] !== undefined && off !== undefined ? base + (toks[2] === "-" ? -1 : 1) * Number(off) : base;
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

  const swapText = $derived(
    pairList.length === 0
      ? ""
      : "本帧交换 " + pairList.map((p) => `${snap.name}[${p.a}] ↔ ${snap.name}[${p.b}]`).join(" / "),
  );
  const metaText = $derived(
    (heldFrom >= 0 ? `末帧收尾 · 沿用第 ${heldFrom + 1} 帧 · ` : "") +
      (swapText
        ? swapText
        : focus.length > 0
          ? "当前比较 " + focus.map((i) => `${snap.name}[${i}]`).join(" / ")
          : "本帧无下标访问"),
  );

  // ⚠️ 模板里 `{/each}{#if …}{/if}</div>` 必须贴紧：Svelte 块之间的空白是
  // 文本节点，会让 E-08 golden 的归一化输出多出一个空格（实测；golden 不刷）。
  // ── 交换连线几何（两格中心之间的短横线；换行不画斜线）────────────
  let cellsEl: HTMLDivElement | undefined = $state();
  let cellsW = $state(0); // 布局宽度变化（窄屏换行/字号档）触发重量
  let cellEls: Array<HTMLDivElement | undefined> = [];
  let linkGeom = $state<{ left: number; top: number; width: number } | null>(null);

  $effect(() => {
    const p = firstPair;
    const host = cellsEl;
    void cellsW; // 依赖登记
    if (!p || !host) {
      linkGeom = null;
      return;
    }
    const ea = cellEls[p.a];
    const eb = cellEls[p.b];
    if (!ea || !eb) {
      linkGeom = null;
      return;
    }
    const hr = host.getBoundingClientRect();
    const ra = ea.getBoundingClientRect();
    const rb = eb.getBoundingClientRect();
    if (Math.abs(ra.top - rb.top) > 2) {
      linkGeom = null;
      return;
    }
    const left = Math.min(ra.right, rb.right) - hr.left;
    const right = Math.max(ra.left, rb.left) - hr.left;
    linkGeom = { left, width: Math.max(2, right - left), top: ra.bottom - hr.top - 6 };
  });

  function swapColor(): string {
    const v = getComputedStyle(document.documentElement).getPropertyValue("--vr-swap").trim();
    return v || "currentColor";
  }

  // 交换脉冲（WAAPI）：按「帧号 + 交换对」键控，同一对不因预算翻态重播；
  // 批量/scrub 时预算全关；播放期由计划表节拍门放行（D3 事件层：8fps 连续
  // 交换按 slow token 抽稀，不会每帧都闪）——静态高亮与连线始终在。
  // 记账必须先于预算裁决：effect 订阅了 batching/playing（allowPulse 读 $state），
  // 预算解除会让 effect 重跑——先记账才不会补播「让位期」那一帧（D0 锚）。
  let lastSwapKey = "";
  $effect(() => {
    const pairs = pairList;
    if (pairs.length === 0) return;
    const key = `${snap.name}|${frameIdx ?? -1}|` + pairs.map((p) => `${p.a}-${p.b}`).join(",");
    if (key === lastSwapKey) return;
    const els = pairs
      .flatMap((p) => [cellEls[p.a], cellEls[p.b]])
      .filter((el): el is HTMLDivElement => el !== undefined);
    if (els.length === 0) return;
    lastSwapKey = key;
    if (!motion.allowPulse("swap", snap.name)) return;
    const color = swapColor();
    for (const el of els) {
      pulse(
        el,
        [{ boxShadow: `inset 0 0 0 3px ${color}` }, { boxShadow: `inset 0 0 0 1px ${color}` }],
        { tier: "slow", easing: "emphasis" },
      );
    }
  });
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
    <div
      class="vr-cells"
      role="list"
      aria-label="数组 {snap.name} 的索引格"
      bind:this={cellsEl}
      bind:clientWidth={cellsW}
      data-swap={hasSwapEvent ? pairList.map((p) => `${p.a}-${p.b}`).join(" ") : undefined}
    >
      {#each elements as v, i (i)}
        <div
          class="vr-cell"
          class:is-current={focus.includes(i)}
          class:is-sorted={numeric && i >= sortedFrom}
          class:is-swap={!hasSwapEvent && changed.has(i)}
          class:is-swap-event={hasSwapEvent && pairCells.has(i)}
          class:is-text={!numeric}
          role="listitem"
          aria-label="{snap.name}[{i}] = {isChar ? charCellText(v) : v}"
          data-swap-cell={pairCells.has(i) ? "1" : undefined}
          bind:this={cellEls[i]}
        >
          <span class="vr-idx">{snap.name}[{i}]</span>
          <span class="vr-val">{isChar ? charCellText(v) : v}</span>
          {#if numeric}
            <span class="vr-bar" style:height="{Math.round(Math.max((Math.abs(nums[i] ?? 0) / maxAbs) * 16, 2))}px"></span>
          {/if}
        </div>
      {/each}{#if linkGeom && firstPair}
        {#key `${snap.name}:${frameIdx}:${firstPair.a}-${firstPair.b}`}
          <span
            class="vr-swap-link"
            aria-hidden="true"
            data-from={firstPair.a}
            data-to={firstPair.b}
            style:left="{linkGeom.left}px"
            style:top="{linkGeom.top}px"
            style:width="{linkGeom.width}px"
          ></span>
        {/key}
      {/if}</div>
    <div class="vr-arrayfoot">
      <span class="vr-legend"><i class="is-cur"></i>当前比较</span>
      {#if hasSwapEvent}<span class="vr-legend" data-swap-legend><i class="is-swap"></i>本帧交换</span>{/if}
      <span class="vr-legend"><i class="is-sorted"></i>已就位</span>
      <span class="vr-note-mini">索引固定；交换时看格内值的变化。</span>
    </div>
  {/if}
</section>
