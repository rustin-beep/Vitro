// Vitro demo · 运行链（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。TS 重写批：签名类型化。）
"use strict";

import { decorateBadges } from "./icon.ts";
import { invoke, bodyOf, gateway, hasGateway } from "./gw.ts";
import { $, esc, setStatus, latin1ToUtf8 } from "./util.ts";
import { renderMemory } from "./memory.ts";
import { currentCaseId } from "./state.ts";
import { workspaceActive, workspaceFilesForCompile } from "./workspace.ts";
import type { Frame } from "./types.ts";
import type { CompileResult, Diagnostic, RunResult, EngineConfig, OutputDelta, MemoryRegions } from "./types.ts";

/** waiting_input 时保留的会话上下文（input.feed 续跑用——完整响应帧）。 */
let pendingRun: Frame | null = null;

export function getPendingRun(): Frame | null { return pendingRun; }
export function resetPendingRun(): void { pendingRun = null; }

export function bindTabs(): void {
  document.querySelectorAll<HTMLElement>(".tabs .tab").forEach((btn) => {
    btn.onclick = () => {
      document.querySelectorAll(".tabs .tab").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      document.querySelectorAll(".tabpage").forEach((p) => p.classList.add("hidden"));
      $("tab-" + btn.dataset.tab).classList.remove("hidden");
    };
  });
}

// ── 会话配置 ─────────────────────────────────────────────
export function applyConfig(): Record<string, any> {
  if (!hasGateway()) return;
  const params = {
    deterministic: ($("cfg-det") as HTMLInputElement).checked,
    max_steps: Number(($("cfg-maxsteps") as HTMLInputElement).value) || 10000000,
    call_depth_limit: Number(($("cfg-depth") as HTMLInputElement).value) || 10000,
  };
  const r = bodyOf(invoke({ method: "config.set", params }));
  const c = bodyOf<EngineConfig>(invoke({ method: "config.get" }));
  $("cfg-msg").textContent = `已应用 ✓（deterministic=${c.deterministic}，max_steps=${c.max_steps}，call_depth=${c.call_depth_limit}）`;
  renderCfgView(c);
  return r;
}

export function renderCfgView(c: unknown): void {
  if (c) $("cfg-view").textContent = JSON.stringify(c, null, 2);
}

// ── 运行一条用例 ──────────────────────────────────────────
export async function runCase(): Promise<void> {
  if (!hasGateway()) return;
  const kase = (DEMO_CASES.find((k) => k.id === currentCaseId()) || {}) as DemoCase;
  $("run-btn").setAttribute("disabled", "true");
  setStatus("busy", "运行中…");
  try {
    gateway().reset();
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
      params: buildBaseConfig(),
    }));
    if (kase.configHint) {
      bodyOf(invoke({ method: "config.set", params: kase.configHint }));
      // 不回写输入框——输入框是「基准」的 UI 真相，回写会污染下一个
      // 用例的恢复基准（2026-09-30 粘滞回归实测抓到）；仅文本提示。
      $("cfg-msg").textContent = `本用例临时覆盖 config：max_steps=${kase.configHint.max_steps}（下一用例自动恢复基准）`;
    }
    // compile：用例可带 files（多编译单元）或单 source；编辑器内容跟随主文件
    let comp: CompileResult;
    const cp = buildCompileParams(kase);
    if (cp.files) {
      comp = bodyOf<CompileResult>(invoke({ method: "compile", params: { files: cp.files } }));
    } else {
      comp = bodyOf<CompileResult>(invoke({ method: "compile", params: { source: cp.source } }));
    }
    renderDiagnostics(comp.diagnostics || []);
    renderPpTrace(comp.preprocessor_trace || []);
    if (!comp.ok) {
      setStatus("err", "编译失败");
      renderTrap("编译失败——诊断见左侧列表");
      return;
    }
    const run = invoke({ method: "run", params: runParams(kase) });
    const rr = bodyOf<RunResult>(run);
    if (rr.waiting_input) {
      pendingRun = run;
      // 挂起提示强化（#28 10-07 登记②：用户曾误报「无法运行」——
      // 状态文案点明输入位置 + stdin 框聚焦 + accent 高亮三管齐下）
      setStatus("wait", "等待输入 —— 在下方 stdin 框输入后点「喂入」继续");
      // 显示 stdin 行：HTML 初始带 .hidden（display:none !important），
      // 必须显式移除（历史上这里操作的是无消费者的 .active 类，行永不出现）
      $("stdin-row").classList.remove("hidden");
      $("stdin-row").classList.add("need-input");
      const box = $("stdin-box") as HTMLTextAreaElement;
      box.focus();
      renderRunResult(rr);
      renderMemory(bodyOf<MemoryRegions>(invoke({ method: "memory.regions" })));
      // scanf 暂停前的 printf 输出已在通道里（如提示语 "n="）——即时拉取显示，
      // 否则要等喂入续跑后才见（2026-10-03 用户问交互时实测发现的显示缺口）
      const o = bodyOf<OutputDelta>(invoke({ method: "output.delta", params: { cursor: 0, stream: "stdout" } }));
      renderOutput(latin1ToUtf8(o.delta) || "", o.total || 0);
      return;
    }
    pendingRun = null;
    finishRun(rr, kase);
  } finally {
    $("run-btn").removeAttribute("disabled");
  }
}

