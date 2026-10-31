<script lang="ts">
  // 引擎与协议 · P1 全页形态（#222 P1 内存/协议，2026-10-22）。
  //
  // 只读事实面：方法分组（本页消费 x/y 方法）+ schema 台账 + 契约 + 当前帧示例。
  // 方法清单单源 = lib/protoFacts.ts（右栏「20 / 25 方法」与这里共读，防两处
  // 计数漂移）；行数(15)与方法数(22)分列，不混算（审查 P2-1）。
  // 其余数据来自 session 层 loadProto 拉取的 capabilities/contracts/labels 帧。
  // 字段缺失显「—」不发明；未消费方法显式标 —（不假装全用）。
  import { frameAt, session } from "../session.svelte.ts";
  import { METHOD_GROUPS, METHOD_LISTED, METHOD_ROWS, METHOD_TOTAL, groupMethodStats } from "./protoFacts.ts";

  type JsonRec = Record<string, unknown>;
  const cap = $derived((session.capabilities ?? {}) as JsonRec);
  const schema = $derived((cap["schema"] ?? {}) as JsonRec);
  const ledger = $derived((schema["v0_2_field_ledger"] ?? []) as JsonRec[]);
  const contracts = $derived((session.contracts ?? null) as JsonRec | null);
  const bc = $derived((contracts?.["behavior_contracts"] ?? []) as JsonRec[]);
  const checklist = $derived((contracts?.["v0_2_activation_checklist"] ?? []) as unknown[]);
  const labels = $derived((session.labels ?? []) as JsonRec[]);
  /** StepPayload 帧字段数（PR #397 审阅 P2-1：旧稿硬编码「14 字段」与实产
   *  16 字段矛盾——#324 病根数字冻进 golden。改从当前帧实数据派生，字段
   *  面演进（如 v0.2 预留位激活）时 UI 静态认知自动跟随）。 */
  const stepFieldCount = $derived(
    session.frames[0] ? Object.keys(session.frames[0]).length : 0,
  );

  const frame = $derived(frameAt(session.idx));
  const frameJson = $derived.by(() => {
    if (!frame) return "";
    return JSON.stringify(
      {
        step_index: frame.step_index,
        code_line: frame.code_line,
        func_name: frame.func_name,
        semantic_label: frame.semantic_label,
        array_snapshots: (frame.array_snapshots ?? []).slice(0, 1).map((s) => ({ name: s.name, elements: s.elements.slice(0, 5) })),
        local_vars: (frame.local_vars ?? []).slice(0, 3).map((v) => ({ name: v.name, value: v.value })),
      },
      null,
      2,
    );
  });
</script>

