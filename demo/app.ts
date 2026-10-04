// Vitro 引擎浏览器单页 demo（second cut：协议面尽量全展示）。
// 承载形态：浏览器直调 gateway wasm-gc 单出口（S7 批五号产物，0.7.0 发布）
// ——零 npm 依赖、零后端；协议帧为 NDJSON，与 CI 的
// scripts/wasm_gateway/host.js 同语义（该脚本 16 断言即协议契约的真值源）。
// 定位是门面不是架构件：渲染逻辑暂放宿主页内 JS，MoonBit SVG 纯函数包
// 落地后由其接管（总计划既定路线）。
//
// 【拆分批 2026-10-04，refs #28】单体 1370 行 → 本入口胶水 + demo/js/ 十模块
// （gw/util/state/editor/run/memory/catalog/calltree/timetravel/settings），
// ESM 零构建直开（<script type="module">）；纯数据函数经 node --test 锚定
// （demo/tests/，对历史 bug 窝点）。ESM 下 cases.js 的全局 DEMO_CASES 仍可
// 裸引用（普通 script 先行加载挂 window）。
"use strict";

import { loadGateway, setGateway, invoke, bodyOf, gateway } from "./js/gw.ts";
import { $, setStatus, makeDropdown, isArrayAnimCase } from "./js/util.ts";
import { renderEditorDecor, initEditorDecor, scrollToLine } from "./js/editor.ts";
import { bindTabs, applyConfig, runCase, feedStdin, renderCfgView, resetPendingRun } from "./js/run.ts";
import { loadCatalog, renderCatalog, renderProto } from "./js/catalog.ts";
import { stepReset, bindAnim, applyCardFold } from "./js/timetravel.ts";
import { setCaseDropdown } from "./js/state.ts";
import { initSettings } from "./js/settings.ts";

let caseDd; // 用例下拉实例（入口持有；state.js 暴露读口）

function selectCase() {
  const k = DEMO_CASES.find((k) => k.id === caseDd.value);
  if (!k) return;
  stepReset(); // 编辑器内容被用例覆盖，回放区过期
  $("editor").value = k.source;
  renderEditorDecor();
  $("case-blurb").textContent = k.blurb;
  $("stdin-row").classList.add("hidden");
  resetPendingRun();
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

// ── 启动 ─────────────────────────────────────────────────
(async function boot() {
  initSettings();
  bindTabs();
  initEditorDecor();
  // 诊断卡点击跳行（F-1 视觉件：事件委托，卡片是批量重渲染的）
  $("diag-list").addEventListener("click", (e) => {
    const card = e.target.closest(".diag.jumpy");
    if (card) scrollToLine(card.dataset.line);
  });
  bindAnim();
  caseDd = makeDropdown(
    "case-select",
    // 含数组声明的用例标注「· 数组」——时间旅行会对这类用例出柱状图动画
    DEMO_CASES.map((k) => ({
      v: k.id,
      label: k.label + (isArrayAnimCase(k.source) ? " · 数组动画" : ""),
    })),
    DEMO_CASES[0].id,
    selectCase
  );
  setCaseDropdown(caseDd);
  $("run-btn").onclick = runCase;
  $("feed-btn").onclick = feedStdin;
  $("cfg-btn").onclick = applyConfig;
  $("cat-search").oninput = (e) => renderCatalog(e.target.value);
  // 信息卡收纳开关（卡体每帧/每次重置都会重建——委托必须挂在恒存的
  // step-tree 容器上；挂卡片自身的话 listener 随首次 innerHTML 重写即失效）
  $("step-tree").addEventListener("click", (e) => {
    if (!e.target.closest(".nc-head")) return;
    const card = $("node-card");
    card.dataset.folded = card.dataset.folded === "1" ? "0" : "1";
    applyCardFold(card);
  });
  try {
    setGateway(await loadGateway());
  } catch (e) {
    setStatus("err", "无法加载 wasm-gc");
    $("boot-error").classList.remove("hidden");
    $("boot-error").textContent =
      "wasm-gc 加载失败（" + e.message + "）——本页需要支持 wasm-gc 与 js-string builtins 的现代浏览器（Chrome/Edge 130+、Firefox 134+）。";
    return;
  }
  const gw = gateway();
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
