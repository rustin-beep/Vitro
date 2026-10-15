<script lang="ts">
  // 设置面板（F4 组件迁移低风险批第二件）——全部状态消费 theme/persisted
  // 层（基建单源），本组件零直摸 documentElement/localStorage。档位
  // role=radiogroup + aria-checked（旧栈 seg 只翻 class、读屏不可达的
  // 审阅 B-P2-8 缺口在此还清）。
  import { KEYS, storeGet, storeSet } from "../persisted.svelte.ts";
  import { THEMES, NIGHT_THEMES, applyTheme, themeState, applyMotion, applyEditorFont, ED_FONT_STEPS } from "../theme.svelte.ts";

  let edFont = $state(storeGet(KEYS.edFont) || "14px");
  let motion = $state(storeGet(KEYS.motion) !== "off");

  // theme 状态单一源在 theme 层（themeState.current），本组件不持副本
  let theme = $derived(themeState.current);

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
  <div class="row">
    <span class="label">主题</span>
    <div class="seg" role="radiogroup" aria-label="主题">
      {#each THEMES as t (t)}
        <button type="button" role="radio" aria-checked={theme === t} class:selected={theme === t} onclick={() => pickTheme(t)}>{t}</button>
      {/each}
    </div>
    <button type="button" class="btn ghost" onclick={quickToggle} title="夜↔日对切">◐</button>
  </div>
  <div class="row">
    <span class="label">编辑器字号</span>
    <div class="seg" role="radiogroup" aria-label="编辑器字号">
      {#each ED_FONT_STEPS as px (px)}
        <button type="button" role="radio" aria-checked={edFont === px} class:selected={edFont === px} onclick={() => pickFont(px)}>{Number.parseInt(px, 10)}</button>
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
</div>

<style>
  .row { display: flex; align-items: center; gap: 10px; margin: 6px 0; flex-wrap: wrap; }
  .label { font-size: 12px; color: var(--t3); min-width: 70px; }
  .seg { display: inline-flex; border: 1px solid var(--hairline); border-radius: 8px; overflow: hidden; }
  .seg button { background: var(--pane); color: var(--t2); border: 0; padding: 5px 12px; font: 12px var(--font-ui); cursor: pointer; }
  .seg button + button { border-left: 1px solid var(--hairline); }
  .seg button.selected { background: var(--accent-tint); color: var(--accent-strong); }
</style>
