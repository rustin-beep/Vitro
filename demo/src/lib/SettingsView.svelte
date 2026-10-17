<script lang="ts">
  // 设置面板（F4 组件迁移低风险批第二件）——全部状态消费 theme/persisted
  // 层（基建单源），本组件零直摸 documentElement/localStorage。档位
  // role=radiogroup + aria-checked（旧栈 seg 只翻 class、读屏不可达的
  // 审阅 B-P2-8 缺口在此还清）。
  // V3/V4 质感批（#141，用户拍板「恢复之前样式——现在的太简陋」）：主题
  // 段恢复旧栈三色点卡形态（中文名 + 昼/夜角标 + win/accent/t1 三色预览，
  // 色面字面量豁免同旧栈 heron 豁免⑥口径）；字号档文案恢复「小/中/大」；
  // seg 容器化（--field 底 + 内按钮 hover/selected 态，对齐旧栈 .seg）。
  import { session, setReplayWide } from "../session.svelte.ts";
  import { KEYS, storeGet, storeSet } from "../persisted.svelte.ts";
  import { NIGHT_THEMES, applyTheme, themeState, applyMotion, applyEditorFont, ED_FONT_STEPS } from "../theme.svelte.ts";

  let edFont = $state(storeGet(KEYS.edFont) || "14px");
  let motion = $state(storeGet(KEYS.motion) !== "off");

  // theme 状态单一源在 theme 层（themeState.current），本组件不持副本
  let theme = $derived(themeState.current);

  // 主题卡元数据（中文名/昼夜/三色预览 = win-bg/accent/t1，照旧栈
  // index.html .tcard 逐字；色面字面量为展示预览豁免——渲染当前值无意义，
  // 三色点要的是目标主题的色板印象）
  const TCARDS: Array<{ v: string; name: string; dn: string; dots: [string, string, string] }> = [
    { v: "ice", name: "明亮实验室", dn: "昼", dots: ["#f2f7fd", "#2563eb", "#1a2740"] },
    { v: "rose", name: "奶油手账", dn: "昼", dots: ["#fbf5f7", "#d4597a", "#2e2428"] },
    { v: "paper", name: "牛皮档案", dn: "昼", dots: ["#f2eee6", "#a67d48", "#080a08"] },
    { v: "glass", name: "深夜书房", dn: "夜", dots: ["#0b1533", "#8b9cf5", "#eaf0ff"] },
    { v: "soft", name: "绒面深蓝", dn: "夜", dots: ["#0d1428", "#7a94e6", "#e6ebf7"] },
  ];
  const FONT_LABELS: Record<string, string> = { "13px": "小", "14px": "中", "16px": "大" };

  function pickTheme(v: string): void {
    applyTheme(v);
    storeSet(KEYS.theme, v);
  }
  function pickFont(px: string): void {
    edFont = px;
    applyEditorFont(px);
    storeSet(KEYS.edFont, px);
  }
  function pickMotion(on: boolean): void {
    motion = on;
    applyMotion(on);
    storeSet(KEYS.motion, on ? "on" : "off");
  }

  // 夜↔日快捷对切（theme-toggle 语义对齐现役：夜切 ice、日切 glass）
  function quickToggle(): void {
    pickTheme(NIGHT_THEMES.has(theme) ? "ice" : "glass");
  }
</script>

<div class="settings">
  <div class="row set-col">
    <span class="label">主题</span>
    <div class="theme-cards" role="radiogroup" aria-label="主题">
      {#each TCARDS as t (t.v)}
        <button type="button" role="radio" aria-checked={theme === t.v} class="tcard" class:on={theme === t.v} onclick={() => pickTheme(t.v)}>
          <span class="tc-dots"><i style:background={t.dots[0]}></i><i style:background={t.dots[1]}></i><i style:background={t.dots[2]}></i></span>
          <span class="tc-name">{t.name}</span>
          <span class="tc-dn">{t.dn}</span>
        </button>
      {/each}
    </div>
    <button type="button" class="btn ghost qtoggle" onclick={quickToggle} title="夜↔日对切">◐ 昼夜对切</button>
  </div>
  <div class="row">
    <span class="label">编辑器字号</span>
    <div class="seg" role="radiogroup" aria-label="编辑器字号">
      {#each ED_FONT_STEPS as px (px)}
        <button type="button" role="radio" aria-checked={edFont === px} class:selected={edFont === px} onclick={() => pickFont(px)}>{FONT_LABELS[px] ?? px}</button>
      {/each}
    </div>
  </div>
  <div class="row">
    <span class="label">界面动效</span>
    <div class="seg" role="radiogroup" aria-label="界面动效">
      <button type="button" role="radio" aria-checked={motion} class:selected={motion} onclick={() => pickMotion(true)}>开</button>
      <button type="button" role="radio" aria-checked={!motion} class:selected={!motion} onclick={() => pickMotion(false)}>关</button>
    </div>
  </div>
  <div class="row">
    <span class="label">回放全宽</span>
    <div class="seg" role="radiogroup" aria-label="回放全宽">
      <button type="button" role="radio" aria-checked={session.replayWide} class:selected={session.replayWide} onclick={() => setReplayWide(true)}>开</button>
      <button type="button" role="radio" aria-checked={!session.replayWide} class:selected={!session.replayWide} onclick={() => setReplayWide(false)}>关</button>
    </div>
  </div>
</div>

<style>
  .row { display: flex; align-items: center; gap: 10px; margin: 6px 0; flex-wrap: wrap; }
  .set-col { flex-direction: column; align-items: stretch; }
  .row + .row { border-top: 1px solid var(--hairline); padding-top: 8px; }
  .label { font-size: 12.5px; color: var(--t2); min-width: 70px; }
  .seg { display: inline-flex; background: var(--field); border: 1px solid var(--hairline); border-radius: 7px; padding: 2px; gap: 2px; }
  .seg button { background: transparent; color: var(--t2); border: 0; border-radius: 5px; padding: 3px 12px; font: 12px var(--font-ui); cursor: pointer; transition: background-color var(--t-fast) var(--ease-out), color var(--t-fast) var(--ease-out); }
  .seg button:hover { background: var(--accent-tint); color: var(--t1); }
  .seg button.selected { background: var(--accent-fill); color: var(--on-accent); }
  /* 主题三色点卡（V3 质感批：旧栈 .tcard 逐字平移） */
  .theme-cards { display: flex; flex-wrap: wrap; gap: 6px; }
  .tcard { position: relative; flex: 1 0 30%; background: var(--pane); border: 1px solid var(--hairline); border-radius: 8px; padding: 8px 6px 6px; display: flex; flex-direction: column; align-items: center; gap: 4px; color: var(--t2); font-size: 11px; cursor: pointer; transition: border-color var(--t-fast) var(--ease-out), box-shadow var(--t-fast) var(--ease-out), color var(--t-fast) var(--ease-out); }
  .tcard:hover { border-color: var(--t3); color: var(--t1); }
  .tcard.on { border-color: var(--accent); color: var(--t1); box-shadow: 0 0 0 1px var(--accent); }
  .tc-dots { display: flex; gap: 3px; }
  .tc-dots i { width: 10px; height: 10px; border-radius: 50%; border: 1px solid var(--hairline); }
  .tc-name { font-size: 11px; }
  .tc-dn { position: absolute; top: 3px; right: 5px; font-size: 9px; color: var(--t3); }
  .qtoggle { align-self: flex-start; }
</style>
