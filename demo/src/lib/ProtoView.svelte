<script lang="ts">
  // 引擎与协议模式（设计稿「协议」+ A19）：只读事实面——
  //   ① 方法面清单（引擎 25 方法 · 组清单 15 行，✓/— = 本页是否消费）
  //   ② SCHEMA 冻结 + v0.2 预留台账   ③ 语言子集锚
  //   ④ memory_model 物理常数          ⑤ contracts 行为契约 + 激活清单
  //   ⑥ semantic_labels 词表（全字段）
  // 数据来自 session 层 loadProto 拉取的 capabilities/contracts/labels 帧；
  // 字段缺失显「—」不发明。
  import { session } from "../session.svelte.ts";

  type JsonRec = Record<string, unknown>;
  const cap = $derived((session.capabilities ?? {}) as JsonRec);
  const schema = $derived((cap.schema ?? {}) as JsonRec);
  const ledger = $derived((schema.v0_2_field_ledger ?? []) as JsonRec[]);
  const cLang = $derived((((cap.languages as JsonRec) ?? {}).c ?? {}) as JsonRec);
  const pp = $derived((cLang.preprocessor ?? {}) as JsonRec);
  const macros = $derived((pp.predefined_macros ?? {}) as JsonRec);
  const mm = $derived((cap.memory_model ?? {}) as JsonRec);
  const contracts = $derived((session.contracts ?? null) as JsonRec | null);
  const bc = $derived((contracts?.behavior_contracts ?? []) as JsonRec[]);
  const checklist = $derived((contracts?.v0_2_activation_checklist ?? []) as unknown[]);
  const labels = $derived((session.labels ?? []) as JsonRec[]);

  const hex = (v: unknown): string => "0x" + (Number(v) || 0).toString(16);

  // 方法面组清单（✓/— = 本页是否消费该方法；描述口径沿用旧栈注释）
  const METHODS: Array<[string, string, boolean]> = [
    ["compile", "源码 → 编译；files 多编译单元 / filename；诊断含修复建议", true],
    ["run", "执行；finished / trap / waiting_input；params 支持 argv 与 input", true],
    ["output.delta", "stdout / stderr / note / display 四视图，游标制增量", true],
    ["input.feed", "stdin 喂入续跑（交互程序）", true],
    ["memory.regions", "内存白箱：三段式区域 + free_list + 隔离区", true],
    ["memory.dump", "1MB 映像 base64 导出（CLI --dump-memory / vm_diff 映像联）", false],
    ["error_catalog", "诊断目录（C 卡按 lang 过滤；含 common_causes 与修复建议）", true],
    ["config.get / config.set", "确定性 / 步数上限 / 调用深度 / 隔离区预算（4 可写字段）", true],
    ["capabilities", "schema 冻结 + v0.2 台账 + languages + memory_model", true],
    ["contracts", "行为契约 + v0.2 激活清单", true],
    ["semantic_labels", "步进语义标注词表（14 类——S8 step 流的呈现层词汇）", true],
    ["session.create / reset / destroy", "会话生命周期（create 清 runtime 域，config 需显式回设）", true],
    ["step.begin / step.next / seek / breakpoints.set", "时间旅行采集：重建 / 批次推进 / 引擎级跳转 / 断点下发", true],
    ["algorithms.catalog", "算法族目录（#36 上线——课程数据引擎单源）", false],
    ["ping / shutdown", "探活与关停", true],
  ];
</script>