<section class="vr-block vr-protopage" aria-label="引擎与协议">
  <div class="vr-blockhead">
    <h2 class="vr-label">引擎与协议</h2>
    <span class="vr-spacer"></span>
    <span class="vr-meta">只读事实 · capabilities / contracts</span>
  </div>

  <div class="vr-proto-facts">
    <span>ENGINE <b>{session.versions.engine || "…"}</b></span>
    <span>PROTOCOL <b>{session.versions.protocol || "…"}</b></span>
    <span>STEPPAYLOAD <b>{stepFieldCount || "…"} 字段</b></span>
    <span>SCHEMA <b>{String(schema["version"] ?? "—")} 冻结</b></span>
    <span>METHODS <b>{METHOD_TOTAL} · 本页 {METHOD_ROWS} 行 / {METHOD_LISTED} 方法</b></span>
    <span>TRANSPORT <b>wasm-gc · js-string</b></span>
  </div>

  <div class="vr-proto-groups">
    {#each METHOD_GROUPS as g, gi (g.id)}
      <div class="vr-proto-group">
        <div class="vr-proto-grouphead">
          <h3><span class="no">{String(gi + 1).padStart(2, "0")}</span>{g.title}</h3>
          <span class="vr-meta">{groupMethodStats(g).used} / {groupMethodStats(g).total} 方法</span>
        </div>
        {#each g.items as m (m.name)}
          <div class="vr-proto-method">
            <span class="m-name">{m.name}</span>
            <span class="m-desc">{m.desc}</span>
            <span class="m-use" class:is-yes={m.used}>{m.used ? "✓" : "—"}</span>
          </div>
        {/each}
      </div>
    {/each}
  </div>

  <section class="vr-proto-sec">
    <div class="vr-proto-seclabel">
      <h3>SCHEMA 冻结与 v0.2 预留台账</h3>
      <span class="vr-meta">{ledger.length} 字段</span>
    </div>
    {#if ledger.length > 0}
      <table class="vr-proto-table">
        <thead><tr><th>FIELD</th><th>BATCH</th><th>STATUS</th><th>NOTE</th></tr></thead>
        <tbody>
          {#each ledger as f (String(f["field"]))}
            <tr>
              <td class="code">{String(f["field"] ?? "—")}</td>
              <td>{String(f["batch"] ?? "—")}</td>
              <td><span class="vr-proto-status is-{String(f["status"] ?? "unknown")}">{String(f["status"] ?? "—")}</span></td>
              <td>{String(f["note"] ?? "")}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    {:else}
      <p class="vr-proto-note">（capabilities.schema 未载——引擎未就绪或协议面拉取失败）</p>
    {/if}
  </section>

  <section class="vr-proto-sec">
    <div class="vr-proto-seclabel">
      <h3>CONTRACTS 行为契约</h3>
      <span class="vr-meta">schema {String(contracts?.["schema"] ?? "—")} · {bc.length} 条</span>
    </div>
    {#if contracts}
      {#each bc as c (String(c["id"]))}
        <div class="vr-proto-contract">
          <span class="code">{String(c["id"] ?? "—")}</span>
          <span class="dim">（{String(c["status"] ?? "—")}）</span>
          {String(c["statement"] ?? "")}
          <div class="dim">守卫：{String(c["enforced_by"] ?? "—")}</div>
        </div>
      {/each}
      {#if checklist.length > 0}
        <p class="vr-proto-note">v0.2 激活清单（{checklist.length} 步——预留位激活的既定流程）：</p>
        {#each checklist as s, i (i)}
          <div class="vr-proto-contract"><span class="code">{i + 1}</span> {String(s)}</div>
        {/each}
      {/if}
    {:else}
      <p class="vr-proto-note">（contracts 未载——引擎未就绪或协议面拉取失败）</p>
    {/if}
  </section>

  <section class="vr-proto-sec">
    <div class="vr-proto-seclabel">
      <h3>FRAME step.next 帧示例</h3>
      <span class="vr-meta">wire JSON · 当前帧 · 已裁剪</span>
    </div>
    {#if frameJson}
      <pre class="vr-proto-frame">{frameJson}</pre>
    {:else}
      <p class="vr-proto-note">（尚未采集——执行一次后这里显示当前帧的 wire JSON）</p>
    {/if}
  </section>

  <details class="vr-proto-more">
    <summary>语义标注词表（{labels.length} 类）</summary>
    {#if labels.length > 0}
      {#each labels as l, i (i)}
        <div class="vr-proto-contract">
          <span class="code">{String(l["id"] ?? "—")}</span>
          <span class="dim">（{String(l["domain"] ?? "—")} · {String(l["status"] ?? "—")}）</span>
          模板 <code>{String(l["template"] ?? "—")}</code>{l["example"] ? ` · 例：${String(l["example"])}` : ""}
        </div>
      {/each}
    {:else}
      <p class="vr-proto-note">（semantic_labels 未载——引擎未就绪或协议面拉取失败）</p>
    {/if}
  </details>

  <p class="vr-meta vr-protopage-foot">capabilities / contracts / semantic_labels 均为只读帧；languages / memory_model 已拉取但本页不展开（审查 P2-6 登记）；缺失字段显「—」，不发明。</p>
</section>