export async function feedStdin(): Promise<void> {
  if (!pendingRun) return;
  const text = ($("stdin-box") as HTMLTextAreaElement).value;
  const feed = invoke({ method: "input.feed", params: { text: text + "\n" } });
  const rr = bodyOf<RunResult>(feed);
  if (rr.waiting_input) {
    setStatus("wait", "仍在等待输入…");
    return;
  }
  pendingRun = null;
  $("stdin-row").classList.add("hidden");
  $("stdin-row").classList.remove("need-input");
  const kase = (DEMO_CASES.find((k) => k.id === currentCaseId()) || {}) as DemoCase;
  finishRun(rr, kase);
}

// run 参数面：argv 输入框（空格分隔）或用例声明；stdin 两步交互保留
// （waiting_input 本身是教学演示点）
function runParams(kase: DemoCase): { argv?: string[] } {
  const p: { argv?: string[] } = {};
  const argvText = ($("argv-box") as HTMLInputElement).value.trim();
  if (argvText) p.argv = argvText.split(/\s+/);
  else if (kase.argv) p.argv = kase.argv;
  return p;
}

// ── 参数构造单一源（2026-10-04 审阅 P2：点课采集通道与运行按钮通道口径
// 分裂——multi_file/argv_prog 在采集通道直接失败的实锤。三构造导出，
// runCase 与 timetravel.stepCollect 共同消费；改一处两条通道同改）──

export function buildCompileParams(kase: DemoCase): { files?: Array<{ filename: string; source: string }>; source?: string } {
  // 工作区模式（打开本地文件夹批 2026-10-05）：全量 .c/.h 打包
  // compile.files，编辑器内容 = active 文件——两条通道（运行/采集）经
  // 本单一源自动同口径；golden 对照在 renderReference 的 kase 空形态下
  // 自然落「未预置参考值」（诚实边界沿用）
  if (workspaceActive()) return { files: workspaceFilesForCompile() };
  if (kase.files) {
    // 多编译单元：主文件跟随编辑器内容（与运行通道同语义）
    return { files: kase.files.map((f, i) => ({
      filename: f.filename,
      source: i === 0 ? ($("editor") as HTMLTextAreaElement).value : f.source,
    })) };
  }
  return { source: ($("editor") as HTMLTextAreaElement).value };
}

export function buildRunParams(kase: DemoCase): { argv?: string[] } {
  return runParams(kase);
}

export function buildBaseConfig(): { max_steps: number; call_depth_limit: number; deterministic: boolean; quarantine_budget: number } {
  return {
    max_steps: Number(($("cfg-maxsteps") as HTMLInputElement).value) || 10000000,
    call_depth_limit: Number(($("cfg-depth") as HTMLInputElement).value) || 10000,
    deterministic: ($("cfg-det") as HTMLInputElement).checked,
    quarantine_budget: Number(($("cfg-quar") as HTMLInputElement).value) || 262144,
  };
}

