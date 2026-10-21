<script lang="ts">
  // 调用树（设计稿 P1-4 / P2-7 / P2-8 / B-2 / B-4）：
  //   - **fit-first**：整树可容纳（fit ≥ 0.95）时保持全览 + 当前节点高亮；
  //     只有大树（fib/dfs）才以当前节点为中心 1.22× 取景——跟随即取景，
  //     不再把可容纳的小树放大裁边（A-1 的病）；
  //   - 执行信息内嵌在树容器左栏（rail）：L{n} + 当前语句 + 帧/函数/局部变量
  //     + 3 行源码片段（可展开到 7 行）——便签不再悬空在树外；
  //   - 390：SVG 隐藏，改渲染调用路径链（同一棵树数据推导，不写第二份）；
  //   - 滚轮锚点缩放 / 拖拽平移 / 双击复位（保留旧栈手势能力，相机单一真相）。
  import type { CallTree } from "../../js/calltree.ts";
  import { session, frameAt } from "../session.svelte.ts";
  import { layoutCallTree } from "./calltreeLayout.ts";
  import { SvelteSet } from "svelte/reactivity";
  import { ui } from "../ui.svelte.ts";

  let { tree, idx, source }: { tree: CallTree | null; idx: number; source: string } = $props();

  const H = 214;
  let wrapEl: HTMLDivElement | undefined = $state();
  let wrapW = $state(0);

  const layout = $derived(layoutCallTree(tree?.root ?? null));
  // 浅树压扁（#222 P1 第三片，2026-10-21）：节点 ≤3（prog → main 一族）时
  // 画布没有信息量却吃 214px 高——压成一行面包屑 + 当前语句，把首屏让给
  // 数组/变量/输出。深树（fib/dfs/递归）保持原画布。
  const compact = $derived(!!layout && layout.nodes.length <= 3);
  const frame = $derived(frameAt(idx));
  const curNode = $derived(tree && tree.frameNode[idx] ? tree.frameNode[idx] : null);
  const curPos = $derived(curNode && layout ? (layout.nodes.find((n) => n.node === curNode) ?? null) : null);

  /** DFS 序里同名节点出现次数（节点标签 `printf #3` 与 footer `×5` 同源）。 */
  const nameCount = $derived.by(() => {
    const m = new Map<string, number>();
    for (const n of layout?.nodes ?? []) m.set(n.label, (m.get(n.label) ?? 0) + 1);
    return m;
  });
  const nameSeq = $derived.by(() => {
    const seq = new Map<string, number>();
    const out = new Map<string, number>();
    for (const n of layout?.nodes ?? []) {
      const k = (seq.get(n.label) ?? 0) + 1;
      seq.set(n.label, k);
      out.set(n.id, k);
    }
    return out;
  });

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

  /** 当前节点祖先链（footer 路径 / 390 路径链 / 面包屑）。 */
  const pathNames = $derived.by(() => {
    const out: string[] = [];
    let n: typeof curNode = curNode;
    while (n) {
      out.unshift(n.name);
      n = n.parent;
    }
    return out;
  });
  const pathText = $derived.by(() => {
    if (!pathNames.length) return "";
    return pathNames
      .map((name, i) => {
        const count = nameCount.get(name) ?? 1;
        // 末段重复出现（如 5 次 printf）标 ×N——一眼看出「这是第几个调用」
        return i === pathNames.length - 1 && count > 1 ? `${name} ×${count}` : name;
      })
      .join(" → ");
  });

  // ── 相机 ─────────────────────────────────────────────────
  const fit = $derived(layout && wrapW > 0 ? Math.min(wrapW / layout.width, H / layout.height) : 1);
  let mode = $state<"follow" | "overview">("follow");
  let manual = $state<{ k: number; cx: number; cy: number } | null>(null);
  let dragging = $state(false);

  // fit-first：可容纳时按 1:1（≤1）整树居中——放大会让 2 节点树的字比设计稿大；
  // 大树才以当前节点为中心 1.22× 取景。
  const autoK = $derived(fit >= 0.95 ? Math.min(fit, 1) : 1.22);
  const k = $derived(manual?.k ?? (mode === "overview" ? fit : autoK));

  function clampCam(cx: number, cy: number, kk: number): { cx: number; cy: number } {
    if (!layout) return { cx, cy };
    const vw = wrapW / kk;
    const vh = H / kk;
    return {
      cx: layout.width <= vw ? layout.width / 2 : Math.max(vw / 2, Math.min(layout.width - vw / 2, cx)),
      cy: layout.height <= vh ? layout.height / 2 : Math.max(vh / 2, Math.min(layout.height - vh / 2, cy)),
    };
  }
  const cam = $derived.by(() => {
    if (!layout) return { k: 1, cx: 0, cy: 0 };
    const kk = k;
    const wantX = manual ? manual.cx : mode === "overview" ? layout.width / 2 : (curPos?.x ?? layout.width / 2);
    const wantY = manual ? manual.cy : mode === "overview" ? layout.height / 2 : (curPos?.y ?? layout.height / 2);
    const c = clampCam(wantX, wantY, kk);
    return { k: kk, cx: c.cx, cy: c.cy };
  });
  const viewBox = $derived.by(() => {
    if (!layout || wrapW <= 0) return null;
    const vw = wrapW / cam.k;
    const vh = H / cam.k;
    return `${cam.cx - vw / 2} ${cam.cy - vh / 2} ${vw} ${vh}`;
  });

  function overview(): void {
    mode = "overview";
    manual = null;
  }
  function followCur(): void {
    mode = "follow";
    manual = null;
  }
  function zoomBy(factor: number): void {
    const nx = Math.max(Math.min(fit * 0.85, 1), Math.min(3, cam.k * factor));
    manual = { k: nx, cx: cam.cx, cy: cam.cy };
  }
  function onWheel(e: WheelEvent): void {
    e.preventDefault();
    const rect = wrapEl!.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const contentX = cam.cx + (mx - wrapW / 2) / cam.k;
    const contentY = cam.cy + (my - H / 2) / cam.k;
    const nk = Math.max(Math.min(fit * 0.85, 1), Math.min(3, cam.k * (1 - e.deltaY * 0.0012)));
    const next = clampCam(contentX - (mx - wrapW / 2) / nk, contentY - (my - H / 2) / nk, nk);
    manual = { k: nk, cx: next.cx, cy: next.cy };
  }
  let dragFrom = { x: 0, y: 0, cx: 0, cy: 0 };
  function down(e: PointerEvent): void {
    if (!layout) return;
    dragging = true;
    dragFrom = { x: e.clientX, y: e.clientY, cx: cam.cx, cy: cam.cy };
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
  }
  function move(e: PointerEvent): void {
    if (!dragging || !layout) return;
    const nx = dragFrom.cx - (e.clientX - dragFrom.x) / cam.k;
    const ny = dragFrom.cy - (e.clientY - dragFrom.y) / cam.k;
    const c = clampCam(nx, ny, cam.k);
    manual = { k: cam.k, cx: c.cx, cy: c.cy };
  }
  function up(): void {
    dragging = false;
  }

  // ── rail：源码片段 ──────────────────────────────────────────
  const line = $derived(frame?.code_line ?? 0);
  const curText = $derived(line > 0 ? (source.split("\n")[line - 1] ?? "").trim() : "");
  const railVars = $derived((frame?.local_vars ?? []).slice(0, 2).map((v) => `${v.name} = ${v.value}`).join(" · "));
  const srcLines = $derived.by(() => {
    if (line <= 0 || !source) return [] as Array<{ n: number; t: string; cur: boolean }>;
    const all = source.split("\n");
    const span = ui.railExpanded ? 3 : 1;
    const lo = Math.max(0, line - 1 - span);
    const hi = Math.min(all.length, line + span);
    return all.slice(lo, hi).map((t, i) => ({ n: lo + i + 1, t, cur: lo + i + 1 === line }));
  });
  const railed = $derived(!!frame);
  const followNote = $derived(mode === "overview" ? "全览 · fit" : manual ? "手工 · 取景" : fit >= 0.95 ? "跟随 · 节点高亮" : "跟随 · 节点居中");
  const zoomPct = $derived(Math.round(cam.k * 100));
