<script lang="ts">
  // 界面设置浮层（锚定在齿轮旁；实底不透明——设计稿 P2-1 / P2-5）。
  // 状态全部走 theme/persisted 层（唯一写入口），本组件不直摸
  // documentElement / localStorage。
  //
  // 五主题（2026-10-18 用户拍板）：明亮实验室 / 奶油手账 / 绒面深蓝
  // 三套旧色板原样 + 白天（纸） / 夜航图 两套设计稿新增。
  import { ui } from "../ui.svelte.ts";
  import { KEYS, THEME_KEYS, storeSet } from "../persisted.svelte.ts";
  import { SIZE_LABELS, SIZE_STEPS, THEME_DOTS, THEME_LABELS, applySize, applyTheme, themeState } from "../theme.svelte.ts";
  import { motion, setMotion } from "./motion.svelte.ts";

  function pickTheme(v: (typeof THEME_KEYS)[number]): void {
    applyTheme(v);
    storeSet(KEYS.theme, v);
  }
  function pickSize(px: string): void {
    applySize(px);
    storeSet(KEYS.size, px);
  }
  function reset(): void {
    pickTheme("paper");
    pickSize("14");
    setMotion(true);
  }
</script>

<div class="vr-popover" role="dialog" aria-label="界面设置">
  <div class="vr-pophead">
    <span>界面设置</span>
    <button type="button" class="vr-iconbtn" aria-label="关闭设置" onclick={() => (ui.settingsOpen = false)}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>
    </button>
  </div>

  <div class="vr-poprow is-col">
    <span class="vr-row-label">主题 · 五套</span>
    <div class="vr-themes" role="radiogroup" aria-label="主题">
      {#each THEME_KEYS as t (t)}
        <button
          type="button"
          role="radio"
          aria-checked={themeState.current === t}
          class="vr-theme-btn"
          class:is-active={themeState.current === t}
          onclick={() => pickTheme(t)}
          title={THEME_LABELS[t]}
        >
          <span class="vr-dot3" aria-hidden="true">
            <i style:background={THEME_DOTS[t][0]}></i><i style:background={THEME_DOTS[t][1]}></i><i style:background={THEME_DOTS[t][2]}></i>
          </span>
          <span>{THEME_LABELS[t]}</span>
        </button>
      {/each}
    </div>
  </div>

  <div class="vr-poprow">
    <span>字号</span>
    <div class="vr-seg" role="radiogroup" aria-label="字号">
      {#each SIZE_STEPS as px (px)}
        <button type="button" role="radio" aria-checked={themeState.size === px} class:is-active={themeState.size === px} onclick={() => pickSize(px)} title={SIZE_LABELS[px]}>
          {px}
        </button>
      {/each}
    </div>
  </div>

  <div class="vr-poprow">
    <span>动效</span>
    <button type="button" class="vr-switch" aria-pressed={motion.enabled} onclick={() => setMotion(!motion.enabled)}>
      {motion.enabled ? "开" : "关"}
    </button>
  </div>

  <div class="vr-poprow">
    <span>等宽连字</span>
    <span class="vr-popnote" style="margin:0">关（教学固定）</span>
  </div>

  <p class="vr-popnote">
    <b>主题迁移：</b>旧 glass 深夜书房 → 夜航图；旧 light → 明亮实验室；旧 paper 牛皮档案 → 白天（纸）。选择记在本机。
  </p>

  <div class="vr-poprow" style="padding-bottom:0">
    <button type="button" class="vr-linkbtn" onclick={reset}>恢复默认</button>
    <span class="vr-popnote" style="margin:0">不联网</span>
  </div>
</div>
