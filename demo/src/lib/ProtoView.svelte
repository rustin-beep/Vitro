<script lang="ts">
  // 引擎与协议页（A19，#140——旧栈 catalog.ts renderProto 六块语义平移，
  // 替代此前「capabilities 原始 JSON 墙 + labels chips」的缩水形态）：
  //   ① 方法面清单（引擎 24 方法 · 组清单 14 行，✓/— = 本页是否消费）
  //   ② SCHEMA 冻结 + v0.2 预留台账（发布即冻结不得改语义）
  //   ③ languages/preprocessor 语言子集锚
  //   ④ memory_model 内存白箱物理常数
  //   ⑤ contracts 行为契约（enforced_by = 守护它的防线测试名）+ 激活清单
  //   ⑥ semantic_labels 步进语义标注词表（全字段）
  // 全部数据来自 session 层 loadProto 拉取的 capabilities/contracts/labels
  // 帧；字段缺失显「—」不发明；文本插值自动转义替代旧栈 esc 纪律。
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

  // 方法面组清单（描述口径照旧栈；✓/— = 本页是否消费该方法。step 族一行
  // 为新栈补记——采集/断点/步号跳转三面现已全部接线）
  const METHODS: Array<[string, string, boolean]> = [
    ["compile", "源码 → 编译；files 多编译单元 / filename；诊断含修复建议", true],
    ["run", "执行；finished / trap / waiting_input；params 支持 argv 与 input", true],
    ["output.delta", "stdout / stderr / note / display 四视图，游标制增量", true],
    ["input.feed", "stdin 喂入续跑（交互程序）", true],
    ["memory.regions", "内存白箱：三段式区域 + free_list + 隔离区", true],
    ["memory.dump", "1MB 映像 base64 导出（CLI --dump-memory / vm_diff 映像联）", false],
    ["error_catalog", "诊断目录 102 卡（#50 批③扩容 77→102；C++ 卡按 lang 过滤）", true],
    ["config.get / config.set", "确定性 / 步数上限 / 调用深度 / 隔离区预算（4 可写字段）", true],
    ["capabilities", "schema 冻结 + v0.2 台账 + languages + memory_model", true],
    ["contracts", "行为契约 + v0.2 激活清单", true],
    ["semantic_labels", "步进语义标注词表（14 类全 active——S8 step 流的呈现层词汇）", true],
    ["session.create / reset / destroy", "会话生命周期（create 清 runtime 域，config 需显式回设）", true],
    ["step.begin / step.next / seek / breakpoints.set", "时间旅行采集：重建 step 会话 / 批次推进 / 引擎级跳转 / 断点下发（paused 批次暂停）", true],
    ["algorithms.catalog", "算法族目录（#36 上线——43 族课程数据引擎单源；页面经构建期合成模块消费）", false],
    ["ping / shutdown", "探活与关停", true],
  ];
</script>