</script>

<section class="vr-block" aria-label="调用树">
  <div class="vr-blockhead">
    <h2 class="vr-label">调用树</h2>
    {#if !compact}
      <div class="vr-seg" role="group" aria-label="取景">
        <button type="button" class:is-active={mode === "follow" && !manual} onclick={followCur}>跟随</button>
        <button type="button" class:is-active={mode === "overview"} onclick={overview}>全览</button>
      </div>
      <div class="vr-zoom">
        <button type="button" onclick={() => zoomBy(1 / 1.18)} aria-label="缩小">−</button>
        <span>{zoomPct}%</span>
        <button type="button" onclick={() => zoomBy(1.18)} aria-label="放大">+</button>
      </div>
    {/if}
    <span class="vr-spacer"></span>
    <span class="vr-meta">{layout ? `${layout.nodes.length} 个节点` : "未采集"}{compact ? " · 浅树压扁" : ""}</span>
  </div>

  {#if compact}
    <div class="vr-tree-compact" aria-label="调用路径">
      <span class="vr-tree-path">{pathText || "prog"}</span>
      <span class="vr-tree-line">{line > 0 ? `· L${line}` : railed ? "· 收尾" : "· —"}</span>
      <code class="vr-tree-code">{curText || (railed ? "程序已退出（末帧收尾）" : "（未采集帧流）")}</code>
      {#if railed}<span class="vr-tree-vars">{frame?.func_name}{#if railVars} · {railVars}{/if}</span>{/if}
    </div>
    <p class="vr-tree-note">栈深 ≤ 2 的课不画布：{pathText || "prog"} 只有库调用，递归课（如 global_struct 的 fib）才展开画布。</p>
  {:else}
    <div class="vr-treebox">
    <aside class="vr-rail" aria-label="当前执行">
      <span class="vr-rail-kicker">当前执行</span>
      <div class="vr-rail-line">{line > 0 ? `L${line}` : railed ? "收尾" : "—"}</div>
      <code class="vr-rail-code">{curText || (railed ? "程序已退出（末帧收尾）" : "（未采集帧流）")}</code>
      <div class="vr-rail-meta">
        {#if railed}第 {idx + 1} / {session.viewFrames.length} 帧 · <b>{frame?.func_name}</b>{#if railVars} · {railVars}{/if}{:else}采集后显示当前语句{/if}
      </div>
      {#if srcLines.length > 0}
        <pre class="vr-rail-src" aria-label="当前行附近的源码">{#each srcLines as s (s.n)}<span class="vr-src-line" class:is-cur={s.cur}><span class="ln">{String(s.n).padStart(3)}</span><span class="src">{s.t}</span></span>{/each}</pre>
        <button type="button" class="vr-rail-more" aria-expanded={ui.railExpanded} onclick={() => (ui.railExpanded = !ui.railExpanded)}>
          {ui.railExpanded ? "收起源码" : "展开源码"}
        </button>
      {/if}
    </aside>

    <div class="vr-canvas" class:is-dragging={dragging} bind:this={wrapEl} bind:clientWidth={wrapW}
      role="img" aria-label="调用树画布（滚轮缩放、拖拽平移）"
      onwheel={onWheel} onpointerdown={down} onpointermove={move} onpointerup={up} onpointercancel={up} ondblclick={followCur}
    >
      {#if layout && viewBox}
        <svg viewBox={viewBox} width={wrapW} height={H}>
          {#each layout.edges as e (e.id)}
            <path class="vr-edge" class:is-visited={isVisited(e.from) && isVisited(e.to)} d={e.path} />
          {/each}
          {#each layout.nodes as nd (nd.id)}
            <g class="vr-node" class:is-current={nd.node === curNode} class:is-visited={isVisited(nd.node)}>
              <rect x={nd.x - 39} y={nd.y - 14} width="78" height="28" rx="2" />
              <text x={nd.x} y={nd.y + 3.5}>{(nameCount.get(nd.label) ?? 0) > 1 ? `${nd.label} #${nameSeq.get(nd.id) ?? 1}` : nd.label}</text>
            </g>
          {/each}
        </svg>
        <div class="vr-tree-mobile" aria-label="调用路径">
          {#each pathNames as p, i (i)}
            <div class="vr-nodechip" class:is-current={i === pathNames.length - 1}>
              <span class="vr-conn"></span>
              <b>{p}</b>
              {#if i === pathNames.length - 1}<span class="vr-now">当前</span>{/if}
            </div>
          {/each}
        </div>
        {#if layout.nodes.length <= 3}
          <p class="vr-canvas-note">本课调用树只有 prog → main：printf 属库函数，不产生用户调用节点；递归课（如 global_struct 的 fib）才会长出大树。</p>
        {/if}
      {:else}
        <p class="vr-empty">（采集后显示调用树）</p>
      {/if}
    </div>
  </div>

  <div class="vr-treefoot">
    <span class="vr-path">{layout ? pathText || "prog" : "—"}</span>
    <span title="整树可容纳时保持全览；大树以当前节点为中心">{followNote}</span>
    <span class="vr-spacer"></span>
    {#if layout}
      <span>{session.breakpoints.length ? `断点 ${session.breakpoints.length} 处` : "无断点"}</span>
    {/if}
  </div>
  {/if}
</section>
