// Vitro demo · 时间旅行回放（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。TS 重写批：签名类型化。）
//
// 帧数据源 = gateway step 族（step.begin / step.next 批量推进），每帧带
// 引擎真实标注（semantic_labels 词表渲染文本）/ 局部变量 / 调用栈 / 当前
// 执行行；seek 与 ◀▶ 为本地帧数组形态（gateway wasm 未接 step.seek /
// payload.get——那是 serve 通道能力，教学回放形态下本地索引足够，引擎级
// 断点留实时调试形态）。场景 = 全部预置用例；左侧编辑器随帧高亮当前行。
// （本段 2026-10-04 自 catalog.ts 尾部迁入——审阅 P3-⑤ 注释漂移：拆分时
// 段落归属错位。）
"use strict";

import { invoke, bodyOf, gateway } from "./gw.ts";
import { $, esc, makeDropdown } from "./util.ts";
import { scrollToLine } from "./editor.ts";
import { buildCallTree, renderCallTree, treeView } from "./calltree.ts";
import { buildCompileParams, buildRunParams, buildBaseConfig } from "./run.ts";
import type { TreeNode } from "./calltree.ts";
import { currentCaseId, setSpeedDropdown, speedValue, currentBreakpoints } from "./state.ts";
import type { StepPayload, StepNextResult, CompileResult } from "./types.ts";

const STEP_FRAME_CAP = 4000; // 上限防大程序把回放 DOM/内存拖爆（infinite 类用例 20000 步在此截断，回放提示截断）

/** 采集结果（stepCollect 返回；tree/frameNode 采集成功后由 stepRecollect 装配）。 */
interface StepData {
  frames: StepPayload[];
  marks: { idx: number; text: string }[];
  stopped: string;
  error?: string;
  tree?: TreeNode;
  frameNode?: (TreeNode | null)[];
}

let stepData: StepData | null = null; // { frames, marks, stopped }
let stepIdx = 0;
let stepTimer: number = 0; // setInterval 句柄（0 = 无）

async function stepCollect(): Promise<StepData> {
  const kase = (DEMO_CASES.find((k) => k.id === currentCaseId()) || {}) as DemoCase;
  gateway().reset();
  bodyOf(invoke({ method: "session.create" }));
  // 参数构造单一源（2026-10-04 审阅 P2）：与「运行」按钮通道同构——
  // 此前只走 compile{source}+run{}，multi_file（files）与 argv_prog（argv）
  // 两课点课采集直接失败的实锤；config = UI 基准 + 用例 configHint 覆盖
  bodyOf(invoke({
    method: "config.set",
    params: Object.assign(buildBaseConfig(), kase.configHint || {}),
  }));
  const cp = buildCompileParams(kase);
  const comp = bodyOf<CompileResult>(invoke({
    method: "compile",
    params: cp.files ? { files: cp.files } : { source: cp.source },
  }));
  if (!comp.ok) return { error: "编译失败——先解决左侧诊断", frames: [], marks: [], stopped: "" };
  // run 先行（2026-10-04，refs #28：Rust golden 提取序照搬 compile→run→
  // step.begin→step.next）——run 建立会话运行态并把 compile 期的算法检测
  // matches 注入引擎；缺此步则帧的 algorithm_step/vis_events 恒空
  //（smoke 抽验带 run 所以绿、本通道此前无标注用例路径未暴露）
  const rp = buildRunParams(kase);
  bodyOf(invoke({ method: "run", params: rp.argv ? { argv: rp.argv } : {} }));
  bodyOf(invoke({ method: "step.begin", params: {} }));
  // 断点下发（2026-10-04，refs #28：编辑器行号点击标记——先清后设语义，
  // step.next 推进到断点行的批次暂停并带 paused 字段）。**须在 step.begin
  // 之后**：begin 重建 vm（#29 #5 语义），重建前设置的断点会被清掉。
  const bpLines = currentBreakpoints();
  if (bpLines.length) {
    bodyOf(invoke({ method: "breakpoints.set", params: { lines: bpLines } }));
  }
  const frames: StepPayload[] = [];
  let stopped = "";
  let batch: StepNextResult;
  do {
    batch = bodyOf<StepNextResult>(invoke({ method: "step.next", params: {} }));
    if (batch.payloads) frames.push(...batch.payloads);
    if (batch.waiting_input) { stopped = "程序等待输入（scanf）——回放到暂停点为止"; break; }
    if (batch.paused) { stopped = "⏸ 已到断点（引擎暂停）——清除断点后 ↻ 重新采集可继续"; break; }
    if (batch.trapped) { stopped = "受检终止：" + String(batch.trap_message || "").split("\n")[0]; break; }
  } while (!batch.finished && frames.length < STEP_FRAME_CAP);
  if (frames.length >= STEP_FRAME_CAP) stopped = stopped || `帧数超 ${STEP_FRAME_CAP} 上限，回放截断`;
  // 事件轴：semantic_label + 行号组合的变化点（教学事件序列）
  const marks: { idx: number; text: string }[] = [];
  let last: string | null = null;
  frames.forEach((f, i) => {
    const k = (f.semantic_label || "") + "@" + f.code_line;
    if (k !== last) {
      marks.push({ idx: i, text: `第 ${f.step_index} 步 · ${f.semantic_label || "执行"}` });
      last = k;
    }
  });
  return { frames, marks, stopped };
}

