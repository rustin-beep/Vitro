<script lang="ts">
  // 会话配置面板（A3/A4/A5/A6，#140——旧栈 .cfg-details/.cfg-msg/cfg-view
  // 语义平移）：确定性 / 步数上限 / 调用深度 / 隔离区预算四项可写 + 应用
  // （config.set + config.get 回读）；argv 输入（空格分隔，run 通道携带）；
  // cfg-msg 反馈行（含用例 configHint 覆盖提示——collect 时写入 session）。
  // 面板默认折叠（旧栈 <details> 同形态）。
  import { session, applyCfg } from "../session.svelte.ts";
</script>

<details class="scfg">
  <summary>会话配置（CONFIG.SET）</summary>
  <div class="scfg-grid">
    <label class="scfg-item">
      <input type="checkbox" bind:checked={session.cfg.deterministic} /> 确定性模式
    </label>
    <label class="scfg-item">步数上限
      <input type="number" bind:value={session.cfg.max_steps} min="1000" step="1000" />
    </label>
    <label class="scfg-item">调用深度
      <input type="number" bind:value={session.cfg.call_depth_limit} min="10" step="10" />
    </label>
    <label class="scfg-item">隔离区预算
      <input type="number" bind:value={session.cfg.quarantine_budget} min="0" step="4096" />
    </label>
    <button type="button" class="btn ghost scfg-apply" onclick={applyCfg}>应用</button>
  </div>
  <label class="scfg-item scfg-argv">argv
    <input type="text" bind:value={session.argvText} placeholder="程序参数（空格分隔，可留空）" />
  </label>
  {#if session.cfgMsg}<p class="scfg-msg">{session.cfgMsg}</p>{/if}
  {#if session.appliedCfg}
    <pre class="scfg-view">{JSON.stringify(session.appliedCfg, null, 2)}</pre>
  {/if}
</details>

<style>
  .scfg { margin-top: 8px; font-size: 12.5px; }
  .scfg summary { cursor: pointer; color: var(--t2); user-select: none; }
  .scfg-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px 12px; margin-top: 8px; }
  .scfg-item { display: flex; align-items: center; gap: 6px; color: var(--t2); }
  .scfg-item input[type="number"] { width: 100%; min-width: 0; font: 12px var(--mono); color: var(--t1); background: var(--pane); border: 1px solid var(--hairline); border-radius: 6px; padding: 4px 6px; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .scfg-item input[type="checkbox"] { accent-color: var(--accent); }
  .scfg-apply { justify-self: start; }
  .scfg-argv { margin-top: 8px; }
  .scfg-argv input { flex: 1 1 auto; min-width: 0; font: 12px var(--mono); color: var(--t1); background: var(--pane); border: 1px solid var(--hairline); border-radius: 6px; padding: 4px 8px; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .scfg-msg { margin: 8px 0 0; font-size: 12px; color: var(--accent-strong); }
  .scfg-view { margin: 8px 0 0; padding: 8px 10px; font: 11.5px var(--mono); color: var(--t2); background: var(--pane); border: 1px solid var(--hairline); border-radius: 6px; overflow: auto; max-height: 180px; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
</style>
