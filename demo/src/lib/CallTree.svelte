<script lang="ts">
  // 调用树（F4 组件迁移，审阅 C 处方）：keyed SVG——每帧只翻 cur/visited
  // class。visited 语义修正：旧栈 lastStep!==undefined 恒真（时间通道死码）——
  // 新栈 = 当前帧 frameNode 沿 parent 上溯祖先集（随帧真生长）。
  //
  // 窗口跟踪 = **viewBox 当相机**（2026-10-16 第三版）：CSS transform 与
  // viewBox 相乘产生双重变换歧义（前两版空画布/位置漂移，坐标推演三轮无
  // 区分性证据——按收敛速率纪律换架构）。viewBox 是相机唯一真相：
  //   zoom（缩放）+ center（内容坐标焦点）→ viewBox 派生，无叠加变换类。
  //   初始化：小树（fit ≥ 0.75）完整居中不跟随；大树固定 0.75 + 跟随当前帧。
  //   交互：滚轮锚点缩放 [0.15, 3]、拖拽平移（内容坐标随缩放折算）、
  //   双击恢复、跟随按钮。数据流不改 follow（旧栈病不带入）。
  import type { CallTree } from "../../js/calltree.ts";
  import { layoutCallTree } from "./calltreeLayout.ts";
  import { SvelteSet } from "svelte/reactivity";

  let { tree, idx }: { tree: CallTree | null; idx: number } = $props();

  let wrapEl: HTMLDivElement | undefined = $state();
  let wrapW = $state(0); // bind:clientWidth
  const WRAP_H = 300;
  // 相机双层（2026-10-16 用户诉求「瞬移改过渡动画」）：viewBox 是属性无法
  // CSS transition——**逻辑目标态（target）与渲染相机（cam）分离**，rAF
  // 指数趋近（rate 14/s ≈ 260ms 到位 95%）；手势直接双写（跟手无动画）。
  // 播放跟随：target 每帧跳、cam 指数追——天然平滑跟随（旧栈 CSS transition
  // 同效果，viewBox 相机下的等价实现）。
  let target = $state({ k: 0.75, cx: 0, cy: 0 });
  let cam = $state({ k: 0.75, cx: 0, cy: 0 });
  let follow = $state(true);
  let dragging = $state(false);
  let initedFor = $state("");

  const layout = $derived(layoutCallTree(tree?.root ?? null));
  const curNode = $derived(tree && tree.frameNode[idx] ? tree.frameNode[idx] : null);
  const curPos: { x: number; y: number; node: object } | null = $derived(
    curNode && layout ? layout.nodes.find((n) => n.node === curNode) ?? null : null,
  );
  const visitedSet = $derived.by(() => {
    const s = new SvelteSet<object>();
    let n: typeof curNode = curNode;
    while (n) {
      s.add(n);
      n = n.parent;
    }
    return s;
  });
  const isVisited = (n: object): boolean => visitedSet.has(n);

  const viewBox = $derived.by(() => {
    if (!layout || !wrapW) return null;
    const vw = wrapW / cam.k;
    const vh = WRAP_H / cam.k;
    return `${cam.cx - vw / 2} ${cam.cy - vh / 2} ${vw} ${vh}`;
  });

  // rAF 指数趋近循环（cam → target）：挂载启动、组件销毁取消
  $effect(() => {
    let raf = 0;
    let last = performance.now();
    const tick = (now: number): void => {
      const dt = Math.min((now - last) / 1000, 0.05);
      last = now;
      const f = 1 - Math.exp(-14 * dt); // rate 14/s
      const dx = target.cx - cam.cx;
      const dy = target.cy - cam.cy;
      const dk = target.k - cam.k;
      if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5 || Math.abs(dk) > 0.002) {
        cam.cx += dx * f;
        cam.cy += dy * f;
        cam.k += dk * f;
      } else if (dx || dy || dk) {
        cam.cx = target.cx;
        cam.cy = target.cy;
        cam.k = target.k;
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  });

  // 新采集（布局换引用）→ 初始化相机：小树完整居中不跟随；大树 0.75 + 跟随当前帧
  $effect(() => {
    if (!layout || !wrapW) return;
    const key = `${layout.width}x${layout.height}#${layout.nodes.length}`;
    if (initedFor === key) return;
    initedFor = key;
    const fit = Math.min(wrapW / layout.width, WRAP_H / layout.height);
    if (fit >= 0.75) {
      target = { k: fit, cx: layout.width / 2, cy: layout.height / 2 };
      follow = false;
    } else {
      target = { k: 0.75, cx: 0, cy: 0 };
      const cp = layout.nodes.find((n) => n.node === (tree?.frameNode[idx] ?? null));
      if (cp) target.cx = cp.x, (target.cy = cp.y);
      follow = true;
    }
  });

  // 跟随（follow=true）：相机目标焦点移到当前帧节点（cam 由 rAF 趋近——平滑跟随）
  $effect(() => {
    void idx;
    if (!follow || !curPos) return;
    target.cx = curPos.x;
    target.cy = curPos.y;
  });

  function fitAll(): void {
    if (!layout || !wrapW) return;
    const fit = Math.min(wrapW / layout.width, WRAP_H / layout.height);
    target = { k: fit, cx: layout.width / 2, cy: layout.height / 2 };
    follow = follow && fit < 0.75;
  }

  function onWheel(e: WheelEvent): void {
    e.preventDefault();
    const rect = wrapEl!.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    // 鼠标位置的内容坐标（缩放前）——缩放后保持不动（锚点）；手势双写 cam+target（跟手）
    const contentX = cam.cx + (mx - wrapW / 2) / cam.k;
    const contentY = cam.cy + (my - WRAP_H / 2) / cam.k;
    const k2 = Math.max(0.15, Math.min(3, cam.k * (1 - e.deltaY * 0.0012)));
    target = { k: k2, cx: contentX - (mx - wrapW / 2) / k2, cy: contentY - (my - WRAP_H / 2) / k2 };
    cam = { ...target };
    follow = false;
  }

  let dragFrom = { x: 0, y: 0, cx: 0, cy: 0 };
  function onPointerDown(e: PointerEvent): void {
    dragging = true;
    dragFrom = { x: e.clientX, y: e.clientY, cx: target.cx, cy: target.cy };
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
  }
  function onPointerMove(e: PointerEvent): void {
    if (!dragging) return;
    follow = false;
    const cx = dragFrom.cx - (e.clientX - dragFrom.x) / cam.k;
    const cy = dragFrom.cy - (e.clientY - dragFrom.y) / cam.k;
    target = { k: cam.k, cx, cy };
    cam = { k: cam.k, cx, cy };
  }
  function onPointerUp(): void {
    dragging = false;
  }
  function onDblClick(): void {
    fitAll();
    if (follow) {
      const cp = curPos;
      if (cp) target.cx = cp.x, (target.cy = cp.y);
    }
  }
  function enableFollow(): void {
    follow = true;
    const cp = curPos;
    if (cp) target.cx = cp.x, (target.cy = cp.y);
  }
</script>

<div class="tree-wrap" bind:this={wrapEl} bind:clientWidth={wrapW}>
  {#if layout && viewBox}
    <div class="toolbar">
      <button type="button" class="tool" class:on={follow} onclick={enableFollow} title="跟随当前帧节点">◉ 跟随{follow ? "中" : ""}</button>
      <button type="button" class="tool" onclick={fitAll} title="整树适应窗口">⤢ 全览</button>
      <span class="hint">滚轮缩放 · 拖拽平移 · 双击恢复</span>
    </div>
    <!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
    <div
      class="tree-viewport"
      class:grabbing={dragging}
      onwheel={onWheel}
      onpointerdown={onPointerDown}
      onpointermove={onPointerMove}
      onpointerup={onPointerUp}
      onpointercancel={onPointerUp}
      ondblclick={onDblClick}
      role="img"
      aria-label="调用树画布（滚轮缩放、拖拽平移、双击恢复跟随）"
    >
      <svg viewBox={viewBox} width={wrapW} height={WRAP_H}>
        {#each layout.edges as e (e.id)}
          <path class="edge" class:walked={isVisited(e.from) && isVisited(e.to)} d={e.path} />
        {/each}
        {#each layout.nodes as n (n.id)}
          <g class="nd" class:cur={n.node === curNode} class:visited={isVisited(n.node)}>
            <rect x={n.x - 39} y={n.y - 18} width="78" height="36" rx="9" />
            <text class="tname" x={n.x} y={n.y - 1}>{n.label}</text>
            {#if n.arg}<text class="targ" x={n.x} y={n.y + 12}>{n.arg}</text>{/if}
          </g>
        {/each}
      </svg>
    </div>
  {:else}
    <p class="muted">（采集后显示调用树）</p>
  {/if}
</div>

<style>
  .tree-wrap { border: 1px solid var(--hairline); border-radius: 8px; background: var(--editor-bg); overflow: hidden; }
  .toolbar { display: flex; align-items: center; gap: 10px; padding: 5px 10px; border-bottom: 1px solid var(--hairline); }
  .tool { background: var(--pane); color: var(--t2); border: 1px solid var(--hairline); border-radius: 6px; padding: 3px 10px; font: 12px var(--font-ui); cursor: pointer; }
  .tool.on { color: var(--accent-strong); border-color: var(--accent); }
  .hint { font-size: 11px; color: var(--t3); }
  .tree-viewport { height: 300px; overflow: hidden; touch-action: none; cursor: grab; }
  .tree-viewport.grabbing { cursor: grabbing; }
  .tree-viewport svg { display: block; /* 视口尺寸 = width/height 属性（相机窗口），内容坐标由 viewBox 映射——CSS 尺寸覆盖会造成双重变换（2026-10-16 空画布实锤） */ }
  .edge { stroke: var(--delimiter); stroke-width: 1.5; fill: none; opacity: 0.55; vector-effect: non-scaling-stroke; }
  .edge.walked { stroke: var(--accent); stroke-width: 2; opacity: 1; }
  .nd rect { fill: var(--pane); stroke: var(--hairline); stroke-width: 1.2; transition: fill var(--t-fast) var(--ease-out), stroke var(--t-fast) var(--ease-out); }
  /* mono 面连字关闭（#121①——demo_ui_lint 检查 D 机判；树节点文本含 <= 等教学符号，连字替换即教学硬伤） */
  .nd text { text-anchor: middle; font-family: var(--mono); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .nd .tname { fill: var(--t1); font-size: 11.5px; font-weight: 600; }
  .nd .targ { fill: var(--t3); font-size: 10px; }
  .nd.cur rect { stroke: var(--accent); stroke-width: 2; fill: var(--accent-tint); }
  .nd.visited rect { stroke: var(--accent); }
  .muted { color: var(--t3); font-size: 12.5px; }
</style>
