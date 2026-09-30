// Vitro 引擎浏览器单页 demo（second cut：协议面尽量全展示）。
// 承载形态：浏览器直调 gateway wasm-gc 单出口（S7 批五号产物，0.7.0 发布）
// ——零 npm 依赖、零后端；协议帧为 NDJSON，与 CI 的
// scripts/wasm_gateway/host.js 同语义（该脚本 16 断言即协议契约的真值源）。
// 定位是门面不是架构件：渲染逻辑暂放宿主页内 JS，MoonBit SVG 纯函数包
// 落地后由其接管（总计划既定路线）。
"use strict";

const MEM_TOTAL = 1024 * 1024; // 1MB 内存映射（引擎口径）
let gw = null; // gateway exports
let frameId = 0;
let pendingRun = null; // waiting_input 时的会话上下文
let catalogData = null; // error_catalog 缓存

// ── wasm 装载 ─────────────────────────────────────────────
async function loadGateway() {
  const buf = await (await fetch("wasm.wasm")).arrayBuffer();
  // 与 host.js 同契约：js-string builtins + "_" 字符串常量模块
  const mod = new WebAssembly.Module(buf, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  const inst = await WebAssembly.instantiate(mod, {});
  return inst.exports;
}

function invoke(obj) {
  frameId += 1;
  obj.id = frameId;
  return JSON.parse(gw.invoke(JSON.stringify(obj)));
}

// 响应统一视图：协议所有方法帧均为「顶层 id/ok + result」包裹（含引擎
// trap 与步数超限——2026-09-30 审阅复核修正，此前注释误写顶层平铺形态）；
// bodyOf 保留为防御式取值。
const bodyOf = (r) => (r && r.result !== undefined ? r.result : r) || {};

// wasm 输出通道的字节保真：delta 字符串每字符 = 一个 Latin-1 字节，
// 中文等 UTF-8 多字节序列在此形态下是 mojibake——按字节还原为文本。
const latin1ToUtf8 = (delta) => {
  if (!delta) return "";
  const bytes = new Uint8Array(delta.length);
  for (let i = 0; i < delta.length; i++) bytes[i] = delta.charCodeAt(i) & 0xff;
  return new TextDecoder("utf-8").decode(bytes);
};

// ── 页面骨架 ──────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
function setStatus(kind, text) {
  const el = $("status-pill");
  el.className = "pill " + kind;
  el.textContent = text;
}

function esc(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

// ── tab 切换 ─────────────────────────────────────────────
function bindTabs() {
  document.querySelectorAll(".tabs .tab").forEach((btn) => {
    btn.onclick = () => {
      document.querySelectorAll(".tabs .tab").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      document.querySelectorAll(".tabpage").forEach((p) => p.classList.add("hidden"));
      $("tab-" + btn.dataset.tab).classList.remove("hidden");
    };
  });
}

// ── 会话配置 ─────────────────────────────────────────────
function applyConfig() {
  if (!gw) return;
  const params = {
    deterministic: $("cfg-det").checked,
    max_steps: Number($("cfg-maxsteps").value) || 10000000,
    call_depth_limit: Number($("cfg-depth").value) || 10000,
  };
  const r = bodyOf(invoke({ method: "config.set", params }));
  const c = bodyOf(invoke({ method: "config.get" }));
  $("cfg-msg").textContent = `已应用 ✓（deterministic=${c.deterministic}，max_steps=${c.max_steps}，call_depth=${c.call_depth_limit}）`;
  renderCfgView(c);
  return r;
}

function renderCfgView(c) {
  if (c) $("cfg-view").textContent = JSON.stringify(c, null, 2);
}

// ── 运行一条用例 ──────────────────────────────────────────
async function runCase() {
  if (!gw) return;
  const kase = DEMO_CASES.find((k) => k.id === $("case-select").value) || {};
  $("run-btn").disabled = true;
  setStatus("busy", "运行中…");
  try {
    gw.reset();
    // 粘滞治理（审阅二批 §5 实测）：gw.reset()（≡ session.reset）保留
    // config 与 runtime 域（argv/batch_input）；session.create 才清 runtime。
    // 故 runCase 开头：session.create 清 runtime（上个用例的 argv 粘滞）
    // → 再显式回设基准 config（config.set 只能显式回设）。
    bodyOf(invoke({ method: "session.create" }));
    // 基准配置回设（config.set 跨 reset 粘滞——session 级配置在
    // session.reset 语义下保留；上个用例注入的 configHint 若不恢复
    // 会泄漏到后续所有用例），再应用用例级覆盖。
    bodyOf(invoke({
      method: "config.set",
      params: {
        max_steps: Number($("cfg-maxsteps").value) || 10000000,
        call_depth_limit: Number($("cfg-depth").value) || 10000,
        deterministic: $("cfg-det").checked,
        quarantine_budget: Number($("cfg-quar").value) || 262144,
      },
    }));
    if (kase.configHint) {
      bodyOf(invoke({ method: "config.set", params: kase.configHint }));
      // 不回写输入框——输入框是「基准」的 UI 真相，回写会污染下一个
      // 用例的恢复基准（2026-09-30 粘滞回归实测抓到）；仅文本提示。
      $("cfg-msg").textContent = `本用例临时覆盖 config：max_steps=${kase.configHint.max_steps}（下一用例自动恢复基准）`;
    }
    // compile：用例可带 files（多编译单元）或单 source；编辑器内容跟随主文件
    let comp;
    if (kase.files) {
      const files = kase.files.map((f, i) => ({
        filename: f.filename,
        source: i === 0 ? $("editor").value : f.source,
      }));
      comp = bodyOf(invoke({ method: "compile", params: { files } }));
    } else {
      comp = bodyOf(invoke({ method: "compile", params: { source: $("editor").value } }));
    }
    renderDiagnostics(comp.diagnostics || []);
    renderPpTrace(comp.preprocessor_trace || []);
    if (!comp.ok) {
      setStatus("err", "编译失败");
      renderTrap("编译失败——诊断见左侧列表");
      return;
    }
    let run = invoke({ method: "run", params: runParams(kase) });
    let rr = bodyOf(run);
    if (rr.waiting_input) {
      pendingRun = run;
      setStatus("wait", "等待输入…（下方 stdin 喂入后继续）");
      $("stdin-row").classList.add("active");
      renderRunResult(rr);
      renderMemory(bodyOf(invoke({ method: "memory.regions" })));
      return;
    }
    pendingRun = null;
    finishRun(rr, kase);
  } finally {
    $("run-btn").disabled = false;
  }
}

async function feedStdin() {
  if (!pendingRun) return;
  const text = $("stdin-box").value;
  const feed = invoke({ method: "input.feed", params: { text: text + "\n" } });
  const rr = bodyOf(feed);
  if (rr.waiting_input) {
    setStatus("wait", "仍在等待输入…");
    return;
  }
  pendingRun = null;
  $("stdin-row").classList.remove("active");
  const kase = DEMO_CASES.find((k) => k.id === $("case-select").value) || {};
  finishRun(rr, kase);
}

// run 参数面：argv 输入框（空格分隔）或用例声明；stdin 两步交互保留
// （waiting_input 本身是教学演示点）
function runParams(kase) {
  const p = {};
  const argvText = $("argv-box").value.trim();
  if (argvText) p.argv = argvText.split(/\s+/);
  else if (kase.argv) p.argv = kase.argv;
  return p;
}

function finishRun(rr, kase) {
  renderRunResult(rr);
  // 四通道视图：stdout / stderr / note（display=全通道按写入序拼接，页内
  // 用分通道展示替代）。字节域 Latin-1 → UTF-8 还原后展示。
  const pull = (stream) => {
    const o = bodyOf(invoke({ method: "output.delta", params: { cursor: 0, stream } }));
    return { text: latin1ToUtf8(o.delta) || "", total: o.total || 0 };
  };
  const stdout = pull("stdout");
  renderOutput(stdout.text, stdout.total);
  const stderr = pull("stderr");
  renderStderr(stderr.text, stderr.total);
  const note = pull("note");
  renderNote(note.text, note.total);
  renderMemory(bodyOf(invoke({ method: "memory.regions" })));
  if (rr.status === "trap") {
    setStatus("err", "trap（受检终止）");
    renderTrap(rr.trap || "");
  } else if (rr.status === "finished") {
    setStatus("ok", "finished");
    renderTrap("");
  } else {
    setStatus("busy", rr.status || String(rr.status));
  }
  renderReference(rr, stdout.text, kase);
  renderCfgView(bodyOf(invoke({ method: "config.get" })));
}

function renderStderr(text, total) {
  const el = $("stderr-box");
  if (!text) {
    el.classList.add("hidden");
    return;
  }
  el.classList.remove("hidden");
  el.textContent = text;
  $("stderr-meta").textContent = `${total} 字节 · stderr 通道（fprintf/perror 分流）`;
}

// ── 渲染：结果 ───────────────────────────────────────────
function renderRunResult(r) {
  $("ret-value").textContent = r.status === "finished" ? String(r.return_value) : "—";
  $("steps-value").textContent = String(r.steps_executed ?? "—");
}

function renderOutput(delta, total) {
  const el = $("stdout-box");
  el.textContent = delta === "" ? "（无 stdout 输出）" : delta;
  el.classList.toggle("empty", delta === "");
  $("stdout-meta").textContent = `${total} 字节 · output.delta 全量拉取`;
}

function renderDiagnostics(diags) {
  const el = $("diag-list");
  if (!diags || diags.length === 0) {
    el.innerHTML = '<div class="muted">无编译期诊断</div>';
    return;
  }
  el.innerHTML = diags
    .map(
      (d) =>
        `<div class="diag ${esc(d.severity)}"><span class="code">${esc(d.code)}</span>` +
        `<span class="loc">${esc(d.filename || "main.c")} 行 ${d.line}:${d.column}</span> ${esc(d.message)}` +
        (d.fix_suggestion ? `<div class="fix">✚ ${esc(d.fix_suggestion)}</div>` : "") +
        `</div>`
    )
    .join("");
}

function renderNote(text, total) {
  const el = $("note-box");
  if (!text) {
    el.classList.add("hidden");
    return;
  }
  el.classList.remove("hidden");
  el.innerHTML = esc(text).replace(/\n/g, "<br>");
  $("note-meta").textContent = `${total} 字节 · note 审计流（Latin-1 字节域按 UTF-8 还原）`;
}
function renderPpTrace(trace) {
  const el = $("diag-list");
  if (trace && trace.length) {
    const div = document.createElement("div");
    div.className = "pp-trace";
    div.innerHTML =
      '<div class="pp-title">宏展开轨迹（preprocessor_trace）</div>' +
      trace.map((t) => `<div class="pp-line">${esc(t)}</div>`).join("");
    el.appendChild(div);
  }
}

function renderTrap(text) {
  const el = $("trap-box");
  if (!text) {
    el.classList.add("hidden");
    return;
  }
  el.classList.remove("hidden");
  el.innerHTML = esc(text).replace(/\n/g, "<br>");
}

// 参考对照（Clang golden 预置真值——诚实边界在文案）
function renderReference(runResult, stdout, kase) {
  const el = $("ref-box");
  if (!kase || (!kase.referenceOutput && !kase.referenceTrap)) {
    el.innerHTML = '<div class="muted">（本用例未预置参考值）</div>';
    return;
  }
  let match, expect;
  if (kase.referenceKind === "stdout") {
    expect = kase.referenceOutput;
    match = stdout === expect;
    el.innerHTML =
      `<div class="${match ? "match" : "mismatch"}">${match ? "✓ 一致" : "✗ 不一致"}</div>` +
      `<pre class="ref-pre">Clang golden（预置真值）: ${esc(JSON.stringify(expect))}\nVitro 实跑 stdout      : ${esc(JSON.stringify(stdout))}</pre>`;
  } else {
    expect = kase.referenceTrap;
    match = (runResult.trap || "").includes(expect);
    el.innerHTML =
      `<div class="${match ? "match" : "mismatch"}">${match ? "✓ 诊断类别一致（含 " + esc(expect) + "）" : "✗ 未复现预期诊断"}</div>` +
      `<pre class="ref-pre">参考真值：CI 防线对该诊断类别的断言（由 wasm 宿主冒烟与 shadow 防线持续对拍）</pre>`;
  }
}

// ── 渲染：内存地图 ───────────────────────────────────────
function renderMemory(mem) {
  $("mem-stats").innerHTML =
    `<span>全局 ${mem.region_counts.global}</span>` +
    `<span>堆 ${mem.region_counts.heap}</span>` +
    `<span>栈 ${mem.region_counts.stack}</span>` +
    `<span>分配计数 ${mem.alloc_counter}</span>` +
    `<span>free_list ${mem.free_list.length}</span>` +
    `<span>隔离区 ${mem.quarantine.bytes} / ${mem.quarantine.budget} 字节（${mem.quarantine.blocks} 块）</span>`;

  const band = $("mem-band-full");
  band.innerHTML = "";
  for (const r of mem.regions) placeBlock(band, r, r.addr / MEM_TOTAL, Math.max(r.size / MEM_TOTAL, 0.004));
  const heapEnd = Math.max(mem.heap_offset, ...mem.regions.filter((r) => r.is_heap).map((r) => r.addr + r.size), mem.heap_base + 64);
  const heapSpan = heapEnd - mem.heap_base;
  const zoom = $("mem-band-heap");
  zoom.innerHTML = "";
  for (const r of mem.regions.filter((r) => r.is_heap)) {
    const left = (r.addr - mem.heap_base) / heapSpan;
    placeBlock(zoom, r, left, Math.max(r.size / heapSpan, 0.02));
  }
  $("mem-zoom-label").textContent =
    `堆区放大 0x${mem.heap_base.toString(16)} – 0x${heapEnd.toString(16)}（span ${heapSpan} B）`;

  const q = mem.quarantine;
  $("quar-bar-fill").style.width = `${Math.min((q.bytes / q.budget) * 100, 100)}%`;
  $("quar-label").textContent = `quarantine（UAF 检测窗）：${q.blocks} 块 / ${q.bytes} B，预算 ${q.budget} B`;

  $("mem-table").innerHTML =
    "<tr><th>地址</th><th>大小</th><th>名称</th><th>类型</th><th>段</th><th>状态</th><th>分配行</th><th>来源</th></tr>" +
    mem.regions
      .map(
        (r) =>
          `<tr class="${r.is_freed ? "freed" : ""}"><td>0x${r.addr.toString(16)}</td><td>${r.size} B</td>` +
          `<td>${esc(r.name)}</td><td>${esc(r.ty)}</td><td>${esc(r.kind)}</td>` +
          `<td>${r.is_freed ? "freed（隔离中）" : "活跃"}</td><td>${r.alloc_line || "—"}</td><td>${esc(r.alloc_by)}</td></tr>`
      )
      .join("");
}

function placeBlock(band, r, left, width) {
  const b = document.createElement("div");
  b.className = "blk " + r.kind + (r.is_freed ? " freed" : "");
  b.style.left = `${Math.min(left * 100, 99.6)}%`;
  b.style.width = `${width * 100}%`;
  b.title = `${r.name} · ${r.ty} · ${r.size} B @0x${r.addr.toString(16)}${r.is_freed ? " · freed" : ""}`;
  band.appendChild(b);
}

// ── 诊断手册（error_catalog）────────────────────────────
async function loadCatalog() {
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

function renderCatalog(query) {
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
function renderProto(cap, contracts, labels) {
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

// ── 用例切换 ─────────────────────────────────────────────
function selectCase() {
  const k = DEMO_CASES.find((k) => k.id === $("case-select").value);
  if (!k) return;
  $("editor").value = k.source;
  $("case-blurb").textContent = k.blurb;
  $("stdin-row").classList.remove("active");
  pendingRun = null;
  setStatus("idle", "就绪");
  ["stdout-box", "trap-box", "ref-box", "mem-band-full", "mem-band-heap", "mem-table", "mem-stats", "diag-list", "note-box", "stderr-box", "stderr-meta", "note-meta"].forEach(
    (id) => {
      const el = $(id);
      if (id === "mem-table") el.innerHTML = "";
      else if (["trap-box", "stdin-row", "stderr-box", "stderr-meta", "note-box", "note-meta"].includes(id)) el.classList.add("hidden");
      else el.innerHTML = '<span class="muted">（点「运行」后展示）</span>';
    }
  );
  $("stdout-meta").textContent = "";
}

// ── 启动 ─────────────────────────────────────────────────
(async function boot() {
  bindTabs();
  const sel = $("case-select");
  sel.innerHTML = DEMO_CASES.map((k) => `<option value="${k.id}">${k.label}</option>`).join("");
  sel.onchange = selectCase;
  $("run-btn").onclick = runCase;
  $("feed-btn").onclick = feedStdin;
  $("cfg-btn").onclick = applyConfig;
  $("cat-search").oninput = (e) => renderCatalog(e.target.value);
  try {
    gw = await loadGateway();
  } catch (e) {
    setStatus("err", "无法加载 wasm-gc");
    $("boot-error").classList.remove("hidden");
    $("boot-error").textContent =
      "wasm-gc 加载失败（" + e.message + "）——本页需要支持 wasm-gc 与 js-string builtins 的现代浏览器（Chrome/Edge 130+、Firefox 134+）。";
    return;
  }
  $("eng-ver").textContent = gw.engine_version();
  $("proto-ver").textContent = gw.protocol_version();
  const cap = bodyOf(invoke({ method: "capabilities" }));
  const contracts = bodyOf(invoke({ method: "contracts" }));
  const labels = bodyOf(invoke({ method: "semantic_labels" }));
  renderProto(cap, contracts, labels);
  renderCfgView(bodyOf(invoke({ method: "config.get" })));
  bodyOf(invoke({ method: "ping" }));
  loadCatalog();
  selectCase();
})();
