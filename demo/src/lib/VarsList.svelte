<script lang="ts">
  // 局部变量表——当前帧 local_vars（值变化行走 row-flash；框架差分下
  // 同一 tr 节点复用，flash 动画只在值真变时重触发，手写栈里要自己维护）。
  import { frameAt, session } from "../session.svelte.ts";

  const vars = $derived(frameAt(session.idx)?.local_vars ?? []);
</script>

{#if vars.length}
  <table class="vars-table">
    <thead>
      <tr><th>名称</th><th>类型</th><th>值</th><th>地址</th></tr>
    </thead>
    <tbody>
      {#each vars as v (v.name)}
        <tr><td>{v.name}</td><td>{v.ty_name}</td><td>{v.value}</td><td>0x{(v.addr || 0).toString(16)}</td></tr>
      {/each}
    </tbody>
  </table>
{:else}
  <p class="muted">（此帧无局部变量）</p>
{/if}
