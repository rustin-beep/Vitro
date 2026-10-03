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
let caseDd, sceneDd, speedDd; // 自绘下拉实例（原生 select 弹出层为 OS 渲染，无法跟随主题）

// 自绘下拉：闭合态按钮 + 浮层 listbox；键盘（Enter/Space 开、↑↓ 浏览、
// Enter 确认、Esc 撤回）、点击外部关闭、aria 展开态。
function makeDropdown(hostId, items, value, onChange) {
  const host = $(hostId);
  host.innerHTML =
    '<button type="button" class="dd-btn" aria-haspopup="listbox" aria-expanded="false">' +
    '<span class="dd-label"></span>' +
    '<svg class="dd-chev" viewBox="0 0 24 24" width="14" height="14" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>' +
    '</button><div class="dd-list" role="listbox" hidden></div>';
  const btn = host.querySelector(".dd-btn");
  const label = host.querySelector(".dd-label");
  const list = host.querySelector(".dd-list");
  let cur = value;
  let committed = value;
  const idxOf = () => items.findIndex((i) => i.v === cur);
  function syncLabel() {
    const it = items[idxOf()];
    label.textContent = it ? it.label : "";
  }
  function renderList() {
    list.innerHTML = items
      .map((i) =>
        `<button type="button" class="dd-opt${i.v === cur ? " on" : ""}" role="option" aria-selected="${i.v === cur}" data-v="${esc(String(i.v))}">${esc(i.label)}</button>`
      )
      .join("");
  }
  function open() {
    committed = cur;
    renderList();
    list.hidden = false;
    host.setAttribute("data-open", "");
    btn.setAttribute("aria-expanded", "true");
    const el = list.querySelector(".dd-opt.on");
    if (el) el.scrollIntoView({ block: "nearest" });
  }
  function close() {
    list.hidden = true;
    host.removeAttribute("data-open");
    btn.setAttribute("aria-expanded", "false");
  }
  function pick(v) {
    cur = v;
    syncLabel();
    close();
    if (onChange) onChange(v);
  }
  btn.onclick = () => (list.hidden ? open() : close());
  list.onclick = (e) => {
    const opt = e.target.closest(".dd-opt");
    if (opt) pick(opt.dataset.v);
  };
  btn.onkeydown = (e) => {
    if (list.hidden) {
      if (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        open();
      }
      return;
    }
    if (e.key === "Escape") {
      e.stopPropagation();
      cur = committed; // 撤回浏览未确认的值
      syncLabel();
      close();
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const idx = Math.max(0, idxOf()) + (e.key === "ArrowDown" ? 1 : -1);
      cur = items[Math.max(0, Math.min(idx, items.length - 1))].v;
      renderList();
      syncLabel();
      const el = list.querySelector(".dd-opt.on");
      if (el) el.scrollIntoView({ block: "nearest" });
    } else if (e.key === "Enter") {
      e.preventDefault();
      pick(cur);
    }
  };
  document.addEventListener("click", (e) => {
    if (!list.hidden && !e.target.closest("#" + host.id)) close();
  });
  syncLabel();
  return {
    get value() { return cur; },
  };
}

function setStatus(kind, text) {
  const el = $("status-pill");
  el.className = "pill " + kind;
  el.textContent = text;
}

