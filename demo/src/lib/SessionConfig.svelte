<script lang="ts">
  // 会话配置面板（实验参数条「展开」打开）：确定性 / 步数上限 / 调用深度 /
  // 隔离区预算四项可写 + 应用（config.set + config.get 回读）；argv 输入
  // （空格分隔，run 通道携带）；cfg-msg 反馈行（含用例 configHint 覆盖提示）。
  // 状态全部走 session 层；details 受控于 ui.scfgOpen（#287-①：argv 胶囊
  // 点开即展开，用户手动收/展经 bind 双向同步）。
  import { applyCfg, session } from "../session.svelte.ts";
  import { ui } from "../ui.svelte.ts";
</script>

<details class="scfg" bind:open={ui.scfgOpen}>
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
    <button type="button" class="ws-btn scfg-apply" onclick={applyCfg}>应用</button>
  </div>
  <label class="scfg-item scfg-argv">argv
    <input type="text" bind:value={session.argvText} placeholder="程序参数（空格分隔，可留空）" />
  </label>
  {#if session.cfgMsg}<p class="scfg-msg">{session.cfgMsg}</p>{/if}
  {#if session.appliedCfg}
    <pre class="scfg-view">{JSON.stringify(session.appliedCfg, null, 2)}</pre>
  {/if}
</details>
