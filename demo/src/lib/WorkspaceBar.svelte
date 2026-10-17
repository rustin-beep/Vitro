<script lang="ts">
  // 工作区条（F4 残留②：旧栈 ws-bar/ws-open 形态的新栈迁移）——打开文件夹
  // 入口 + 激活后：目录名 / 文件 chips（active + dirty 圆点）/ 保存 / 关闭。
  // 不支持 FSA 的浏览器整体不渲染（无降级——Chromium 桌面能力，同旧栈）；
  // 移动端 ≤960px CSS 隐藏（同旧栈 ws-ui 纪律）。
  // 切换文件：store 只返回新源码，写入编辑器 source 由父层（App 持有
  // editorRef/source 单源）经 onswitch 回调完成——组件不直摸编辑器。
  import {
    confirmCloseWorkspace, openWorkspace, saveActiveFile, switchTo, workspace, workspaceSupported,
  } from "./workspace.svelte.ts";

  let { onswitch }: { onswitch: (path: string, source: string) => void } = $props();
</script>

{#if workspaceSupported()}
  <div class="ws-bar">
    <button type="button" class="btn ghost ws-open" disabled={workspace.opening} onclick={async () => { const src = await openWorkspace(); if (src !== null) onswitch(workspace.activePath ?? "", src); }} title="打开本地 C 工程文件夹（读写本地文件；桌面 Chrome/Edge）">
      <svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 7a1.5 1.5 0 0 1 1.5-1.5h4l2 2h8A1.5 1.5 0 0 1 20.5 9v8a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 17z"/></svg>
      {workspace.opening ? "打开中…" : "打开文件夹"}
    </button>
    {#if workspace.active}
      <span class="ws-name" title={workspace.dirName}>{workspace.dirName}（{workspace.files.length}）</span>
      <div class="ws-files">
        {#each workspace.files as f (f.path)}
          <button
            type="button"
            class="ws-chip"
            class:on={f.path === workspace.activePath}
            class:dirty={workspace.dirtyPaths.has(f.path)}
            title={f.path + (workspace.dirtyPaths.has(f.path) ? "（未保存）" : "")}
            onclick={() => { const src = switchTo(f.path); if (src !== null) onswitch(f.path, src); }}
          >{f.path.split("/").pop() || f.path}<i class="ws-dot"></i></button>
        {/each}
      </div>
      <button type="button" class="btn ghost ws-save" disabled={!workspace.dirty} onclick={() => void saveActiveFile()} title="保存当前文件（Ctrl+S）">保存</button>
      <button type="button" class="btn ghost ws-close" onclick={() => confirmCloseWorkspace()} title="关闭工作区">✕ 关闭</button>
    {/if}
  </div>
{/if}

<style>
  .ws-bar { display: flex; align-items: center; gap: 8px; margin: 4px 0 8px; flex-wrap: wrap; }
  .ws-open { display: inline-flex; align-items: center; gap: 6px; flex: none; }
  .ws-open svg { flex: none; }
  .ws-name { font-size: 12px; color: var(--t3); flex: none; max-width: 140px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ws-files { display: flex; gap: 6px; overflow-x: auto; flex: 1 1 auto; min-width: 0; padding: 2px; scrollbar-width: thin; }
  .ws-chip { background: var(--pane); color: var(--t3); border: 1px solid var(--hairline); border-radius: 12px; padding: 2px 10px; font-size: 12px; font-family: var(--mono); white-space: nowrap; flex: none; display: inline-flex; align-items: center; gap: 5px; cursor: pointer; font-variant-ligatures: none; }
  .ws-chip:hover { color: var(--t1); border-color: var(--t3); }
  .ws-chip.on { color: var(--t1); border-color: var(--accent); background: var(--accent-tint); }
  .ws-chip .ws-dot { display: none; width: 6px; height: 6px; border-radius: 50%; background: var(--num); flex: none; }
  .ws-chip.dirty .ws-dot { display: block; }
  .ws-save, .ws-close { padding: 4px 12px; font-size: 12px; flex: none; }
  /* 移动端入口整体隐藏（无降级——FSA 是 Chromium 桌面能力；同旧栈 ws-ui） */
  @media (max-width: 960px) { .ws-bar { display: none; } }
</style>
