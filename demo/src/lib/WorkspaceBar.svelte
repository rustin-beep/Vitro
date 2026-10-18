<script lang="ts">
  // 工作区条（实验参数条内的「文件」段）：打开本地文件夹入口 + 激活后
  // 目录名 / 文件 chips（active + dirty 圆点）/ 保存 / 关闭。
  // 类名 ws-* 是 E2E（W1–W10）锚点契约，换皮不动名。
  // 不支持 FSA 的浏览器整体不渲染（Chromium 桌面能力，同旧栈）。
  import {
    confirmCloseWorkspace, openWorkspace, saveActiveFile, switchTo, workspace, workspaceSupported,
  } from "./workspace.svelte.ts";

  let { onswitch }: { onswitch: (path: string, source: string) => void } = $props();
</script>

{#if workspaceSupported()}
  <div class="ws-bar">
    {#if !workspace.active}
      <button type="button" class="ws-btn ws-open" disabled={workspace.opening} onclick={async () => { const src = await openWorkspace(); if (src !== null) onswitch(workspace.activePath ?? "", src); }} title="打开本地 C 工程文件夹（读写本地文件；桌面 Chrome/Edge）">
        <svg viewBox="0 0 24 24" width="12" height="12" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 7a1.5 1.5 0 0 1 1.5-1.5h4l2 2h8A1.5 1.5 0 0 1 20.5 9v8a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 17z"/></svg>
        {workspace.opening ? "打开中…" : "打开文件夹"}
      </button>
    {:else}
      <span class="ws-name" title={workspace.dirName}>{workspace.dirName}（{workspace.files.length}）</span>
      {#each workspace.files as f (f.path)}
        <button
          type="button"
          class="ws-chip"
          class:on={f.path === workspace.activePath}
          class:dirty={workspace.dirtyPaths.has(f.path)}
          title={f.path + (workspace.dirtyPaths.has(f.path) ? "（未保存）" : "")}
          onclick={() => { const src = switchTo(f.path); if (src !== null) onswitch(f.path, src); }}
        >{f.path.split("/").pop() || f.path}<i class="dot"></i></button>
      {/each}
      <button type="button" class="ws-btn ws-save" disabled={!workspace.dirty} onclick={() => void saveActiveFile()} title="保存当前文件（Ctrl+S）">保存</button>
      <button type="button" class="ws-btn ws-close" onclick={() => confirmCloseWorkspace()} title="关闭工作区">关闭</button>
    {/if}
  </div>
{/if}