<section class="vr-block" aria-label="引擎与协议">
  <div class="vr-blockhead">
    <h2 class="vr-label">引擎与协议</h2>
    <span class="vr-spacer"></span>
    <span class="vr-meta">只读事实</span>
  </div>

  <div class="vr-proto-head">
    <span>engine <b>{session.versions.engine || "…"}</b></span>
    <span>protocol <b>{session.versions.protocol || "…"}</b></span>
    <span>StepPayload <b>14 字段</b></span>
    <span>schema <b>{String(schema.version ?? "—")}</b></span>
    <span>方法面 <b>25</b></span>
    <span>本页组清单 <b>{METHODS.length}</b></span>
  </div>

  <p class="vr-proto-note">冻结协议 {String(schema.version ?? "—")}（{String(schema.frozen_at ?? "—")} 定版）的 NDJSON 方法帧——demo 是协议的第一个浏览器消费者。wasm-gc + js-string builtins（Chrome/Edge 130+、Firefox 134+）。</p>

  <div class="vr-proto-groups">
    {#each METHODS as m (m[0])}
      <div class="vr-proto-method">
        <span class="m-name">{m[0]}</span>
        <span>{m[1]}</span>
        <span class="m-use" class:is-yes={m[2]}>{m[2] ? "✓" : "—"}</span>
      </div>
    {/each}
  </div>

  <div class="vr-proto-sec">
    <h3>SCHEMA 冻结与 v0.2 预留台账</h3>
    {#if ledger.length > 0}
      {#each ledger as f (String(f.field))}
        <div class="vr-proto-ledger">
          <span class="code">{String(f.field ?? "—")}</span>
          <span class="dim">（{String(f.batch ?? "—")} · {String(f.status ?? "—")}）</span>
          {String(f.note ?? "")}
        </div>
      {/each}
    {:else}
      <p class="vr-proto-note">（capabilities.schema 未载——引擎未就绪或协议面拉取失败）</p>
    {/if}
  </div>

  <div class="vr-proto-sec">
    <h3>语言子集锚（LANGUAGES）</h3>
    <div class="vr-proto-ledger"><span class="code">{String(cLang.anchor ?? "—")}</span> <code>__STDC_VERSION__</code>={String(macros["__STDC_VERSION__"] ?? "—")} · <code>__VITRO_SUBSET__</code>={String(macros["__VITRO_SUBSET__"] ?? "—")}</div>
    <div class="vr-proto-ledger">预处理器：对象宏/函数宏/字符串化/拼接 {pp.stringize && pp.token_paste ? "✓" : "—"} · 条件编译 {(pp.conditionals as unknown[] | undefined)?.length ?? 0} 指令 · <code>include_cycle_detection</code>={String(pp.include_cycle_detection ?? "—")} · <code>expand_depth_fuse</code>={String(pp.expand_depth_fuse ?? "—")}（熔断）</div>
    <div class="vr-proto-ledger">教学层：{(pp.teaching_layer as string[] | undefined ?? []).join(" · ")}</div>
  </div>

  <div class="vr-proto-sec">
    <h3>内存模型常数（MEMORY_MODEL）</h3>
    <div class="vr-proto-ledger"><code>mem_size</code>={String(mm.mem_size ?? "—")} B（1MB 映射） · <code>null_trap_size</code>={String(mm.null_trap_size ?? "—")} B（NULL 页受检）</div>
    <div class="vr-proto-ledger"><code>global_start</code>={hex(mm.global_start)} · <code>global_region_limit</code>={String(mm.global_region_limit ?? "—")} B · <code>heap_start_default</code>={hex(mm.heap_start_default)}（动态：max(HEAP_START, align4(global_data_end))）</div>
  </div>

  <div class="vr-proto-sec">
    <h3>行为契约（CONTRACTS）</h3>
    {#if contracts}
      <p class="vr-proto-note">schema {String(contracts.schema ?? "")} · 冻结于 {String(contracts.frozen_at ?? "")} · 契约 {bc.length} 条（enforced_by = 守护它的防线测试名）</p>
      {#each bc as c (String(c.id))}
        <div class="vr-proto-ledger">
          <span class="code">{String(c.id ?? "—")}</span>
          <span class="dim">（{String(c.status ?? "—")}）</span>
          {String(c.statement ?? "")}
          <div class="dim">守卫：{String(c.enforced_by ?? "—")}</div>
        </div>
      {/each}
      {#if checklist.length > 0}
        <p class="vr-proto-note">v0.2 激活清单（{checklist.length} 步——预留位激活的既定流程）：</p>
        {#each checklist as s, i (i)}
          <div class="vr-proto-ledger"><span class="code">{i + 1}</span> {String(s)}</div>
        {/each}
      {/if}
    {:else}
      <p class="vr-proto-note">（contracts 未载——引擎未就绪或协议面拉取失败）</p>
    {/if}
  </div>

  <div class="vr-proto-sec">
    <h3>语义标注词表（SEMANTIC_LABELS · {labels.length} 类）</h3>
    {#if labels.length > 0}
      {#each labels as l, i (i)}
        <div class="vr-proto-ledger">
          <span class="code">{String(l.id ?? "—")}</span>
          <span class="dim">（{String(l.domain ?? "—")} · {String(l.status ?? "—")}）</span>
          模板 <code>{String(l.template ?? "—")}</code>{l.example ? ` · 例：${String(l.example)}` : ""}
        </div>
      {/each}
    {:else}
      <p class="vr-proto-note">（semantic_labels 未载——引擎未就绪或协议面拉取失败）</p>
    {/if}
  </div>
</section>
