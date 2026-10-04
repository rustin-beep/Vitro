// Vitro demo · 诊断手册与协议参照（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。）
"use strict";

import { invoke, bodyOf } from "./gw.js";
import { $, esc } from "./util.js";

let catalogData = null; // error_catalog 缓存

export async function loadCatalog() {
  if (catalogData) return;
  const r = bodyOf(invoke({ method: "error_catalog" }));
  const all = r.catalog || [];
  // 按 lang 过滤：C++ 卡（5 张）为 F-2 裁砍前的历史目录——展示会误导
  // 读者以为引擎支持 C++（审阅二批 §2）；保留数据不删，仅不展示。
  catalogData = all.filter((c) => c.lang === "c");
  const cpp = all.length - catalogData.length;
  const cats = new Set(catalogData.map((c) => c.category));
  $("cat-stats").textContent =
    `C 卡 ${catalogData.length} 张 · 按 ${cats.size} 个分类` +
    (cpp ? `（另有 ${cpp} 张 C++ 历史卡不展示——C++ 已于 F-2 裁砍）` : "");
  renderCatalog("");
}

export function renderCatalog(query) {
  const q = query.trim().toLowerCase();
  const list = q
    ? catalogData.filter((c) =>
        [c.code_str, c.title, c.category, c.explanation, ...(c.common_causes || [])]
          .join(" ").toLowerCase().includes(q)
      )
    : catalogData;
  const byCat = {};
  for (const c of list) (byCat[c.category] = byCat[c.category] || []).push(c);
  $("cat-list").innerHTML =
    (list.length === 0 ? '<div class="muted">无匹配条目</div>' : "") +
    Object.entries(byCat)
      .map(
        ([cat, items]) =>
          `<div class="cat-group"><div class="cat-head">${esc(cat)} <span class="muted">(${items.length})</span></div>` +
          items
            .map(
              (c) =>
                `<details class="cat-card"><summary><span class="emoji">${esc(c.emoji)}</span>` +
                `<span class="code">${esc(c.code_str)}</span> ${esc(c.title)}</summary>` +
                `<div class="cat-body"><p>${esc(c.explanation)}</p>` +
                (c.common_causes && c.common_causes.length
                  ? `<div class="causes">常见原因：${c.common_causes.map((x) => esc(x)).join("；")}</div>`
                  : "") +
                `</div></details>`
            )
            .join("") +
          `</div>`
      )
      .join("");
}

