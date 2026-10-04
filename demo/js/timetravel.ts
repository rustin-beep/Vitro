// Vitro demo · 时间旅行回放（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。）
"use strict";

import { invoke, bodyOf, gateway } from "./gw.js";
import { $, esc, latin1ToUtf8 } from "./util.js";
import { scrollToLine } from "./editor.js";
import { buildCallTree, renderCallTree, treeView } from "./calltree.js";
import { renderMemory } from "./memory.js";
import { currentCaseId, setSpeedDropdown, speedValue } from "./state.js";
import { makeDropdown } from "./util.js";

const STEP_FRAME_CAP = 4000; // 上限防大程序把回放 DOM/内存拖爆（infinite 类用例 20000 步在此截断，回放提示截断）
let stepData = null; // { frames, marks, stopped }
let stepIdx = 0;
let stepTimer = 0;

async function stepCollect() {
  const kase = DEMO_CASES.find((k) => k.id === currentCaseId()) || {};
  gateway().reset();
  bodyOf(invoke({ method: "session.create" }));
  const finalCap = (kase.configHint && kase.configHint.max_steps) || 10000000;
  bodyOf(invoke({
    method: "config.set",
    params: { max_steps: finalCap, call_depth_limit: 10000, deterministic: true, quarantine_budget: 262144 },
  }));
  const comp = bodyOf(invoke({ method: "compile", params: { source: $("editor").value } }));
  if (!comp.ok) return { error: "编译失败——先解决左侧诊断", frames: [], marks: [] };
  bodyOf(invoke({ method: "step.begin", params: {} }));
  const frames = [];
  let stopped = "";
  let batch;
  do {
    batch = bodyOf(invoke({ method: "step.next", params: {} }));
    if (batch.payloads) frames.push(...batch.payloads);
    if (batch.waiting_input) { stopped = "程序等待输入（scanf）——回放到暂停点为止"; break; }
    if (batch.trapped) { stopped = "受检终止：" + String(batch.trap_message || "").split("\n")[0]; break; }
  } while (!batch.finished && frames.length < STEP_FRAME_CAP);
  if (frames.length >= STEP_FRAME_CAP) stopped = stopped || `帧数超 ${STEP_FRAME_CAP} 上限，回放截断`;
  // 事件轴：semantic_label + 行号组合的变化点（教学事件序列）
  const marks = [];
  let last = null;
  frames.forEach((f, i) => {
    const k = (f.semantic_label || "") + "@" + f.code_line;
    if (k !== last) {
      marks.push({ idx: i, text: `第 ${f.step_index} 步 · ${f.semantic_label || "执行"}` });
      last = k;
    }
  });
  return { frames, marks, stopped };
}

function stepGoto(i) {
  if (!stepData) return;
  stepIdx = Math.max(0, Math.min(i, stepData.frames.length - 1));
  // 帧推进（seek/单步/播放）= 镜头回到当前事件重心——手动平移只在不动帧时保持
  treeView.follow = true;
  stepRender();
}

function stepRender() {
  const f = stepData.frames[stepIdx];
  $("anim-seek").value = stepIdx;
  $("anim-progress").textContent =
    `帧 ${stepIdx + 1}/${stepData.frames.length} · 第 ${f.step_index} 步` +
    (stepData.stopped ? " · " + stepData.stopped : "");
  const label = f.semantic_label || "执行";
  $("anim-phase").textContent = `【${label}】第 ${f.code_line} 行` + (f.func_name ? ` · ${f.func_name}` : "");
  scrollToLine(f.code_line, false); // 播放中只滚动+描边当前行，不闪烁
  // 局部变量表
  const vars = f.local_vars || [];
  $("step-vars").innerHTML = vars.length
    ? "<tr><th>名称</th><th>类型</th><th>值</th><th>地址</th></tr>" +
      vars
        .map((v) => `<tr><td>${esc(v.name)}</td><td>${esc(v.ty_name)}</td><td>${esc(v.value)}</td><td>0x${(v.addr || 0).toString(16)}</td></tr>`)
        .join("")
    : '<tr><td class="muted">（此帧无局部变量）</td></tr>';
  // 调用栈链（main → fib → …）
  const stack = f.call_stack || [];
  $("step-stack").innerHTML = stack.length
    ? stack
        .map((c, i) => (i ? '<span class="arrow">→</span>' : "") + `<span class="frm">${esc(c.func_name)}${c.return_line ? `<span class="ln">ret:${c.return_line}</span>` : ""}</span>`)
        .join("")
    : '<span class="muted">（空栈）</span>';
  // 调用树高亮（树结构采集后重建一次，此处只挪高亮节点）
  renderCallTree(stepData.tree, stepData.frameNode[stepIdx]); // 传根节点（stepData.tree=buildCallTree().root）
  updateNodeCard(f); // 常驻信息卡跟随当前帧
  renderArrayViz(f); // 数组柱状图（有数组变量才显示）
}

