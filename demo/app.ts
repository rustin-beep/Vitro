// Vitro 引擎浏览器单页 demo（second cut：协议面尽量全展示）。
// 承载形态：浏览器直调 gateway wasm-gc 单出口（S7 批五号产物，0.7.0 发布）
// ——零 npm 依赖、零后端；协议帧为 NDJSON，与 CI 的
// scripts/wasm_gateway/host.js 同语义（该脚本 16 断言即协议契约的真值源）。
// 定位是门面不是架构件：渲染逻辑暂放宿主页内 JS，MoonBit SVG 纯函数包
// 落地后由其接管（总计划既定路线）。
//
// 【拆分批 2026-10-04，refs #28】单体 1370 行 → 本入口胶水 + demo/js/ 十一模块
// （gw/util/state/editor/run/memory/catalog/calltree/timetravel/settings），
// ESM 零构建直开（<script type="module">）；纯数据函数经 node --test 锚定
// （demo/tests/，对历史 bug 窝点）。ESM 下 cases.js 的全局 DEMO_CASES 仍可
// 裸引用（普通 script 先行加载挂 window）。
"use strict";

import { loadGateway, setGateway, invoke, bodyOf, gateway } from "./js/gw.ts";
import { $, setStatus, isArrayAnimCase } from "./js/util.ts";
import { renderEditorDecor, initEditorDecor, scrollToLine } from "./js/editor.ts";
import { bindTabs, applyConfig, runCase, feedStdin, renderCfgView, resetPendingRun } from "./js/run.ts";
import { loadCatalog, renderCatalog, renderProto } from "./js/catalog.ts";
import { stepReset, bindAnim, applyCardFold, collectCurrentEditor } from "./js/timetravel.ts";
import { renderCourseTree, bindCasePicker } from "./js/course.ts";
import { setCurrentCase } from "./js/state.ts";
import { initSettings } from "./js/settings.ts";
import { initWorkspace } from "./js/workspace.ts";

// 课程树基础课选中（原 selectCase 语义照搬：编辑器/blurb/回放区过期/输出区清零；
// 工作区离开 guard 在 course.ts 课点击层统一处理，此处无需重复）
function selectCaseById(id: string) {
  const k = DEMO_CASES.find((k) => k.id === id);
  if (!k) return;
  setCurrentCase(id);
  const tabBtn = document.querySelector<HTMLElement>('.tabs .tab[data-tab="result"]');
  if (tabBtn) tabBtn.click(); // 内容页选课 → 切运行视图
  stepReset(); // 编辑器内容被用例覆盖，回放区过期
  ($("editor") as HTMLTextAreaElement).value = k.source;
  renderEditorDecor();
  $("case-blurb").textContent = k.blurb + (isArrayAnimCase(k.source) ? "（数组动画）" : "");
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
  // 点课即采集（课程心智统一：基础课与算法课同为「载入→回放」一步到位；
  // stdin 类用例采集停在等待输入提示——语义已有）
  void collectCurrentEditor();
}

// ── 界面设置（五主题 / 编辑器字号 / 动效开关；localStorage 持久化）────────
// 主题 id 与 tokens.css 的 data-theme 取值一一对应；昼 = ice/rose/paper，
// 夜 = glass/soft（header 快捷按钮在组间切换：夜→ice、昼→glass）。
// 旧值迁移（2026-10-03 换肤批）："light"→ice、"dark"→glass，读到即回写。

// ── 启动 ─────────────────────────────────────────────────
(async function boot() {
  initSettings();
  initWorkspace(); // 本地文件夹工作区（不支持的浏览器内部自隐入口）
  bindTabs();
  initEditorDecor();
  // 诊断卡点击跳行（F-1 视觉件：事件委托，卡片是批量重渲染的）
  $("diag-list").addEventListener("click", (e: MouseEvent) => {
    const card = (e.target as HTMLElement).closest<HTMLElement>(".diag.jumpy");
    if (card) scrollToLine(card.dataset.line as string);
  });
  bindAnim();
  // 课程树（内容入口归一：基础用例 + 43 族 + 变体 + 扩展——heron 式章节树；
  // 基础课点击走 selectCaseById，算法/扩展课走 course 模块内置载入）
  bindCasePicker(selectCaseById);
  renderCourseTree();
  $("run-btn").onclick = runCase;
  $("feed-btn").onclick = feedStdin;
  $("cfg-btn").onclick = applyConfig;
  $("cat-search").oninput = (e: Event) => renderCatalog((e.target as HTMLInputElement).value);
  // 信息卡收纳开关（卡体每帧/每次重置都会重建——委托必须挂在恒存的
  // step-tree 容器上；挂卡片自身的话 listener 随首次 innerHTML 重写即失效）
  $("step-tree").addEventListener("click", (e: MouseEvent) => {
    if (!(e.target as HTMLElement).closest(".nc-head")) return;
    const card = $("node-card");
    card.dataset.folded = card.dataset.folded === "1" ? "0" : "1";
    applyCardFold(card);
  });
  try {
    // 加载态先落盘（首访 wasm-gc 下载+实例化可到秒级——期间编辑器空白、
    // 无任何反馈，用户无从区分「加载中」与「坏了」而误刷新；加载提示带上
    // 超时指引，见 2026-10-05 UX 批用户拍板文案）
    setStatus("busy", "加载引擎中…");
    ($("editor") as HTMLTextAreaElement).value = [
      "// 加载中：引擎（wasm-gc）正在载入……",
      "// 若等待时间超过一分钟，建议刷新页面",
      "",
    ].join("\n");
    renderEditorDecor();
    setGateway(await loadGateway());
  } catch (e) {
    setStatus("err", "无法加载 wasm-gc");
    $("boot-error").classList.remove("hidden");
    $("boot-error").textContent =
      "wasm-gc 加载失败（" + (e instanceof Error ? e.message : String(e)) + "）——本页需要支持 wasm-gc 与 js-string builtins 的现代浏览器（Chrome/Edge 130+、Firefox 134+）。";
    ($("editor") as HTMLTextAreaElement).value = "// 引擎加载失败——见上方红色提示（需支持 wasm-gc 的现代浏览器）\n";
    renderEditorDecor();
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
  // 编辑器空态（2026-10-04 课程重构批用户拍板：初始不预设代码——内容页选课填入）
  ($("editor") as HTMLTextAreaElement).value = [
    "// 请输入代码，或者在「内容」页选择要预先填入的示例",
    "// 注意：从内容页选择时会覆盖编辑器里原有的代码",
    "// 提示：编辑器左侧行号单击可设置/取消引擎断点（采集回放将在断点处暂停）；",
    "//       回放条「引擎跳转」输入步号可直达引擎权威帧",
    "",
  ].join("\n");
  renderEditorDecor();
  setStatus("idle", "就绪"); // 初始 pill = busy 加载态（HTML 同步预置），引擎就绪此处才落回
})();