<div class="proto">
  <p class="proto-line">
    本页所有能力均来自冻结协议 <b>{String(schema.version ?? "—")}</b>
    （{String(schema.frozen_at ?? "—")} 定版）的 NDJSON 方法帧——demo 就是协议的第一个浏览器消费者。
  </p>

  <h3 class="ph">方法面（引擎 25 个 · 组清单 {METHODS.length} 行）</h3>
  <div class="methods">
    {#each METHODS as m (m[0])}
      <div class="method">
        <span class="m-name">{m[0]}</span>
        <span class="m-desc">{m[1]}</span>
        <span class="m-use" class:yes={m[2]} class:no={!m[2]}>{m[2] ? "✓" : "—"}</span>
      </div>
    {/each}
  </div>

  <h3 class="ph">SCHEMA 冻结与 v0.2 预留台账</h3>
  <p class="small">协议 <b>{String(schema.version ?? "—")}</b> 冻结于 {String(schema.frozen_at ?? "—")}；以下为 v0.2 预留台账（<code>v0_2_field_ledger</code>，发布即冻结不得改语义）：</p>
  {#if ledger.length > 0}
    {#each ledger as f (String(f.field))}
      <div class="ledger">
        <span class="code">{String(f.field ?? "—")}</span>
        <span class="muted">（{String(f.batch ?? "—")} · {String(f.status ?? "—")}）</span>
        {String(f.note ?? "")}
      </div>
    {/each}
  {:else}
    <p class="muted">（capabilities.schema 未载——引擎未就绪或协议面拉取失败）</p>
  {/if}

  <h3 class="ph">语言子集锚（LANGUAGES）</h3>
  <div class="ledger"><span class="code">{String(cLang.anchor ?? "—")}</span> <code>__STDC_VERSION__</code>={String(macros["__STDC_VERSION__"] ?? "—")} · <code>__VITRO_SUBSET__</code>={String(macros["__VITRO_SUBSET__"] ?? "—")}</div>
  <div class="ledger">预处理器：对象宏/函数宏/字符串化/拼接 {pp.stringize && pp.token_paste ? "✓" : "—"} · 条件编译 {(pp.conditionals as unknown[] | undefined)?.length ?? 0} 指令 · <code>include_cycle_detection</code>={String(pp.include_cycle_detection ?? "—")} · <code>expand_depth_fuse</code>={String(pp.expand_depth_fuse ?? "—")}（熔断）</div>
  <div class="ledger">教学层：{(pp.teaching_layer as string[] | undefined ?? []).map((t) => t).join(" · ")}</div>

  <h3 class="ph">内存模型常数（MEMORY_MODEL）</h3>
  <div class="ledger"><code>mem_size</code>={String(mm.mem_size ?? "—")} B（1MB 映射） · <code>null_trap_size</code>={String(mm.null_trap_size ?? "—")} B（NULL 页受检）</div>
  <div class="ledger"><code>global_start</code>={hex(mm.global_start)} · <code>global_region_limit</code>={String(mm.global_region_limit ?? "—")} B · <code>heap_start_default</code>={hex(mm.heap_start_default)}（动态：max(HEAP_START, align4(global_data_end))）</div>

  <h3 class="ph">行为契约（CONTRACTS）</h3>
  {#if contracts}
    <p class="small">schema {String(contracts.schema ?? "")} · 冻结于 {String(contracts.frozen_at ?? "")} · 契约 {bc.length} 条（enforced_by = 守护它的防线测试名）：</p>
    {#each bc as c (String(c.id))}
      <div class="ledger">
        <span class="code">{String(c.id ?? "—")}</span>
        <span class="muted">（{String(c.status ?? "—")}）</span>
        {String(c.statement ?? "")}
        <div class="muted">守卫：{String(c.enforced_by ?? "—")}</div>
      </div>
    {/each}
    {#if checklist.length > 0}
      <p class="small">v0.2 激活清单（{checklist.length} 步——预留位激活的既定流程）：</p>
      {#each checklist as s, i (i)}
        <div class="ledger"><span class="code">{i + 1}</span> {String(s)}</div>
      {/each}
    {/if}
  {:else}
    <p class="muted">（contracts 未载——引擎未就绪或协议面拉取失败）</p>
  {/if}

  <h3 class="ph">语义标注词表（SEMANTIC_LABELS）</h3>
  {#if labels.length > 0}
    <p class="small">步进语义标注（S8 step 流的呈现层词汇，已冻结）· 共 {labels.length} 类：</p>
    {#each labels as l, i (i)}
      <div class="ledger">
        <span class="code">{String(l.id ?? "—")}</span>
        <span class="muted">（{String(l.domain ?? "—")} · {String(l.status ?? "—")}）</span>
        模板 <code>{String(l.template ?? "—")}</code>{l.example ? ` · 例：${String(l.example)}` : ""}
      </div>
    {/each}
  {:else}
    <p class="muted">（semantic_labels 未载——引擎未就绪或协议面拉取失败）</p>
  {/if}
</div>

<style>
  .proto { font-size: 12.5px; color: var(--t2); display: flex; flex-direction: column; gap: 4px; }
  .proto-line { font-size: 12.5px; color: var(--t2); line-height: 1.7; margin: 4px 0 10px; }
  .ph { font-size: 13px; margin: 14px 0 6px; color: var(--t1); }
  .small { font-size: 12px; color: var(--t3); margin: 0 0 4px; }
  .methods { display: flex; flex-direction: column; gap: 3px; }
  .method { display: grid; grid-template-columns: minmax(150px, auto) 1fr auto; gap: 10px; align-items: baseline; padding: 5px 10px; border: 1px solid var(--hairline); border-radius: 6px; background: var(--pane); }
  .m-name { font: 12px var(--mono); color: var(--accent-strong); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .m-desc { color: var(--t2); }
  .m-use { font-weight: 700; }
  .m-use.yes { color: var(--ok); }
  .m-use.no { color: var(--t3); }
  .ledger { padding: 5px 10px; border-left: 3px solid var(--hairline); margin: 3px 0; line-height: 1.6; }
  .ledger .code { font: 12px var(--mono); color: var(--accent-strong); font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
  .muted { color: var(--t3); font-size: 12px; }
  code { font: 11.5px var(--mono); background: var(--pane); border: 1px solid var(--hairline); border-radius: 4px; padding: 0 4px; font-variant-ligatures: none; font-feature-settings: "liga" 0, "calt" 0; }
</style>