// 常驻信息卡：跟随当前帧刷新（事件/位置/步数/局部变量/代码预览——手机可达，
// 不依赖悬停；教学化文案，is_local 过滤后仍不裸 dump 内部数据）
function updateNodeCard(f) {
  const el = document.getElementById("node-card");
  if (!el) return;
  const vars = (f.local_vars || []).filter((v) => v.is_local);
  // 代码预览：当前执行行 ±2 行——用户不必左右扫视编辑器
  const NL = String.fromCharCode(10); // heredoc 吃 \n 转义，运行时构造
  const srcLines = ($("editor").value || "").split(NL);
  const cl = Math.max(1, f.code_line || 1);
  const from = Math.max(0, cl - 3), to = Math.min(srcLines.length, cl + 2);
  let codeHtml = "";
  for (let i = from; i < to; i++) {
    codeHtml += `<div class="nc-code${i + 1 === cl ? " on" : ""}"><span class="n">${i + 1}</span>${esc(srcLines[i] || "")}</div>`;
  }
  el.innerHTML =
    `<div class="nc-head" title="点击收纳/展开"><span>执行信息</span><span class="nc-fold">▾</span></div>` +
    `<div class="nc-body">` +
    `<p class="nc-ev">${esc(f.semantic_label || "执行")}</p>` +
    `<p class="nc-fn">${esc(f.func_name || "—")} · 第 ${f.code_line} 行</p>` +
    `<p class="nc-step">第 ${f.step_index} 步</p>` +
    (vars.length
      ? vars.map((v) => `<p class="nc-var">${esc(v.name)} = ${esc(v.value)}</p>`).join("")
      : `<p class="nc-var muted">（此帧无局部变量）</p>`) +
    `<div class="nc-codebox">${codeHtml}</div>` +
    `</div>`;
  applyCardFold(el); // 折叠态跨帧保持（dataset 在常驻容器上）
}

// 收纳开关：点击卡头折叠/展开（boot 时对常驻容器绑一次，事件委托）
export function applyCardFold(el) {
  const folded = el.dataset.folded === "1";
  const body = el.querySelector(".nc-body");
  const mark = el.querySelector(".nc-fold");
  if (body) body.style.display = folded ? "none" : "";
  if (mark) mark.textContent = folded ? "▸" : "▾";
}

// 数组可视化：local_vars 里 ty_name=int[N] 且 value={…} 的变量 → 柱状图。
// step 流是逐 VM 指令推进，交换类操作会出现「半完成」中间态（如 a[j]=a[j+1]
// 已写、a[j+1]=t 未写）——这是指令级真实执行状态，是白箱教学的卖点而非 bug。
function renderArrayViz(f) {
  const host = document.getElementById("array-viz");
  if (!host) return;
  const arrays = (f.local_vars || []).filter((v) => {
    if (!/^[A-Za-z_]\w*\[\d+\]$/.test(v.ty_name || "")) return false;
    const m = String(v.value).match(/^\{([-,\d\s]*)\}$/);
    if (!m) return false;
    const nums = m[1].split(",").map((x) => parseInt(x.trim(), 10));
    return nums.length >= 2 && nums.length <= 32 && nums.every((n) => !isNaN(n));
  });
  const head = document.getElementById("array-viz-head");
  if (!arrays.length) {
    host.style.display = "none";
    if (head) head.style.display = "none"; // 审阅 P3-1：标题与教学说明随区显隐（曾写死 none 无人解锁）
    return;
  }
  host.style.display = "";
  if (head) head.style.display = "";
  // div 柱而非 SVG：preserveAspectRatio="none" 的非等比拉伸会把柱下数字压扁
  host.innerHTML = arrays
    .map((v) => {
      const nums = String(v.value).match(/^\{([-,\d\s]*)\}$/)[1].split(",").map((x) => parseInt(x.trim(), 10));
      const max = Math.max(...nums.map((n) => Math.abs(n)), 1);
      const cols = nums
        .map((n) =>
          `<div class="av-col"><div class="av-bar" style="height:${((Math.abs(n) / max) * 100).toFixed(1)}%"></div><div class="av-num">${n}</div></div>`
        )
        .join("");
      return `<div class="av-item"><div class="av-name">${esc(v.name)} · ${esc(v.ty_name)}</div><div class="av-chart">${cols}</div></div>`;
    })
    .join("");
}