function finishRun(rr: RunResult, kase: DemoCase): void {
  renderRunResult(rr);
  // 四通道视图：stdout / stderr / note（display=全通道按写入序拼接，页内
  // 用分通道展示替代）。分域解码（对齐 gateway serve_io 的 delta 通道语义，
  // #49 批一 note mojibake 修复的连坐——批一改引擎侧时漏了本消费方，note
  // 中文在 demo 全部 mojibake 的回归由本批收口）：
  // - stdout/stderr = C 程序字节流（Latin-1 逐字节折回）→ latin1ToUtf8 还原；
  // - note = 引擎文本域（gateway 已解码回原文直传，真 UTF-8 字符串）→
  //   直接使用，过 latin1ToUtf8 会把 >0xFF 码点截低字节必乱码。
  const pull = (stream: string): { text: string; total: number } => {
    const o = bodyOf<OutputDelta>(invoke({ method: "output.delta", params: { cursor: 0, stream } }));
    const raw = o.delta || "";
    const text = stream === "note" ? raw : latin1ToUtf8(raw);
    return { text, total: o.total || 0 };
  };
  const stdout = pull("stdout");
  renderOutput(stdout.text, stdout.total);
  const stderr = pull("stderr");
  renderStderr(stderr.text, stderr.total);
  const note = pull("note");
  renderNote(note.text, note.total);
  renderMemory(bodyOf<MemoryRegions>(invoke({ method: "memory.regions" })));
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

function renderStderr(text: string, total: number): void {
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
function renderRunResult(r: RunResult): void {
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

function renderOutput(delta: string, total: number): void {
  const el = $("stdout-box");
  el.textContent = delta === "" ? "（无 stdout 输出）" : delta;
  el.classList.toggle("empty", delta === "");
  el.classList.remove("flash-in"); // F-1b②：重触发淡入
  void el.offsetWidth;
  el.classList.add("flash-in");
  $("stdout-meta").textContent = `${total} 字节 · output.delta 全量拉取`;
}

function renderDiagnostics(diags: Diagnostic[]): void {
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

function renderNote(text: string, total: number): void {
  const el = $("note-box");
  if (!text) {
    // 空态先清内容再隐藏——hidden 元素旧文本残留（#28 10-07 登记①）
    el.innerHTML = "";
    $("note-meta").textContent = "";
    el.classList.add("hidden");
    return;
  }
  el.classList.remove("hidden");
  el.innerHTML = decorateBadges(esc(text).replace(/\n/g, "<br>"));
  $("note-meta").textContent = `${total} 字节 · note 审计流（引擎文本域直传）`;
}
function renderPpTrace(trace: string[]): void {
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

function renderTrap(text: string): void {
  const el = $("trap-box");
  if (!text) {
    // 同 renderNote：空态清内容再隐藏（同款写法债连坐）
    el.innerHTML = "";
    el.classList.add("hidden");
    return;
  }
  el.classList.remove("hidden");
  el.innerHTML = decorateBadges(esc(text).replace(/\n/g, "<br>"));
}

// 参考对照（Clang golden 预置真值——诚实边界在文案）
function renderReference(runResult: RunResult, stdout: string, kase: DemoCase): void {
  const el = $("ref-box");
  if (!kase || (!kase.referenceOutput && !kase.referenceTrap)) {
    el.innerHTML = '<div class="muted">（本用例未预置参考值）</div>';
    return;
  }
  // 诚实边界：编辑器内容被修改后，golden 只属于原用例——不拿旧预期比新代码
  if (($("editor") as HTMLTextAreaElement).value !== kase.source) {
    el.innerHTML = '<div class="muted">（编辑器内容已修改——Clang golden 对照仅对未修改的预置用例有效；可切回用例或点「↻ 重新采集」前先比对）</div>';
    return;
  }
  let match: boolean, expect: string | undefined;
  if (kase.referenceKind === "stdout") {
    expect = kase.referenceOutput;
    match = stdout === expect;
    el.innerHTML =
      `<div class="${match ? "match" : "mismatch"}">${match ? "✓ 一致" : "✗ 不一致"}</div>` +
      `<pre class="ref-pre">Clang golden（预置真值）: ${esc(JSON.stringify(expect))}\nVitro 实跑 stdout      : ${esc(JSON.stringify(stdout))}</pre>`;
  } else {
    expect = kase.referenceTrap;
    match = (runResult.trap || "").includes(expect as string);
    el.innerHTML =
      `<div class="${match ? "match" : "mismatch"}">${match ? "✓ 诊断类别一致（含 " + esc(expect as string) + "）" : "✗ 未复现预期诊断"}</div>` +
      `<pre class="ref-pre">参考真值：CI 防线对该诊断类别的断言（由 wasm 宿主冒烟与 shadow 防线持续对拍）</pre>`;
  }
}