function stepGoto(i: number): void {
  if (!stepData) return;
  stepIdx = Math.max(0, Math.min(i, stepData.frames.length - 1));
  // 帧推进（seek/单步/播放）= 镜头回到当前事件重心——手动平移只在不动帧时保持
  treeView.follow = true;
  stepRender();
}

// vis_events 行标记（2026-10-04，refs #28）：帧的可视化事件行在编辑器装饰层
// 左缘加竖条（.cl.vis-on——叠加类不动 highlightLines 行渲染管线）。
// ty 含义见 protocol（1=比较 等）——首版不分类全同色，分类呈现随 #28 迭代。
function markVisEventLines(f: StepPayload): void {
  const rows = document.querySelectorAll<HTMLElement>("#editor-hl .cl");
  rows.forEach((r) => r.classList.remove("vis-on"));
  for (const ev of f.vis_events || []) {
    const row = rows[ev.line - 1];
    if (row) row.classList.add("vis-on");
  }
}

function stepRender(): void {
  if (!stepData) return;
  const f = stepData.frames[stepIdx];
  $("anim-seek").setAttribute("value", String(stepIdx));
  $("anim-progress").textContent =
    `帧 ${stepIdx + 1}/${stepData.frames.length} · 第 ${f.step_index} 步` +
    (stepData.stopped ? " · " + stepData.stopped : "");
  const label = f.semantic_label || "执行";
  $("anim-phase").textContent = `【${label}】第 ${f.code_line} 行` + (f.func_name ? ` · ${f.func_name}` : "");
  scrollToLine(f.code_line, false); // 播放中只滚动+描边当前行，不闪烁
  markVisEventLines(f); // vis_events 行（编辑器左缘 accent 标记——常显至下帧）
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
  renderCallTree(stepData.tree as TreeNode, (stepData.frameNode as (TreeNode | null)[])[stepIdx]); // 传根节点（stepData.tree=buildCallTree().root）
  updateNodeCard(f); // 常驻信息卡跟随当前帧
  renderArrayViz(f); // 数组柱状图（有数组变量才显示）
}