function stepStopTimer() {
  if (stepTimer) {
    clearInterval(stepTimer);
    stepTimer = 0;
  }
  $("anim-play").textContent = "▶ 采集并回放";
}

function stepPlay() {
  if (!stepData || !stepData.frames.length) return;
  stepStopTimer();
  if (stepIdx >= stepData.frames.length - 1) stepGoto(0);
  $("anim-play").textContent = "⏸ 暂停";
  stepTimer = setInterval(() => {
    if (stepIdx >= stepData.frames.length - 1) {
      stepStopTimer();
      return;
    }
    stepGoto(stepIdx + 1);
  }, Number(speedValue()) || 200);
}

async function stepRecollect() {
  // 采集源恒为当前编辑器内容（无场景概念——左栏用例选择即场景入口）
  stepStopTimer();
  treeView.k = 0; // 新采集：视图按小树/大树规则重新初始化
  stepData = null;
  stepIdx = 0;
  $("step-vars").innerHTML = "";
  $("step-stack").textContent = "—";
  $("anim-phase").textContent = "采集中：step.begin + step.next 推进引擎…";
  $("anim-play").disabled = true;
  $("anim-play").textContent = "… 采集中";
  await new Promise((r) => setTimeout(r)); // 让按钮态先渲染
  stepData = await stepCollect();
  if (stepData.error) {
    $("anim-phase").textContent = "采集失败：" + stepData.error;
    $("anim-play").disabled = false;
    $("anim-play").textContent = "▶ 采集并回放";
    return;
  }
  const built = buildCallTree(stepData.frames);
  stepData.tree = built.root;
  stepData.frameNode = built.frameNode;
  $("anim-seek").max = stepData.frames.length - 1;
  $("anim-play").disabled = false;
  stepGoto(0);
  stepPlay(); // 采集完自动播放
}

export function bindAnim() {
  setSpeedDropdown(makeDropdown(
    "anim-speed",
    [ { v: "400", label: "0.5×" }, { v: "200", label: "1×" }, { v: "100", label: "2×" } ],
    "200",
    () => { if (stepTimer) stepPlay(); } // 播放中调速 = 重启节奏
  ));
  $("anim-play").onclick = () => {
    if (!stepData) { stepRecollect(); return; }
    stepTimer ? stepStopTimer() : stepPlay();
  };
  $("anim-prev").onclick = () => { stepStopTimer(); stepGoto(stepIdx - 1); };
  $("anim-next").onclick = () => { stepStopTimer(); stepGoto(stepIdx + 1); };
  // 重新采集 = 用当前编辑器内容重跑 step 流（回到帧 0 用进度条拖动即可）
  $("anim-reset").onclick = () => stepRecollect();
  $("anim-seek").oninput = (e) => {
    stepStopTimer();
    stepGoto(Number(e.target.value));
  };
}


// ── 用例切换 ─────────────────────────────────────────────
export function stepReset() {
  // 编辑器内容变化后旧采集过期：回放区回到待采集态
  stepStopTimer();
  treeView.k = 0;
  stepData = null;
  stepIdx = 0;
  $("step-tree").innerHTML =
    '<span class="muted">（采集后展示）</span>' +
    '<div id="node-card" class="node-card"><p class="nc-ev muted">（采集后展示当前事件）</p></div>'; // 常驻卡随容器重建一起恢复
  $("step-vars").innerHTML = "";
  $("step-stack").textContent = "—";
  $("anim-seek").max = 0;
  $("anim-progress").textContent = "";
  $("anim-phase").textContent = "（采集后展示执行过程——数据来自引擎 step 流）";
  $("anim-play").disabled = false;
  $("anim-play").textContent = "▶ 采集并回放";
}