function esc(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

// ── C 语法高亮（F-1b①）───────────────────────────────────
// 页面侧独立小型着色器：零第三方依赖，与引擎 lexer 无契约绑定（呈现层
// 自治，F-2a SVG 包接管渲染时本逻辑随 JS 侧一起迁走，CSS transition 原样保留）。
// 形态（修订版）：textarea 前景透明只留光标 + 背后逐行行盒高亮层；软换行
// 自动折行（无横向滚动）+ 编辑器高度随内容伸缩（滚动收口在外层 .editor-wrap，
// 两层恒等宽保证折行断点一致——textarea 自身不滚，滚动条不会挤压文本区）。
const C_KEYWORDS = new Set(
  (
    "auto break case char const continue default do double else enum extern " +
    "float for goto if inline int long register restrict return short signed " +
    "sizeof static struct switch typedef union unsigned void volatile while " +
    "_Bool _Complex _Imaginary bool true false nullptr"
  ).split(" ")
);
// 组合正则按优先级一次扫描：块注释/行注释/字符串/字符/预处理行/数字/标识符。
// 未闭合的注释与字符串也吞到末尾（打字中间态高亮稳定）；预处理行匹配
// ^\s*#（m 标志），因注释/字符串组在前，处于它们内部的 # 不会被误判。
const C_TOKEN =
  /(\/\*[\s\S]*?(?:\*\/|$))|(\/\/[^\n]*)|("(?:\\.|[^"\\\n])*"?)|('(?:\\.|[^'\\\n])*'?)|(^[ \t]*#[^\n]*)|(\.?\d(?:[\w.]|[eEpP][+-])*)|([A-Za-z_]\w*)/gm;

function tokenizeC(src) {
  const toks = [];
  let last = 0;
  let m;
  C_TOKEN.lastIndex = 0;
  while ((m = C_TOKEN.exec(src))) {
    if (m.index > last) toks.push({ cls: "", text: src.slice(last, m.index) });
    const cls = m[1] || m[2] ? "syn-com"
      : m[3] || m[4] ? "syn-str"
      : m[5] ? "syn-pre"
      : m[6] ? "syn-num"
      : C_KEYWORDS.has(m[7]) ? "syn-key"
      : "";
    toks.push({ cls, text: m[0] });
    last = m.index + m[0].length;
    if (m[0].length === 0) C_TOKEN.lastIndex += 1; // 防零宽匹配死循环
  }
  if (last < src.length) toks.push({ cls: "", text: src.slice(last) });
  return toks;
}

// 整体 tokenize 后按 \n 切分组装行盒（块注释等跨行 token 的着色状态
// 在行间延续）；每行一个 .cl，行号 .ln 内嵌行盒，折行后行号不重复。
function highlightLines(src) {
  const rows = [];
  let cur = "";
  const feed = (cls, text) => {
    const parts = text.split("\n");
    for (let i = 0; i < parts.length; i++) {
      if (i > 0) {
        rows.push(cur);
        cur = "";
      }
      if (parts[i]) cur += cls ? `<span class="${cls}">${esc(parts[i])}</span>` : esc(parts[i]);
    }
  };
  for (const t of tokenizeC(src)) feed(t.cls, t.text);
  rows.push(cur);
  return rows
    .map((html, i) => `<div class="cl"><span class="ln">${i + 1}</span><span class="lc">${html || "\u200b"}</span></div>`)
    .join("");
}

// input 同步渲染（不走 rAF）：textarea 高度即时跟随内容，消除打字回车
// 瞬间 textarea 内部出现溢出的时序差。
function renderEditorDecor() {
  const ta = $("editor");
  if (!ta) return;
  $("editor-hl").innerHTML = highlightLines(ta.value);
}

function initEditorDecor() {
  const ta = $("editor");
  ta.addEventListener("input", renderEditorDecor);
  renderEditorDecor();
}

