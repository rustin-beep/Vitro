<script lang="ts">
  // 局部变量（设计稿仪器「账本式表格」）：当前帧 local_vars 快照；
  // 值发生变化的名字左缘染琥珀细线（对比上一可视帧——语句级组尾帧口径）。
  // 地址列用引擎真实 addr（不伪造 0x… 占位）。
  // 可选 idx/heldFrom：末帧收尾帧（prog）沿用它之前有数据的帧时，块头如实
  // 标注「沿用第 N 帧」，读数不张冠李戴。
  // D2（#122）：行进出 gatedFade + 值变化 WAAPI 脉冲（预算外只留静态左缘线）。
  import { frameAt, session } from "../session.svelte.ts";
  import { gatedFade, motion, pulse } from "./motion.svelte.ts";

  let { idx = -1, heldFrom = -1 }: { idx?: number; heldFrom?: number } = $props();

  const at = $derived(idx >= 0 ? idx : session.idx);
  const vars = $derived(frameAt(at)?.local_vars ?? []);
  const prev = $derived(at > 0 ? (frameAt(at - 1)?.local_vars ?? []) : []);
  function changed(name: string, value: string): boolean {
    const p = prev.find((v) => v.name === name);
    return !!p && p.value !== value;
  }

  let rowEls: Array<HTMLTableRowElement | undefined> = [];
  let flashKey = "";
  let flashPrimed = false;
  $effect(() => {
    const list = vars;
    const key = `${at}|` + list.map((v) => `${v.name}=${v.value}`).join("|");
    if (key === flashKey) return;
    flashKey = key;
    if (!flashPrimed) {
      flashPrimed = true; // 首帧是「进入页面」不是「值变了」，不闪
      return;
    }
    if (!motion.allowPulse("vars", "*")) return;
    const tint = getComputedStyle(document.documentElement).getPropertyValue("--vr-amber-tint").trim() || "transparent";
    for (let i = 0; i < list.length; i += 1) {
      const v = list[i];
      if (!v || !changed(v.name, v.value)) continue;
      pulse(rowEls[i], [{ backgroundColor: tint }, { backgroundColor: "transparent" }], { tier: "fast", easing: "emphasis" });
    }
  });
</script>

<section class="vr-block" aria-label="局部变量">
  <div class="vr-blockhead">
    <h2 class="vr-label">局部变量</h2>
    <span class="vr-spacer"></span>
    <span class="vr-meta">{session.viewFrames.length ? `帧 ${at + 1} 快照${heldFrom >= 0 ? ` · 末帧沿用` : ""}` : "未采集"}</span>
  </div>
  {#if vars.length}
    <table class="vr-vars">
      <thead>
        <tr><th>名称</th><th>类型</th><th>值</th><th>地址</th></tr>
      </thead>
      <tbody>
        {#each vars as v, vi (`${v.name}#${vi}`)}
          <tr class:is-changed={changed(v.name, v.value)} transition:gatedFade bind:this={rowEls[vi]}>
            <td>{v.name}</td>
            <td class="vr-dim">{v.ty_name}</td>
            <td>{v.value}</td>
            <td class="vr-dim">0x{(v.addr || 0).toString(16)}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {:else}
    <p class="vr-empty">（此帧无局部变量）</p>
  {/if}
</section>
