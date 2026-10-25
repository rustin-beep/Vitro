<script lang="ts">
  // 协议模式右栏（#222 P1 内存/协议，2026-10-22）：叙事故障 / 计数 / 三入口 / 动作。
  //
  // 计数与主页同源（lib/protoFacts.ts）：大号数字 = 本页实际消费的**方法数**
  // （按方法展开 = 20）/ 协议 v0.2 冻结方法面 25；组清单 15 行 / 展开 22 方法
  // 另记，行与方法分母不同，不混算（审查 P2-1）。
  import { session } from "../session.svelte.ts";
  import { setMode } from "../ui.svelte.ts";
  import { toast } from "../toasts.svelte.ts";
  import { METHOD_LISTED, METHOD_ROWS, METHOD_TOTAL, METHOD_USED } from "./protoFacts.ts";

  const schemaVersion = $derived(String(((session.capabilities as Record<string, unknown> | null)?.["schema"] as Record<string, unknown> | undefined)?.["version"] ?? "—"));

  async function copyCaps(): Promise<void> {
    try {
      await navigator.clipboard.writeText(JSON.stringify(session.capabilities ?? {}, null, 2));
      toast("ok", "能力清单（JSON）已复制到剪贴板");
    } catch {
      toast("err", "剪贴板不可用——切到执行模式后可在控制台读 __pilot.session.capabilities");
    }
  }
</script>

<div class="vr-side">
  <p class="vr-side-kicker">这份页面证明什么</p>
  <h1 class="vr-side-title">不是文档，<br />是同一份引擎事实。</h1>
  <p class="vr-side-lede">CLI、浏览器、下游消费者读同一套 NDJSON 帧；demo 只是第一个浏览器消费者。</p>

  <div class="vr-side-count">
    <b>{METHOD_USED}</b><span>/ {METHOD_TOTAL} 方法被本页消费</span>
  </div>

  <ol class="vr-side-principles">
    <li><b>01 三方同源</b><span>同一份帧、同一 schema，CLI 与浏览器不各写一份。</span></li>
    <li><b>02 未消费诚实</b><span>memory.dump / algorithms.catalog 标 —，不假装全用。</span></li>
    <li><b>03 冻结可对</b><span>schema / contracts 可按版本对账，不从 UI 文案反推。</span></li>
    <li><b>04 降级有洁</b><span>wasm-gc 失败切 js 臂，协议面不分裂。</span></li>
  </ol>

  <div class="vr-side-entries">
    <h3>三个入口</h3>
    <div><span>CLI</span><code>scripts/bin/vitro --json</code></div>
    <div><span>浏览器</span><code>gateway wasm-gc 实例</code></div>
    <div><span>帧文档</span><code>docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md</code></div>
  </div>

  <div class="vr-side-actions">
    <button type="button" class="vr-btn vr-primary" onclick={copyCaps}>复制能力清单（JSON）</button>
    <button type="button" class="vr-btn" onclick={() => setMode("exec")}>切回执行模式</button>
  </div>

  <p class="vr-side-foot">schema {schemaVersion}。本页清单 {METHOD_ROWS} 行 / 展开 {METHOD_LISTED} 方法；协议方法面 {METHOD_TOTAL}——行与方法分母不同，不混算。</p>
</div>