// ── 引擎与协议 ───────────────────────────────────────────
export function renderProto(cap, contracts, labels) {
  const schema = cap.schema || {};
  const ledger = schema.v0_2_field_ledger || [];
  $("cap-badge").textContent = `schema ${schema.version || "?"}（冻结于 ${schema.frozen_at || "?"}）`;
  $("cap-badge").title = `semantic_label_kinds=${cap.semantic_label_kinds ?? "?"}`;
  const methods = [
    ["compile", "源码 → 编译；files 多编译单元 / filename；诊断含修复建议", "✓"],
    ["run", "执行；finished / trap / waiting_input；params 支持 argv 与 input", "✓"],
    ["output.delta", "stdout / stderr / note / display 四视图，游标制增量", "✓"],
    ["input.feed", "stdin 喂入续跑（交互程序）", "✓"],
    ["memory.regions", "内存白箱：三段式区域 + free_list + 隔离区", "✓"],
    ["error_catalog", "诊断目录 77 卡（72 C 卡展示；5 张 C++ 历史卡按 lang 过滤）", "✓"],
    ["config.get / config.set", "确定性 / 步数上限 / 调用深度 / 隔离区预算（4 可写字段）", "✓"],
    ["capabilities", "schema 冻结 + v0.2 台账 + languages + memory_model", "✓"],
    ["contracts", "行为契约 + v0.2 激活清单", "✓"],
    ["semantic_labels", "步进语义标注词表（14 类全 active——S8 step 流的呈现层词汇）", "✓"],
    ["session.create / reset / destroy", "会话生命周期（create 清 runtime 域，config 需显式回设）", "✓"],
    ["ping / shutdown", "探活与关停", "✓"],
  ];
  $("methods-list").innerHTML = methods
    .map(
      ([m, d, s]) =>
        `<div class="method"><span class="m-name">${esc(m)}</span><span class="m-desc">${esc(d)}</span>` +
        `<span class="m-use ${s === "✓" ? "yes" : "no"}">${esc(s)}</span></div>`
    )
    .join("");
  $("cap-box").innerHTML =
    `<p class="small">协议 <b>${esc(schema.version)}</b> 冻结于 ${esc(schema.frozen_at)}；以下为 v0.2 预留台账（<code>v0_2_field_ledger</code>，发布即冻结不得改语义）：</p>` +
    ledger
      .map(
        (f) =>
          `<div class="ledger"><span class="code">${esc(f.field)}</span>` +
          `<span class="muted small">（${esc(f.batch)} · ${esc(f.status)}）</span> ${esc(f.note)}</div>`
      )
      .join("");
  // languages（语言子集锚——C23 基准与预处理器能力）
  const c = (cap.languages && cap.languages.c) || {};
  const pp = c.preprocessor || {};
  $("lang-box").innerHTML =
    `<div class="ledger"><span class="code">${esc(c.anchor || "")}</span> <code>__STDC_VERSION__</code>=${esc((c.predefined_macros || {})["__STDC_VERSION__"] || "")} · <code>__VITRO_SUBSET__</code>=${esc((c.predefined_macros || {})["__VITRO_SUBSET__"] || "")}</div>` +
    `<div class="ledger">预处理器：对象宏/函数宏/字符串化/拼接 ${pp.stringize && pp.token_paste ? "✓" : "—"} · 条件编译 ${((pp.conditionals || []).length)} 指令 · <code>include_cycle_detection</code>=${esc(pp.include_cycle_detection)} · <code>expand_depth_fuse</code>=${esc(pp.expand_depth_fuse)}（熔断）</div>` +
    `<div class="ledger">教学层：${(pp.teaching_layer || []).map((t) => `<code>${esc(t)}</code>`).join(" ")}</div>`;
  // memory_model（内存白箱的物理常数）
  const mm = cap.memory_model || {};
  $("memmodel-box").innerHTML =
    `<div class="ledger"><code>mem_size</code>=${mm.mem_size} B（1MB 映射） · <code>null_trap_size</code>=${mm.null_trap_size} B（NULL 页受检）</div>` +
    `<div class="ledger"><code>global_start</code>=0x${(mm.global_start || 0).toString(16)} · <code>global_region_limit</code>=${mm.global_region_limit} B · <code>heap_start_default</code>=0x${(mm.heap_start_default || 0).toString(16)}（动态：max(HEAP_START, align4(global_data_end))）</div>`;
  // 行为契约 + v0.2 激活清单
  const bc = (contracts && contracts.behavior_contracts) || [];
  const checklist = (contracts && contracts.v0_2_activation_checklist) || [];
  $("contracts-box").innerHTML =
    (contracts ? `<p class="small">schema ${esc(contracts.schema || "")} · 冻结于 ${esc(contracts.frozen_at || "")} · 契约 ${bc.length} 条（enforced_by = 守护它的防线测试名）：</p>` : "") +
    bc
      .map(
        (c) =>
          `<div class="ledger"><span class="code">${esc(c.id)}</span>` +
          `<span class="muted small">（${esc(c.status)}）</span> ${esc(c.statement)}` +
          `<div class="muted small">守卫：${esc(c.enforced_by)}</div></div>`
      )
      .join("") +
    (checklist.length
      ? `<p class="small" style="margin-top:8px">v0.2 激活清单（${checklist.length} 步——预留位激活的既定流程）：</p>` +
        checklist.map((s, i) => `<div class="ledger"><span class="code">${i + 1}</span> ${esc(s)}</div>`).join("")
      : "");
  // semantic_labels（14 类步进语义词表——时间旅行回放的标注词汇，已冻结）
  const sl = (labels && labels.labels) || [];
  $("labels-box").innerHTML =
    (labels ? `<p class="small">${esc(labels.discipline || "")} · 共 ${sl.length} 类：</p>` : "") +
    sl
      .map(
        (l) =>
          `<div class="ledger"><span class="code">${esc(l.id)}</span>` +
          `<span class="muted small">（${esc(l.domain)} · ${esc(l.status)}）</span>` +
          `模板 <code>${esc(l.template)}</code>${l.example ? ` · 例：${esc(l.example)}` : ""}</div>`
      )
      .join("");
}

// ── 时间旅行（S8 step 流采集-回放）──────────────────────
// 帧数据源 = gateway step 族（step.begin / step.next 批量推进），每帧带
// 引擎真实标注（semantic_labels 词表渲染文本）/ 局部变量 / 调用栈 / 当前
// 执行行；seek 与 ◀▶ 为本地帧数组形态（gateway wasm 未接 step.seek /
// payload.get——那是 serve 通道能力，教学回放形态下本地索引足够，引擎级
// 断点留实时调试形态）。场景 = 全部预置用例；左侧编辑器随帧高亮当前行。