// 常驻信息卡：跟随当前帧刷新（事件/位置/步数/局部变量/代码预览——手机可达，
// 不依赖悬停；教学化文案，is_local 过滤后仍不裸 dump 内部数据）
function updateNodeCard(f: StepPayload): void {
  const el = document.getElementById("node-card");
  if (!el) return;
  const vars = (f.local_vars || []).filter((v) => v.is_local);
  // 代码预览：当前执行行 ±2 行——用户不必左右扫视编辑器
  const NL = String.fromCharCode(10); // heredoc 吃 \n 转义，运行时构造
  const srcLines = (($("editor") as HTMLTextAreaElement).value || "").split(NL);
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
    (f.algorithm_step
      ? `<p class="nc-algo">🧭 ${esc(f.algorithm_step.display_name || f.algorithm_step.algorithm_name)} · ${esc(f.algorithm_step.phase)}<br><span class="nc-algo-desc">${esc(f.algorithm_step.description)}</span></p>`
      : "") +
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
export function applyCardFold(el: HTMLElement): void {
  const folded = el.dataset.folded === "1";
  const body = el.querySelector(".nc-body") as HTMLElement | null;
  const mark = el.querySelector(".nc-fold") as HTMLElement | null;
  if (body) body.style.display = folded ? "none" : "";
  if (mark) mark.textContent = folded ? "▸" : "▾";
}

// 数组可视化：local_vars 里 ty_name=int[N] 且 value={…} 的变量 → 柱状图。
// step 流是逐 VM 指令推进，交换类操作会出现「半完成」中间态（如 a[j]=a[j+1]
// 已写、a[j+1]=t 未写）——这是指令级真实执行状态，是白箱教学的卖点而非 bug。
function renderArrayViz(f: StepPayload): void {
  const host = document.getElementById("array-viz") as HTMLElement;
  if (!host) return;
  const arrays = (f.local_vars || []).filter((v) => {
    if (!/^[A-Za-z_]\w*\[\d+\]$/.test(v.ty_name || "")) return false;
    const m = String(v.value).match(/^\{([-,\d\s]*)\}$/);
    if (!m) return false;
    const nums = m[1].split(",").map((x) => parseInt(x.trim(), 10));
    return nums.length >= 2 && nums.length <= 32 && nums.every((n) => !isNaN(n));
  });
  const head = document.getElementById("array-viz-head") as HTMLElement | null;
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
      const nums = (String(v.value).match(/^\{([-,\d\s]*)\}$/) as RegExpMatchArray)[1].split(",").map((x) => parseInt(x.trim(), 10));
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

function stepStopTimer(): void {
  if (stepTimer) {
    clearInterval(stepTimer);
    stepTimer = 0;
  }
  $("anim-play").textContent = "▶ 采集并回放";
}

function stepPlay(): void {
  if (!stepData || !stepData.frames.length) return;
  stepStopTimer();
  if (stepIdx >= stepData.frames.length - 1) stepGoto(0);
  $("anim-play").textContent = "⏸ 暂停";
  stepTimer = window.setInterval(() => {
    if (stepIdx >= stepData.frames.length - 1) {
      stepStopTimer();
      return;
    }
    stepGoto(stepIdx + 1);
  }, Number(speedValue()) || 200);
}

async function stepRecollect(): Promise<void> {
  // 采集源恒为当前编辑器内容（无场景概念——左栏用例选择即场景入口）
  stepStopTimer();
  treeView.k = 0; // 新采集：视图按小树/大树规则重新初始化
  stepData = null;
  stepIdx = 0;
  $("step-vars").innerHTML = "";
  $("step-stack").textContent = "—";
  $("anim-phase").textContent = "采集中：step.begin + step.next 推进引擎…";
  $("anim-play").setAttribute("disabled", "true");
  $("anim-play").textContent = "… 采集中";
  // 采集互斥（#28 评论区待办①）：采集是异步长任务，中途「运行」会 reset
  // 会话打断采集（并发状态错乱）——运行/喂入按钮同步禁用，采集结束恢复
  $("run-btn").setAttribute("disabled", "true");
  $("feed-btn").setAttribute("disabled", "true");
  await new Promise((r) => setTimeout(r)); // 让按钮态先渲染
  stepData = await stepCollect();
  $("run-btn").removeAttribute("disabled");
  $("feed-btn").removeAttribute("disabled");
  if (stepData.error) {
    $("anim-phase").textContent = "采集失败：" + stepData.error;
    $("anim-play").removeAttribute("disabled");
    $("anim-play").textContent = "▶ 采集并回放";
    return;
  }
  const built = buildCallTree(stepData.frames);
  stepData.tree = built.root;
  stepData.frameNode = built.frameNode;
  ($("anim-seek") as HTMLInputElement).max = String(stepData.frames.length - 1);
  $("anim-play").removeAttribute("disabled");
  stepGoto(0);
  stepPlay(); // 采集完自动播放
}

// 算法侧栏入口（2026-10-04，refs #28）：algo 卡片载入示例后自动采集——
// 与 anim-reset 同源（编辑器当前内容采集），导出供跨模块调用
export function collectCurrentEditor(): void {
  void stepRecollect();
}

// ── 引擎级跳转（2026-10-04，refs #28：gateway step.seek 消费）────────
// 与本地拖条的分工：本地 seek = 已采集缓存内的回放（含树高亮/进度）；
// 引擎跳转 = 引擎权威帧——超出本地采集范围（4000 帧截断外）仍可取帧。
// 命中本地缓存时回落本地渲染（全兼容），超界走最小渲染面。
export function engineSeek(step: number): void {
  if (!hasGatewaySafe()) return;
  stepStopTimer();
  const r = bodyOf<{ success: boolean; payload: StepPayload }>(
    invoke({ method: "seek", params: { step } })
  );
  if (!r || !r.success || !r.payload) {
    $("anim-progress").textContent = `引擎跳转 step ${step} 失败（越界或未采集）`;
    return;
  }
  const f = r.payload;
  const localIdx = stepData ? stepData.frames.findIndex((x) => x.step_index === f.step_index) : -1;
  if (localIdx >= 0) { stepGoto(localIdx); return; } // 本地缓存命中：全兼容渲染
  renderEngineFrame(f);
}

// 超采集范围的引擎帧：最小渲染面（phase/变量表/调用栈/信息卡/vis 行——
// 树高亮依赖本地 frameNode 索引，引擎帧跳过）
function renderEngineFrame(f: StepPayload): void {
  $("anim-phase").textContent = `【${f.semantic_label || "执行"}】第 ${f.code_line} 行（引擎帧 · step ${f.step_index}）`;
  $("anim-progress").textContent = `引擎帧 step ${f.step_index}（超出本地采集范围）`;
  const vars = f.local_vars || [];
  $("step-vars").innerHTML = vars.length
    ? "<tr><th>名称</th><th>类型</th><th>值</th><th>地址</th></tr>" +
      vars.map((v) => `<tr><td>${esc(v.name)}</td><td>${esc(v.ty_name)}</td><td>${esc(v.value)}</td><td>0x${(v.addr || 0).toString(16)}</td></tr>`).join("")
    : '<tr><td class="muted">（此帧无局部变量）</td></tr>';
  const stack = f.call_stack || [];
  $("step-stack").innerHTML = stack.length
    ? stack.map((c) => `<span class="frm">${esc(c.func_name)}</span>`).join('<span class="arrow">→</span>')
    : '<span class="muted">（空栈）</span>';
  markVisEventLines(f);
  updateNodeCard(f);
  renderArrayViz(f);
  scrollToLine(f.code_line, false);
}

function hasGatewaySafe(): boolean {
  try { gateway(); return true; } catch { return false; }
}

export function bindAnim(): void {
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
  $("anim-seek").oninput = (e: Event) => {
    stepStopTimer();
    stepGoto(Number((e.target as HTMLInputElement).value));
  };
  // 引擎级跳转（step.seek 消费——引擎权威帧，超出本地采集范围可用）
  $("eng-seek-btn").onclick = () => {
    const n = Number(($("eng-seek-num") as HTMLInputElement).value);
    if (Number.isFinite(n) && n >= 0) engineSeek(n);
  };
}


// ── 用例切换 ─────────────────────────────────────────────
export function stepReset(): void {
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
  ($("anim-seek") as HTMLInputElement).max = "0";
  $("anim-progress").textContent = "";
  $("anim-phase").textContent = "（采集后展示执行过程——数据来自引擎 step 流）";
  $("anim-play").removeAttribute("disabled");
  $("anim-play").textContent = "▶ 采集并回放";
}