// ── 行跳转（F-1 视觉件）+ 高亮闪烁定位（F-1b②动效）──────────
function scrollToLine(line) {
  line = Number(line);
  if (!line || line < 1) return;
  const wrapEl = $("editor-wrap");
  const row = wrapEl.querySelectorAll("#editor-hl .cl")[line - 1];
  if (!row) return;
  // 目标行滚到编辑器视口中部（offsetTop 相对 .editor-lay，即内容坐标）
  wrapEl.scrollTop = Math.max(0, row.offsetTop - wrapEl.clientHeight / 2);
  const hlEl = $("editor-hl");
  hlEl.querySelectorAll(".flash-on").forEach((el) => el.classList.remove("flash-on"));
  hlEl.querySelectorAll(".cl.cur").forEach((el) => el.classList.remove("cur"));
  void hlEl.offsetWidth; // 重触发闪烁动画
  row.classList.add("flash-on", "cur");
  const onEnd = () => {
    row.classList.remove("flash-on");
    row.removeEventListener("animationend", onEnd);
  };
  row.addEventListener("animationend", onEnd);
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
  const kase = DEMO_CASES.find((k) => k.id === caseDd.value) || {};
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
      // 显示 stdin 行：HTML 初始带 .hidden（display:none !important），
      // 必须显式移除（历史上这里操作的是无消费者的 .active 类，行永不出现）
      $("stdin-row").classList.remove("hidden");
      renderRunResult(rr);
      renderMemory(bodyOf(invoke({ method: "memory.regions" })));
      // scanf 暂停前的 printf 输出已在通道里（如提示语 "n="）——即时拉取显示，
      // 否则要等喂入续跑后才见（2026-10-03 用户问交互时实测发现的显示缺口）
      const o = bodyOf(invoke({ method: "output.delta", params: { cursor: 0, stream: "stdout" } }));
      renderOutput(latin1ToUtf8(o.delta) || "", o.total || 0);
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
  $("stdin-row").classList.add("hidden");
  const kase = DEMO_CASES.find((k) => k.id === caseDd.value) || {};
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
  const ret = $("ret-value");
  const steps = $("steps-value");
  ret.textContent = r.status === "finished" ? String(r.return_value) : "—";
  steps.textContent = String(r.steps_executed ?? "—");
  for (const el of [ret, steps]) {
    el.classList.remove("flash-in"); // 数字更新淡入，与 stdout 同款
    void el.offsetWidth;
    el.classList.add("flash-in");
  }
}

