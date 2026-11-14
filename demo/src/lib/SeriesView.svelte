<script lang="ts">
  // SeriesView —— 课程声明驱动的参数化图形（demo 宿主绘制面，批 D 2026-11-14）。
  //
  // 边界：本组件只画 SVG；「画什么」由课程 `<!-- vitri-viz v1 -->` 声明 +
  // 引擎侧词表（projectors.ts）决定，分派与合法性校验在 viewProjection.ts。
  // 不按变量名猜场景、不内置任何领域知识（傅里叶只是 `series re im -> polar`
  // 的一条普通声明）。配色一律走 StylePack 语义槽（--vr-*），五主题自动换肤。
  import type { ArraySnapshot } from "../../js/types.ts";
  import type { VizDecl } from "./lessonMd.ts";

  let {
    decl,
    snaps,
    error,
  }: {
    decl: VizDecl;
    snaps: ArraySnapshot[];
    error: string | null;
  } = $props();

  const W = 320;
  const H = 132;
  const PAD = 16;
  const COLORS = ["s0", "s1", "s2", "s3", "s4"];

  function num(s: string): number | null {
    const v = Number.parseFloat(s);
    return Number.isFinite(v) ? v : null;
  }

  const gain = $derived.by(() => {
    const g = Number.parseFloat(decl.opts["gain"] ?? "1");
    return Number.isFinite(g) && g > 0 ? g : 1;
  });

  const series = $derived.by(() =>
    snaps.map((s) => ({
      name: s.name,
      values: s.elements.map((e) => (num(e) ?? 0) * gain),
      skipped: s.elements.filter((e) => num(e) === null).length,
    })),
  );

  const skipped = $derived(series.reduce((n, s) => n + s.skipped, 0));
  const total = $derived(series.reduce((n, s) => n + s.values.length, 0));

  type Shape =
    | { t: "bar"; x: number; y: number; w: number; h: number; idx: number }
    | { t: "poly"; points: string; cls: string }
    | { t: "ray"; x: number; y: number }
    | { t: "dot"; x: number; y: number }
    | { t: "tick"; x: number; label: string };

  const shapes = $derived.by((): Shape[] => {
    const out: Shape[] = [];
    const first = series[0]?.values ?? [];
    if (first.length === 0) return out;
    const innerW = W - 2 * PAD;
    const innerH = H - 2 * PAD;

    if (decl.projector === "bars" || decl.projector === "spectrum") {
      const max = Math.max(1, ...first.map((v) => Math.abs(v)));
      const bw = innerW / first.length;
      for (const [i, v] of first.entries()) {
        const h = (Math.abs(v) / max) * innerH;
        out.push({ t: "bar", x: PAD + i * bw + 1, y: H - PAD - h, w: Math.max(1, bw - 2), h, idx: i });
      }
      if (decl.projector === "spectrum") {
        const step = first.length > 12 ? Math.ceil(first.length / 6) : 1;
        for (let i = 0; i < first.length; i += step) {
          out.push({ t: "tick", x: PAD + (i + 0.5) * bw, label: String(i) });
        }
      }
      return out;
    }

    if (decl.projector === "line") {
      const all = series.flatMap((s) => s.values);
      const lo = Math.min(0, ...all);
      const hi = Math.max(1, ...all);
      const span = hi - lo || 1;
      for (const [k, s] of series.entries()) {
        const pts = s.values
          .map((v, i) => {
            const x = PAD + (s.values.length === 1 ? innerW / 2 : (i * innerW) / (s.values.length - 1));
            const y = H - PAD - ((v - lo) / span) * innerH;
            return `${x.toFixed(1)},${y.toFixed(1)}`;
          })
          .join(" ");
        out.push({ t: "poly", points: pts, cls: COLORS[k % COLORS.length] ?? "s0" });
      }
      return out;
    }

    if (decl.projector === "polar" && series.length >= 2) {
      const re = series[0]!.values;
      const im = series[1]!.values;
      const cx = W / 2;
      const cy = H / 2;
      const radius = Math.min(W, H) / 2 - PAD;
      const mag = Math.max(1, ...re.map((v, i) => Math.hypot(v, im[i] ?? 0)));
      const scale = radius / mag;
      for (let i = 0; i < re.length; i += 1) {
        const x = cx + (re[i] ?? 0) * scale;
        const y = cy - (im[i] ?? 0) * scale;
        out.push({ t: "ray", x, y });
        out.push({ t: "dot", x, y });
      }
      return out;
    }
    return out;
  });

  const label = $derived(`${decl.projector} · ${decl.series.join(" + ")}`);
  const meta = $derived(
    skipped > 0 ? `${total} 点 · ${skipped} 个非数值元素按 0 处理` : `${total} 点`,
  );
</script>

<section class="vr-block vr-viz" aria-label={`可视化 ${label}`}>
  <div class="vr-blockhead">
    <h2 class="vr-label">视图 {label}</h2>
    <span class="vr-spacer"></span>
    <span class="vr-meta">{meta}</span>
  </div>
  {#if error !== null}
    <p class="vr-empty vr-viz-error" role="status">{error}</p>
  {:else}
    <svg class="vr-viz-svg" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label} preserveAspectRatio="xMidYMid meet">
      <line class="vr-viz-axis" x1={PAD} y1={H - PAD} x2={W - PAD} y2={H - PAD} />
      {#if decl.projector === "polar"}
        <line class="vr-viz-axis" x1={W / 2} y1={PAD} x2={W / 2} y2={H - PAD} />
        <line class="vr-viz-axis" x1={PAD} y1={H / 2} x2={W - PAD} y2={H / 2} />
        <circle class="vr-viz-ring" cx={W / 2} cy={H / 2} r={Math.min(W, H) / 2 - PAD} />
      {/if}
      {#each shapes as sh, i (i)}
        {#if sh.t === "bar"}
          <rect class="vr-viz-bar" x={sh.x} y={sh.y} width={sh.w} height={sh.h} rx="2" />
        {:else if sh.t === "poly"}
          <polyline class={`vr-viz-line ${sh.cls}`} points={sh.points} />
        {:else if sh.t === "ray"}
          <line class="vr-viz-ray" x1={W / 2} y1={H / 2} x2={sh.x} y2={sh.y} />
        {:else if sh.t === "dot"}
          <circle class="vr-viz-dot" cx={sh.x} cy={sh.y} r="2.5" />
        {:else if sh.t === "tick"}
          <text class="vr-viz-text" x={sh.x} y={H - 3} font-size="9" text-anchor="middle">{sh.label}</text>
        {/if}
      {/each}
    </svg>
  {/if}
</section>