function renderOutput(delta, total) {
  const el = $("stdout-box");
  el.textContent = delta === "" ? "（无 stdout 输出）" : delta;
  el.classList.toggle("empty", delta === "");
  el.classList.remove("flash-in"); // F-1b②：重触发淡入
  void el.offsetWidth;
  el.classList.add("flash-in");
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
      (d, i) =>
        `<div class="diag ${esc(d.severity)}${d.line > 0 ? " jumpy" : ""}" style="--i:${i}"` +
        (d.line > 0 ? ` data-line="${d.line}" title="点击跳到 main.c 第 ${d.line} 行"` : "") +
        `><span class="code">${esc(d.code)}</span>` +
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
// 堆区放大视角的跨度计算（内存地图 tab 与动画演示 tab 共用）
function heapSpanOf(mem) {
  const heapEnd = Math.max(
    mem.heap_offset ?? 0,
    ...mem.regions.filter((r) => r.is_heap).map((r) => r.addr + r.size),
    mem.heap_base + 64
  );
  return { heapBase: mem.heap_base, heapEnd, span: heapEnd - mem.heap_base };
}

function renderMemory(mem) {
  $("mem-stats").innerHTML =
    `<span>全局 ${mem.region_counts.global}</span>` +
    `<span>堆 ${mem.region_counts.heap}</span>` +
    `<span>栈 ${mem.region_counts.stack}</span>` +
    `<span>分配计数 ${mem.alloc_counter}</span>` +
    `<span>free_list ${mem.free_list.length}</span>` +
    `<span>隔离区 ${mem.quarantine.bytes} / ${mem.quarantine.budget} 字节（${mem.quarantine.blocks} 块）</span>`;

  const band = $("mem-band-full");
  bandRender(
    band,
    mem.regions.map((r) => ({ r, left: r.addr / MEM_TOTAL, width: Math.max(r.size / MEM_TOTAL, 0.004) }))
  );
  const { heapBase, span: heapSpan } = heapSpanOf(mem);
  const zoom = $("mem-band-heap");
  bandRender(
    zoom,
    mem.regions
      .filter((r) => r.is_heap)
      .map((r) => ({ r, left: (r.addr - heapBase) / heapSpan, width: Math.max(r.size / heapSpan, 0.02) }))
  );
  $("mem-zoom-label").textContent =
    `堆区放大 0x${heapBase.toString(16)} – 0x${heapSpanOf(mem).heapEnd.toString(16)}（span ${heapSpan} B）`;

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

// 条块 keyed 复用（F-1b②）：addr/size 过渡的前提是元素存活——同 key 只更新
// 位置/尺寸/状态类，transition 才吃得到变化；本帧消失的 key 直接移除。
// key 含 addr+size+name：同一位置复分配出的新块视为新块（瞬现，不跨会话漂移）。
function bandRender(band, entries) {
  for (const n of Array.from(band.childNodes)) {
    // 占位提示（HTML 静态 .muted.center 与 selectCase 重置的 .muted 两种）一律清，
    // 条块本体（.blk）是复用对象，不能动
    if (!(n.nodeType === 1 && n.classList.contains("blk"))) n.remove();
  }
  const seen = new Set();
  for (const { r, left, width } of entries) {
    const key = `${r.addr}:${r.size}:${r.name}`;
    seen.add(key);
    let b = band.querySelector(`[data-key="${CSS.escape(key)}"]`);
    if (!b) {
      b = document.createElement("div");
      b.dataset.key = key;
      band.appendChild(b);
    }
    b.className = "blk " + r.kind + (r.is_freed ? " freed" : "");
    b.style.left = `${Math.min(left * 100, 99.6)}%`;
    b.style.width = `${width * 100}%`;
    b.title = `${r.name} · ${r.ty} · ${r.size} B @0x${r.addr.toString(16)}${r.is_freed ? " · freed" : ""}`;
  }
  for (const b of band.querySelectorAll(".blk")) {
    if (!seen.has(b.dataset.key)) b.remove();
  }
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

// ── 动画演示（帧采集播放器）──────────────────────────────
// 原理：同一程序按步数上限阶梯（config.set max_steps）反复实跑，每档拉取
// memory.regions / output.delta 快照作一帧——每一帧都是引擎真实状态，
// 页面只负责按帧播放。事件时间轴由相邻帧差分推导（同样源自引擎数据）。
const ANIM_SCENES = ["malloc_free", "uaf", "infinite"];
const ANIM_MAX_MID_FRAMES = 44;
let animData = null; // { frames, events }
let animIdx = 0;
let animTimer = 0;

function animGrab(kase, cap) {
  gw.reset();
  bodyOf(invoke({ method: "session.create" }));
  bodyOf(invoke({ method: "config.set", params: { max_steps: cap } }));
  bodyOf(invoke({ method: "compile", params: { source: kase.source } }));
  const r = bodyOf(invoke({ method: "run" }));
  const m = bodyOf(invoke({ method: "memory.regions" }));
  const o = bodyOf(invoke({ method: "output.delta", params: { cursor: 0, stream: "stdout" } }));
  return {
    cap,
    steps: r.steps_executed ?? 0,
    status: r.status,
    ret: r.return_value,
    trap: r.trap || "",
    regions: m.regions,
    quar: m.quarantine,
    alloc: m.alloc_counter,
    heapBase: m.heap_base,
    heapOffset: m.heap_offset,
    out: latin1ToUtf8(o.delta) || "",
  };
}

async function animCollect(sceneId) {
  const kase = DEMO_CASES.find((k) => k.id === sceneId);
  if (!kase) return null;
  const frames = [];
  // 帧 0：不执行，初始态（VFS 预设文件已在堆上）
  gw.reset();
  bodyOf(invoke({ method: "session.create" }));
  const m0 = bodyOf(invoke({ method: "memory.regions" }));
  frames.push({ cap: 0, steps: 0, status: "idle", ret: undefined, trap: "", regions: m0.regions, quar: m0.quarantine, alloc: m0.alloc_counter, heapBase: m0.heap_base, heapOffset: m0.heap_offset, out: "" });
  // 终帧：无步数上限（死循环用 configHint 的预算即其教学终态）
  const finalCap = (kase.configHint && kase.configHint.max_steps) || 10000000;
  const fin = animGrab(kase, finalCap);
  const total = fin.steps;
  // 中间帧：小步数程序逐步采样，大步数程序均匀采样
  const caps = [];
  if (total > 1) {
    if (total - 1 <= ANIM_MAX_MID_FRAMES) {
      for (let c = 1; c <= total - 1; c++) caps.push(c);
    } else {
      for (let i = 1; i <= ANIM_MAX_MID_FRAMES; i++) caps.push(Math.max(1, Math.round((i * (total - 1)) / ANIM_MAX_MID_FRAMES)));
    }
  }
  const seen = new Set([0, finalCap]);
  let n = 0;
  for (const c of caps) {
    if (seen.has(c)) continue;
    seen.add(c);
    frames.push(animGrab(kase, c));
    if (++n % 8 === 0) await new Promise((r2) => setTimeout(r2)); // 分片，让 UI 喘息
  }
  frames.push(fin);
  // 事件差分（相邻帧的 region 集与 stdout 对比——推导自引擎数据）
  const keyOf = (r) => `${r.addr}:${r.size}:${r.name}`;
  const events = [];
  for (let i = 1; i < frames.length; i++) {
    const a = frames[i - 1];
    const b = frames[i];
    const ak = new Map(a.regions.map((r) => [keyOf(r), r]));
    const bk = new Map(b.regions.map((r) => [keyOf(r), r]));
    for (const [k, r] of bk) {
      if (!ak.has(k)) {
        const verb = r.kind === "stack" ? "栈帧" : r.kind === "global" ? "全局段" : "分配";
        events.push({ f: i, text: `第 ${b.steps} 步 · ${verb} ${r.name}（${r.size} B @0x${r.addr.toString(16)}）` });
      }
    }
    for (const [k, r0] of ak) {
      const r1 = bk.get(k);
      if (r1 && !r0.is_freed && r1.is_freed) events.push({ f: i, text: `第 ${b.steps} 步 · 释放 ${r1.name} → 隔离区（${r1.size} B）` });
    }
    if (b.out.length > a.out.length) events.push({ f: i, text: `第 ${b.steps} 步 · 输出 ${JSON.stringify(b.out.slice(a.out.length))}` });
  }
  if (fin.status === "trap" && fin.trap) {
    events.push({ f: frames.length - 1, text: `终止 · ${fin.trap.split("\n")[0].slice(0, 64)}`, terminal: true });
  } else if (fin.status === "finished") {
    events.push({ f: frames.length - 1, text: `程序结束 · 返回码 ${fin.ret}`, terminal: true });
  }
  return { frames, events };
}

function animGoto(i) {
  if (!animData) return;
  animIdx = Math.max(0, Math.min(i, animData.frames.length - 1));
  animRender();
}

function animRender() {
  const f = animData.frames[animIdx];
  const isFinal = animIdx === animData.frames.length - 1;
  const full = f.regions.map((r) => ({ r, left: r.addr / MEM_TOTAL, width: Math.max(r.size / MEM_TOTAL, 0.004) }));
  bandRender($("anim-band-full"), full);
  const heapEnd = Math.max(f.heapOffset ?? 0, ...f.regions.filter((r) => r.is_heap).map((r) => r.addr + r.size), f.heapBase + 64);
  const span = Math.max(heapEnd - f.heapBase, 1);
  bandRender(
    $("anim-band-heap"),
    f.regions
      .filter((r) => r.is_heap)
      .map((r) => ({ r, left: (r.addr - f.heapBase) / span, width: Math.max(r.size / span, 0.02) }))
  );
  $("anim-seek").value = animIdx;
  $("anim-progress").textContent = `帧 ${animIdx + 1}/${animData.frames.length} · 第 ${f.steps} 步 · 隔离区 ${f.quar.blocks} 块`;
  // 阶段说明：中间帧是「步数上限截断的快照」，终帧才是真实终态
  let last = null;
  for (const e of animData.events) if (e.f <= animIdx) last = e;
  const stateTxt = isFinal
    ? f.status === "finished" ? `程序结束（返回码 ${f.ret}）`
      : f.status === "trap" ? "受检终止：" + (f.trap.split("\n")[0] || "").slice(0, 72)
      : f.status
    : `快照于第 ${f.steps} 步（步数上限 ${f.cap} 截断）`;
  let tail;
  if (f.steps === 0) tail = "初始状态：VFS 预设文件已位于堆底";
  else if (last && !(isFinal && last.terminal)) tail = last.text; // 终帧 trap 文案已在 stateTxt，不重复
  else tail = isFinal ? "" : "VM 指令推进中…";
  $("anim-phase").textContent = `【${stateTxt}】${tail}`;
  const chips = $("anim-events").children;
  for (let j = 0; j < animData.events.length; j++) chips[j].classList.toggle("on", animData.events[j].f <= animIdx);
  // stdout 回放（内容变化时淡入）
  const el = $("anim-out");
  const prev = animIdx > 0 ? animData.frames[animIdx - 1] : null;
  el.textContent = f.out === "" ? "（暂无输出）" : f.out;
  el.classList.toggle("empty", f.out === "");
  if (!prev || prev.out !== f.out) {
    el.classList.remove("flash-in");
    void el.offsetWidth;
    el.classList.add("flash-in");
  }
  $("anim-out-meta").textContent = `${f.out.length} 字节（截至第 ${f.steps} 步）`;
}

function animStopTimer() {
  if (animTimer) {
    clearInterval(animTimer);
    animTimer = 0;
  }
  $("anim-play").textContent = "▶ 播放";
}

function animPlay() {
  if (!animData) return;
  animStopTimer();
  if (animIdx >= animData.frames.length - 1) animGoto(0); // 播完再点 = 重播
  $("anim-play").textContent = "⏸ 暂停";
  animTimer = setInterval(() => {
    if (animIdx >= animData.frames.length - 1) {
      animStopTimer();
      return;
    }
    animGoto(animIdx + 1);
  }, Number(speedDd.value) || 200);
}

async function animLoadScene(sceneId) {
  animStopTimer();
  animData = null;
  animIdx = 0;
  $("anim-events").innerHTML = "";
  $("anim-band-full").innerHTML = "";
  $("anim-band-heap").innerHTML = "";
  $("anim-phase").textContent = "采集中：按步数上限阶梯反复实跑引擎…";
  $("anim-play").disabled = true;
  $("anim-play").textContent = "… 采集中";
  await new Promise((r) => setTimeout(r)); // 让按钮态先渲染
  animData = await animCollect(sceneId);
  $("anim-events").innerHTML = animData.events
    .map((e) => `<span class="evt${e.terminal ? " terminal" : ""}">${esc(e.text)}</span>`)
    .join("");
  $("anim-seek").max = animData.frames.length - 1;
  $("anim-play").disabled = false;
  animRender();
  animPlay(); // 采集完自动播放
}

function bindAnim() {
  sceneDd = makeDropdown(
    "anim-scene",
    ANIM_SCENES.map((id) => {
      const k = DEMO_CASES.find((x) => x.id === id);
      return { v: id, label: k ? k.label : id };
    }),
    ANIM_SCENES[0],
    (v) => animLoadScene(v)
  );
  speedDd = makeDropdown(
    "anim-speed",
    [ { v: "400", label: "0.5×" }, { v: "200", label: "1×" }, { v: "100", label: "2×" } ],
    "200",
    () => { if (animTimer) animPlay(); } // 播放中调速 = 重启节奏
  );
  $("anim-play").onclick = () => {
    if (!animData) return;
    animTimer ? animStopTimer() : animPlay();
  };
  $("anim-reset").onclick = () => {
    if (!animData) return;
    animStopTimer();
    animGoto(0);
  };
  $("anim-seek").oninput = (e) => {
    animStopTimer();
    animGoto(Number(e.target.value));
  };
}

// ── 用例切换 ─────────────────────────────────────────────
function selectCase() {
  const k = DEMO_CASES.find((k) => k.id === caseDd.value);
  if (!k) return;
  $("editor").value = k.source;
  renderEditorDecor();
  $("case-blurb").textContent = k.blurb;
  $("stdin-row").classList.add("hidden");
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

// ── 界面设置（五主题 / 编辑器字号 / 动效开关；localStorage 持久化）────────
// 主题 id 与 tokens.css 的 data-theme 取值一一对应；昼 = ice/rose/paper，
// 夜 = glass/soft（header 快捷按钮在组间切换：夜→ice、昼→glass）。
// 旧值迁移（2026-10-03 换肤批）："light"→ice、"dark"→glass，读到即回写。
function storeGet(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }
function storeSet(key, val) { try { localStorage.setItem(key, val); } catch (e) {} }

const THEMES = ["ice", "rose", "paper", "glass", "soft"];
const NIGHT_THEMES = new Set(["glass", "soft"]);

function syncSeg(segId, v) {
  const seg = $(segId);
  if (!seg) return;
  for (const b of seg.querySelectorAll("button")) b.classList.toggle("on", b.dataset.v === v);
}

function setTheme(v) {
  document.documentElement.setAttribute("data-theme", v);
  document.documentElement.setAttribute("data-shade", NIGHT_THEMES.has(v) ? "night" : "day");
  storeSet("vitro-theme", v);
  syncSeg("set-theme", v);
}

function applyEdFont(px) {
  // 编辑器对齐契约：hl 与 textarea 两层的 font 都引用 --ed-fs，改一处即同步
  document.documentElement.style.setProperty("--ed-fs", px);
  syncSeg("set-font", px);
}

function applyMotion(v) {
  if (v === "off") document.documentElement.setAttribute("data-motion", "off");
  else document.documentElement.removeAttribute("data-motion");
  syncSeg("set-motion", v);
}

(function initSettings() {
  let saved = storeGet("vitro-theme");
  if (saved === "light") saved = "ice"; // 旧双值迁移
  else if (!saved || saved === "dark") saved = "glass";
  if (!THEMES.includes(saved)) saved = "glass";
  setTheme(saved);
  const savedFont = storeGet("vitro-ed-font");
  applyEdFont(savedFont === "12px" || savedFont === "15px" ? savedFont : "13px");
  applyMotion(storeGet("vitro-motion") === "off" ? "off" : "on");

  const themeBtn = $("theme-toggle");
  if (themeBtn) {
    themeBtn.onclick = () => {
      const cur = document.documentElement.getAttribute("data-theme");
      setTheme(NIGHT_THEMES.has(cur) ? "ice" : "glass");
    };
  }
  const segBind = (segId, apply) => {
    $(segId).addEventListener("click", (e) => {
      const b = e.target.closest("button");
      if (b) apply(b.dataset.v);
    });
  };
  segBind("set-theme", setTheme);
  segBind("set-font", (px) => { applyEdFont(px); storeSet("vitro-ed-font", px); });
  segBind("set-motion", (v) => { applyMotion(v); storeSet("vitro-motion", v); });

  // 面板开关：齿轮 toggle / 点击面板外关闭 / ESC 关闭
  const panel = $("settings-panel");
  const toggle = $("settings-toggle");
  const setOpen = (open) => {
    panel.classList.toggle("hidden", !open);
    toggle.setAttribute("aria-expanded", String(open));
  };
  toggle.addEventListener("click", () => setOpen(panel.classList.contains("hidden")));
  document.addEventListener("click", (e) => {
    if (!panel.classList.contains("hidden") && !e.target.closest(".settings-wrap")) setOpen(false);
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !panel.classList.contains("hidden")) setOpen(false);
  });
})();

// ── 启动 ─────────────────────────────────────────────────
(async function boot() {
  bindTabs();
  initEditorDecor();
  // 诊断卡点击跳行（F-1 视觉件：事件委托，卡片是批量重渲染的）
  $("diag-list").addEventListener("click", (e) => {
    const card = e.target.closest(".diag.jumpy");
    if (card) scrollToLine(card.dataset.line);
  });
  // 动画演示：首次切到该 tab 时懒采集（探针 + 播放器都在协议面内）
  bindAnim();
  document.querySelector('.tab[data-tab="anim"]').addEventListener(
    "click",
    () => {
      if (!animData && !$("anim-play").disabled) animLoadScene(sceneDd.value);
    },
    { once: true }
  );
  caseDd = makeDropdown(
    "case-select",
    DEMO_CASES.map((k) => ({ v: k.id, label: k.label })),
    DEMO_CASES[0].id,
    selectCase
  );
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
