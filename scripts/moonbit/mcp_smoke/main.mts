// mcp_smoke —— cmd/mcp_js 产物 stdio 冒烟闸（DSH mbt 化批 CI 接线，2026-11-03）。
// 驱动 moon build --release --target js 的单文件产物：协议契约（initialize/
// listChanged）+ 渐进披露（L0 5 → session_open → list_changed → L1 12 → 收回）+
// readOnlyHint + 池语义（run_to 事件停/终局回看）+ 投影（默认 {i,l,f,s} 分页
// + fields/filter）+ render 落盘（301 帧 HTML）+ 产物 script 语法门与 PLAYER
// 驱动对拍（#468/#469 防回归，2026-11-04）+ interactive 无 wasm 回落
// static（CI 无 wasm 资产——恰测回落路径；真 interactive 归本地 accept.mts）。
// 锚值与 mcp_wbtest/accept 同源（bubble.c：1126 步 / swap 7 / 首交换帧 93 行 8
// / stdout "1 2 3 5 8 9 \n" / budget 300 → 301 帧）——引擎行为变更连坐红。
// 用法：node scripts/moonbit/mcp_smoke/main.mts（前置：moon build --release
// --target js cmd/mcp_js；产物路径可用 VITRO_MCP_JS 覆盖，缺产物 fail loud）。
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import vm from "node:vm";

/// bubble.c（v1 samples 逐字同源——锚值依据，改语料须连坐锚）。
const BUBBLE_C = `#include <stdio.h>

void bubble_sort(int arr[], int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - 1 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                int tmp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
        }
    }
}

int main(void) {
    int arr[6] = {5, 2, 8, 1, 9, 3};
    bubble_sort(arr, 6);
    for (int i = 0; i < 6; i++) printf("%d ", arr[i]);
    printf("\\n");
    return 0;
}
`;

/// bubble_sort.c（corpus/baseline/bubble_sort.c 逐字同源——数组真名 a ≠
/// 字幕展示名 arr，#469 分叉面锚：swap 高亮靠 vis_events context 归属）。
const BUBBLE_SORT_A = `// @category: baseline
int main() { int a[5] = {5,3,4,1,2}; for (int i = 0; i < 4; i++) for (int j = 0; j < 4-i; j++) if (a[j] > a[j+1]) { int t = a[j]; a[j] = a[j+1]; a[j+1] = t; } printf("%d", a[0]); return 0; }
`;

/// fourier 真课 viz 块的探针程序：数组名与课源一致（re/im/mag），数值不是
/// DFT 语义——只验「真课声明 → 引擎解析 → doc.series_decl/focus」链路（P3-6）。
const VIZ_PROBE_C = `#include <stdio.h>

int main(void) {
  double re[4] = {1.0, 0.0, -1.0, 0.0};
  double im[4] = {0.0, 1.0, 0.0, -1.0};
  double mag[4] = {1.0, 1.0, 1.0, 1.0};
  printf("%.1f\\n", re[0] + im[1] + mag[2]);
  return 0;
}
`;

/** 行缓冲累积器：feed 返回本次成行的完整帧（不带换行）；残行留存。 */
export function makeLineAcc(): { feed(chunk: string): string[] } {
  let buf = "";
  return {
    feed(chunk: string): string[] {
      buf += chunk;
      const out: string[] = [];
      let i = buf.indexOf("\n");
      while (i >= 0) {
        const line = buf.slice(0, i).trim();
        if (line.length > 0) out.push(line);
        buf = buf.slice(i + 1);
        i = buf.indexOf("\n");
      }
      return out;
    },
  };
}

/** 工具返回体提取：{isError, text}；畸形 content fail loud（throw）。 */
export function toolTextOf(frame: unknown): { isError: boolean; text: string } {
  const r = (frame as { result?: { content?: Array<{ text?: string }>; isError?: boolean } }).result;
  if (r === undefined || !Array.isArray(r.content) || r.content.length === 0 || r.content[0]?.text === undefined) {
    throw new Error(`toolTextOf: 畸形 tools/call 结果——${JSON.stringify(frame).slice(0, 160)}`);
  }
  return { isError: r.isError === true, text: r.content[0].text };
}

/** 断言账本（纯计数与清单；judgment 由调用方驱动）。 */
export class CheckRun {
  readonly failures: string[] = [];
  #n = 0;
  get total(): number { return this.#n; }
  check(name: string, ok: boolean, detail = ""): void {
    this.#n += 1;
    if (!ok) this.failures.push(detail === "" ? name : `${name} — ${detail}`);
  }
}

interface Frame { id?: number | null; method?: string; result?: unknown; error?: { code: number } }

/** 产物 HTML 的 <script> 段提取（#468 语法门取段器）：无段 fail loud。 */
export function extractScript(html: string): string {
  const m = /<script>([\s\S]*?)<\/script>/.exec(html);
  if (m === null || m[1] === undefined) throw new Error("extractScript: 产物无 <script> 段");
  return m[1];
}

interface StubEl {
  id: string;
  innerHTML: string;
  textContent: string;
  value: string;
  max: string;
  disabled: boolean;
  dataset: Record<string, string>;
  classList: { add(): void; remove(): void; contains(): boolean };
  onclick: (() => void) | null;
  oninput: ((this: StubEl) => void) | null;
  onchange: (() => void) | null;
  scrollIntoView(): void;
}

function makeEl(id: string): StubEl {
  return {
    id, innerHTML: "", textContent: "", value: "0", max: "0", disabled: false,
    dataset: {},
    classList: { add() {}, remove() {}, contains: () => false },
    onclick: null, oninput: null, onchange: null,
    scrollIntoView() {},
  };
}

/** 产物 script 驱动（#468 语法门 + #469 swap 对拍）：stub DOM 里跑完整
 * PLAYER（init 自然执行），再逐帧拨 slider 复算每帧 stage.innerHTML，统计
 * 含 swap 类名的帧数。首个 new vm.Script 即语法门——#468 形态（模板字面量
 * 转义丢失的裸换行/退化正则）在编译期 throw，不再依赖「生成成功+帧数正确」
 * 的盲验收。只 stub static 路径 PLAYER 触碰的宿主面（interactive 分支不达）。
 * TimelinePlan 批一（#470）：额外返回 __VITRO__ 数据与逐帧探针（swap/changed
 * 类名计数 + 字幕 innerHTML）——plan 路径等价对拍与 smoke 扩断言共用。 */
export interface FrameProbe {
  swap: number;
  changed: number;
  cap: string;
}

export interface DriveResult {
  swapFrames: number;
  total: number;
  data: unknown;
  probes: FrameProbe[];
}

export function driveScript(scriptText: string): DriveResult {
  const els = new Map<string, StubEl>();
  const stage = makeEl("stage");
  els.set("stage", stage);
  const cap = makeEl("cap");
  els.set("cap", cap);
  const slider = makeEl("slider");
  els.set("slider", slider);
  const documentStub = {
    getElementById: (id: string): StubEl => els.get(id) ?? makeEl(id),
    querySelector: (): null => null,
    documentElement: { dataset: {} as Record<string, string> },
    onkeydown: null as (() => void) | null,
  };
  const sandbox: Record<string, unknown> = {
    document: documentStub,
    location: { hash: "" },
    matchMedia: () => ({ matches: false }),
    setInterval: () => 0,
    clearInterval: () => {},
    setTimeout: () => 0,
    console,
  };
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(scriptText, sandbox); // 语法门：SyntaxError 在此 throw
  const total = Number(slider.max) + 1;
  const countCls = (html: string, cls: string): number => {
    let n = 0;
    for (let i = html.indexOf(`class="${cls}"`); i >= 0; i = html.indexOf(`class="${cls}"`, i + 1)) n += 1;
    return n;
  };
  let swapFrames = 0;
  const probes: FrameProbe[] = [];
  for (let k = 0; k < total; k++) {
    slider.value = String(k);
    if (slider.oninput !== null) slider.oninput.call(slider);
    const html = stage.innerHTML;
    const swap = countCls(html, "cell swap");
    const changed = countCls(html, "cell changed");
    if (swap > 0) swapFrames++;
    probes.push({ swap, changed, cap: cap.innerHTML });
  }
  return { swapFrames, total, data: sandbox.__VITRO__, probes };
}

/** render 产物探针（读盘 + 提段 + 驱动；异常折叠为 {ok:false,err}）。 */
function probeHtml(
  htmlPath: string,
): {
  ok: boolean;
  swapFrames: number;
  total: number;
  data?: unknown;
  probes?: FrameProbe[];
  err?: string;
} {
  try {
    const d = driveScript(extractScript(readFileSync(htmlPath, "utf8")));
    return { ok: true, swapFrames: d.swapFrames, total: d.total, data: d.data, probes: d.probes };
  } catch (e) {
    return { ok: false, swapFrames: -1, total: -1, err: e instanceof Error ? e.message : String(e) };
  }
}

/** 事件 context 是否点名该数组（旧壳层规则同款；等价对拍与 smoke 共用）。 */
export function contextMentionsArray(context: string, name: string): boolean {
  if (!name) return false;
  const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^\\w.])${esc}\\s*\\[`).test(context);
}

export interface TimelineSwap {
  name: string;
  i: number;
  j: number;
}
export interface TimelineCap {
  t: string;
  w: number;
  dur: number;
}
export interface TimelineStep {
  sw?: TimelineSwap;
  cap?: TimelineCap;
}
export interface MiniFrame {
  s?: string;
  /** vis_events 紧凑数组 [ty,line,e0,e1,e2,context]（context 是字符串）。 */
  e?: Array<Array<number | string>>;
  r?: Record<string, string[]>;
  a?: { p?: string; d?: string } | null;
  h?: { o?: string } | null;
}
export interface VitroData {
  frames?: MiniFrame[];
  focus?: string[];
  doc?: { timeline?: { pv?: number; steps?: TimelineStep[] } };
}

/** 帧内是否存在「可归属且有界」的 ty=2 交换事件（与 plan 生成器同判据）。 */
export function frameHasValidSwap(fr: MiniFrame): boolean {
  const names = Object.keys(fr.r ?? {});
  for (const e of fr.e ?? []) {
    if (e[0] !== 2) continue;
    const ctx = typeof e[5] === "string" ? e[5] : "";
    if (ctx === "") continue;
    const hits = names.filter((n) => contextMentionsArray(ctx, n));
    if (hits.length !== 1) continue;
    const name = hits[0];
    if (name === undefined) continue;
    const x = Number(e[2]);
    const y = Number(e[3]);
    if (!Number.isInteger(x) || !Number.isInteger(y)) continue;
    const lo = Math.min(x, y);
    const hi = Math.max(x, y);
    const len = (fr.r?.[name] ?? []).length;
    if (lo < 0 || lo === hi || hi >= len) continue;
    return true;
  }
  return false;
}

/** TimelinePlan v0.1 产物不变量（#470 批一）：
 *  steps 与 frames 零基同构 / sw 归属真名且事件帧全点亮 / cap.t 与字幕同源 /
 *  缺省键不产空串。返回错误清单（空 = 绿）与计数。 */
export function checkTimelinePlan(
  data: unknown,
  realName: string,
): { errors: string[]; swFrames: number; steps: number; frames: number } {
  const errors: string[] = [];
  const d = (data ?? {}) as VitroData;
  const frames = d.frames ?? [];
  const tl = d.doc?.timeline;
  const steps = tl?.steps;
  if (tl?.pv !== 1) errors.push(`doc.timeline.pv 非 1（${String(tl?.pv)}）`);
  if (!Array.isArray(steps)) {
    return { errors: [...errors, "doc.timeline.steps 缺失"], swFrames: 0, steps: 0, frames: frames.length };
  }
  if (steps.length !== frames.length) {
    errors.push(`steps=${steps.length} ≠ frames=${frames.length}（步骤错位）`);
  }
  let swFrames = 0;
  for (let k = 0; k < Math.min(steps.length, frames.length); k++) {
    const fr = frames[k] ?? {};
    const step = steps[k] ?? {};
    const hasEv = frameHasValidSwap(fr);
    // prod 帧的 r 已按 focus 过滤——归属真名不在本帧可见数组时不判「事件↔sw」
    // （v0.1 plan 可携带非聚焦数组意图；绘制面由宿主决定）。
    const visible = fr.r?.[realName] !== undefined;
    const sw = step.sw;
    if (sw !== undefined) {
      swFrames += 1;
      if (visible && !hasEv) errors.push(`帧 ${k}: sw 无源（无界内 ty=2 事件）`);
      if (sw.name !== realName) errors.push(`帧 ${k}: sw.name=${sw.name} ≠ ${realName}（归属真名）`);
      if (typeof sw.name !== "string" || sw.name === "") errors.push(`帧 ${k}: sw.name 空串`);
      if (!Number.isInteger(sw.i) || !Number.isInteger(sw.j) || sw.i < 0 || sw.i >= sw.j) {
        errors.push(`帧 ${k}: sw 下标非法 ${sw.i}/${sw.j}`);
      }
    } else if (visible && hasEv) {
      errors.push(`帧 ${k}: 界内交换事件未点亮 sw`);
    }
    const label = fr.s ?? "";
    const cap = step.cap;
    if (label === "") {
      if (cap !== undefined) errors.push(`帧 ${k}: 空标签仍产 cap（禁空串占位）`);
    } else if (cap === undefined) {
      errors.push(`帧 ${k}: 非空标签缺 cap`);
    } else {
      if (cap.t !== label) errors.push(`帧 ${k}: cap.t ≠ semantic_label`);
      if (cap.t === "") errors.push(`帧 ${k}: cap.t 空串`);
      if (!(typeof cap.w === "number" && cap.w >= 1)) errors.push(`帧 ${k}: cap.w 非法`);
      if (!(typeof cap.dur === "number" && cap.dur >= 0)) errors.push(`帧 ${k}: cap.dur 非法`);
    }
  }
  return { errors, swFrames, steps: steps.length, frames: frames.length };
}

async function drive(): Promise<number> {
  const product = process.env.VITRO_MCP_JS ?? "moonbit/_build/js/release/build/cmd/mcp_js/mcp_js.js";
  if (!existsSync(product)) {
    console.error(`mcp_smoke: 产物不存在 ${product}——前置 moon build --release --target js cmd/mcp_js`);
    return 2;
  }
  const outDir = mkdtempSync(path.join(tmpdir(), "mcp-smoke-"));
  const srv = spawn(process.execPath, [product], { stdio: ["pipe", "pipe", "pipe"] });
  srv.stderr.on("data", () => { /* 启动横幅等——不判 */ });
  const acc = makeLineAcc();
  const results = new Map<number, Frame>();
  const notifications: string[] = [];
  srv.stdout.on("data", (d) => {
    for (const line of acc.feed(d.toString("utf8"))) {
      const f = JSON.parse(line) as Frame;
      if (f.id !== undefined && f.id !== null) results.set(f.id, f);
      else if (f.method !== undefined) notifications.push(f.method);
    }
  });
  let seq = 0;
  const send = (method: string, params?: Record<string, unknown>): number => {
    const id = ++seq;
    void srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, ...(params === undefined ? {} : { params }) }) + "\n");
    return id;
  };
  const wait = (id: number, ms = 90_000): Promise<Frame> =>
    new Promise((resolve, reject) => {
      const t0 = Date.now();
      const iv = setInterval(() => {
        const got = results.get(id);
        if (got !== undefined) { clearInterval(iv); resolve(got); }
        else if (Date.now() - t0 > ms) { clearInterval(iv); reject(new Error(`timeout id=${id}`)); }
      }, 25);
    });
  const call = (name: string, args: Record<string, unknown>): Promise<{ isError: boolean; text: string; frame: Frame }> =>
    wait(send("tools/call", { name, arguments: args })).then((frame) => ({ ...toolTextOf(frame), frame }));
  function body<T>(r: { isError: boolean; text: string }): T {
    return JSON.parse(r.text) as T;
  }

  const chk = new CheckRun();
  try {
    // ── 协议契约 ──
    const init = (await wait(send("initialize", { protocolVersion: "2025-03-05" }))).result as {
      protocolVersion: string; capabilities: { tools: { listChanged: boolean } }; serverInfo: { name: string };
    };
    chk.check("initialize（回显版本 + listChanged）",
      init.capabilities.tools.listChanged === true && init.protocolVersion === "2025-03-05" && init.serverInfo.name === "vitro-dsh-plugin",
      JSON.stringify(init.serverInfo));
    void srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    void await wait(send("ping"));

    // ── L0 披露 + readOnlyHint ──
    const list0 = (await wait(send("tools/list"))).result as { tools: Array<{ name: string; annotations?: { readOnlyHint?: boolean } }> };
    chk.check("L0 = 5 工具",
      list0.tools.map((t) => t.name).join(",") === "animate,diagnose,capabilities,sessions,session_open",
      list0.tools.map((t) => t.name).join(","));
    const ro = new Map(list0.tools.map((t) => [t.name, t.annotations?.readOnlyHint === true]));
    chk.check("readOnlyHint（只读三真 / animate·session_open 假）",
      ro.get("diagnose") === true && ro.get("sessions") === true && ro.get("animate") === false && ro.get("session_open") === false);
    const guard = await call("frames_summary", {});
    chk.check("无会话 L1 守卫（isError + 指向 session_open）",
      guard.isError && guard.text.includes("session_open"), guard.text.slice(0, 60));

    // ── 会话 B：推进式（run_to 事件锚）──
    const openedB = body<{ session_id: string; compile_ok: boolean; algorithm_matches: Array<{ name: string }>; overview: { functions: unknown[] } }>(
      await call("session_open", { source: BUBBLE_C }));
    chk.check("session_open（compile_ok + bubble_sort + overview）",
      openedB.compile_ok && openedB.algorithm_matches?.[0]?.name === "bubble_sort" && openedB.overview.functions.length === 2,
      openedB.session_id);
    await new Promise((r) => setTimeout(r, 80));
    chk.check("解锁通知 list_changed", notifications.includes("notifications/tools/list_changed"));
    const list1 = (await wait(send("tools/list"))).result as { tools: unknown[] };
    chk.check("L1 = 12 工具", list1.tools.length === 12, String(list1.tools.length));
    const rt = body<{ event_step?: number; paused_at?: number; advanced: number }>(
      await call("run_to", { stop_event: "swap" }));
    chk.check("run_to stop_event=swap（首交换帧 93 行 8）",
      rt.event_step === 93 && rt.paused_at === 8 && rt.advanced > 0, JSON.stringify(rt));

    // ── 会话 A：惰性全采 + 投影 + 渲染（显式寻址 B 避免串扰）──
    const openedA = body<{ session_id: string }>(await call("session_open", { source: BUBBLE_C }));
    const summary = body<{ summary: { total: number; vis_events: Record<string, number>; stopped: string }; outputs: { stdout: string } }>(
      await call("frames_summary", { session_id: openedA.session_id }));
    chk.check("frames_summary（1126 / swap 7 / finished）",
      summary.summary.total === 1126 && summary.summary.vis_events.swap === 7 && summary.summary.stopped === "finished",
      `total=${summary.summary.total} vis=${JSON.stringify(summary.summary.vis_events)}`);
    chk.check("stdout 锚", summary.outputs.stdout === "1 2 3 5 8 9 \n", JSON.stringify(summary.outputs.stdout));
    const q = body<{ frames: Array<Record<string, unknown>>; has_more: boolean; to: number }>(
      await call("frames_query", { session_id: openedA.session_id, limit: 5 }));
    const keys = Object.keys(q.frames[0] ?? {}).sort().join(",");
    chk.check("默认投影 {f,i,l,s} + 分页", keys === "f,i,l,s" && q.frames.length === 5 && q.has_more && q.to === 5, keys);
    const q2 = body<{ total: number; frames: Array<{ r?: Record<string, string[]> }> }>(
      await call("frames_query", { session_id: openedA.session_id, fields: ["r"], filter: { has_vis_event: true } }));
    chk.check("fields=r + filter（61 含事件帧）",
      q2.total === 54 + 7 && q2.frames.length === 50 && q2.frames.some((f) => f.r?.arr !== undefined), `total=${q2.total}`);
    const rendered = body<{ ok: boolean; frame_count: number; size_bytes: number; html_path: string }>(
      await call("render", { session_id: openedA.session_id, budget: 300, out_dir: outDir, preview_png: false }));
    chk.check("render（301 帧 HTML 落盘）",
      rendered.ok && rendered.frame_count === 301 && rendered.size_bytes > 50_000 && existsSync(rendered.html_path),
      `${rendered.frame_count} 帧 ${rendered.size_bytes}B`);
    // ── 产物 script 语法门 + PLAYER 驱动对拍（#468/#469 防回归）──
    // #468：extern 模板字面量转义丢失曾致整段 script SyntaxError（播放器
    // 交互全灭，而「生成成功+帧数正确」验收不暴露）——vm.Script 编译 + 逐帧
    // 驱动是唯一会红的面。锚 3 = BUBBLE_C（真名恰为 arr）抽稀后 swap 帧
    // 点亮数（纯 vis_events 驱动——字幕正则兜底已随 #469 退役）。#517
    // P1-3 重锚（2026-11-14）：形参解引用视图修复后 bubble_sort 帧的 arr
    // 逐帧真变（修前恒为跨帧垃圾、arrays_eq 恒等）——关键帧 w=3 集从少数
    // 事件帧膨胀到几乎全帧，301 预算下 hi 集均匀抽稀，7 个 swap 帧保留
    // 3（旧锚 5 系「被调帧数组恒定」缺陷形态的基线）。PR #519 审阅 P2-3
    // 登记已知权衡：7 个 swap 帧仅 3 个点亮=关键帧抽稀稀释（数组逐帧
    // 真变令 w=3 集膨胀至近全帧、301 预算均匀抽稀）——产物质量回退面，
    // 修法在 extract_keyframes 权重/ararrays_eq 粒度（v1 照搬算法），列
    // 后续批候选，本批以锚值吸收不改算法。
    const pa = probeHtml(rendered.html_path);
    chk.check("render 产物 script 语法门 + PLAYER 驱动（BUBBLE_C swap 锚 3/#468·#469/#517）",
      pa.ok && pa.swapFrames === 3 && pa.total === 301,
      pa.ok ? `swap=${pa.swapFrames}/${pa.total}` : `驱动失败: ${pa.err ?? "?"}`);
    // TimelinePlan v0.1 批一（#470）：doc.timeline 与选中帧零基同构、sw 归属
    // 真名（bubble 真名=展示名 arr）、界内事件帧全点亮（3/3）、cap.t 同源。
    const pt = pa.data === undefined ? null : checkTimelinePlan(pa.data, "arr");
    chk.check(
      "doc.timeline：steps==frames(301) + 事件帧全点亮 3 + sw.name=arr（#470 批一）",
      pt !== null && pt.errors.length === 0 && pt.steps === 301 && pt.swFrames === 3,
      pt === null ? "产物数据缺失" : `steps=${pt.steps} sw=${pt.swFrames} ${pt.errors.slice(0, 3).join(" | ")}`,
    );
    // interactive 回落（CI 无 wasm 资产——恒走回落，恰锁该路径）
    const anim = body<{ ok: boolean; mode: string; frame_count: number; warnings: string[] }>(
      await call("animate", { source: BUBBLE_C, mode: "interactive", out_dir: outDir, preview_png: false }));
    chk.check("animate interactive 无 wasm 回落 static（401 帧 + 回落 warning）",
      anim.ok && anim.mode === "static" && anim.frame_count === 401 && anim.warnings.some((w) => w.includes("回落")),
      `mode=${anim.mode} frames=${anim.frame_count}`);

    // ── #469 分叉面语料：数组真名 a ≠ 字幕展示名 arr ──
    // 语义标注模板硬编码展示名 arr，正则咬字幕形态恒假（swap 全灭）；修复后
    // swap 高亮走 vis_events context 归属（demo visEvents.ts 同款）。锚 54 =
    // 81 帧里 54 个 ty=2 事件帧全点亮（context 形如 "a[j]:a[j + 1]"）。
    // #517 P2-7 重锚（2026-11-14）：is_swap_assign_line v4 修正单行语料的
    // 伪交换字幕（整行首个裸 = 在 `int a[5] = {…}…for (int i = 0;` 处——
    // v3 整行含 [] 即判交换，字幕恒「交换」撑起 weight-2 关键帧 301 抽稀）；
    // v4 字幕正确化后关键帧 301→81（数组/栈实义帧，不抽稀），7 个交换的
    // 原始事件帧全保留（21→54）。
    const openedC = body<{ session_id: string }>(await call("session_open", { source: BUBBLE_SORT_A }));
    const renderedC = body<{ ok: boolean; html_path: string; frame_count: number; error?: string }>(
      await call("render", { session_id: openedC.session_id, budget: 300, out_dir: outDir, preview_png: false }));
    const pc = probeHtml(renderedC.ok ? renderedC.html_path : "");
    chk.check("swap 高亮归属（真名 a ≠ 展示名 arr，vis_events context 归属锚 54/#469/#517）",
      renderedC.ok && pc.ok && pc.swapFrames === 54,
      renderedC.ok ? (pc.ok ? `swap=${pc.swapFrames}/${pc.total}` : `驱动失败: ${pc.err ?? "?"}`) : `render 红本文: ${renderedC.error ?? "?"}`);
    // TimelinePlan 分叉面锚：sw.name 必须是真实数组名 a（不是字幕展示名 arr）；
    // 81 帧里 54 个界内交换帧全点亮，另 2 帧 a[4]↔a[5] 越界（数组长 5）不产 sw
    // ——这条正是「数组长度入最小视图」的判别证据（否则 plan 会到 56 帧）。
    const ptc = pc.data === undefined ? null : checkTimelinePlan(pc.data, "a");
    chk.check(
      "doc.timeline：sw.name=a 54 界内帧全点亮 + 越界帧不产 sw（#470 批一）",
      renderedC.ok && ptc !== null && ptc.errors.length === 0 && ptc.steps === 81 && ptc.swFrames === 54,
      ptc === null ? "产物数据缺失" : `steps=${ptc.steps} sw=${ptc.swFrames} ${ptc.errors.slice(0, 3).join(" | ")}`,
    );
    await call("session_close", { session_id: openedC.session_id });

    // ── P3-6：真课 viz 声明经引擎解析（fourier 的 vitri-viz 块 → animate.viz）──
    {
      const md = readFileSync(path.resolve("course/basic/fourier/lesson.md"), "utf8").replace(/\r\n/g, "\n");
      const block = /<!--\s*vitri-viz v1\n([\s\S]*?)-->/.exec(md);
      const viz = (block?.[1] ?? "")
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l !== "" && !l.startsWith("//"))
        .join("\n");
      const vizAnim = body<{ ok: boolean; html_path: string; arrays_focused: string[] }>(
        await call("animate", { source: VIZ_PROBE_C, viz, out_dir: outDir, preview_png: false }));
      const html = vizAnim.ok ? readFileSync(vizAnim.html_path, "utf8") : "";
      const docOk = html.includes("\"series_decl\"") && html.includes("\"projector\":\"polar\"") && html.includes("\"projector\":\"spectrum\"");
      chk.check("fourier 真课 viz 声明进 doc（polar+spectrum + focus re/im，P3-6）",
        vizAnim.ok && viz !== "" && docOk && vizAnim.arrays_focused.includes("re") && vizAnim.arrays_focused.includes("im"),
        `viz=${JSON.stringify(viz)} focus=${(vizAnim.arrays_focused ?? []).join(",")}`);
    }

    // ── 收回披露 ──
    notifications.length = 0;
    await call("session_close", { session_id: openedB.session_id });
    await call("session_close", { session_id: openedA.session_id });
    await new Promise((r) => setTimeout(r, 80));
    const list2 = (await wait(send("tools/list"))).result as { tools: unknown[] };
    chk.check("全关收回（L0 5 + list_changed）",
      list2.tools.length === 5 && notifications.includes("notifications/tools/list_changed"));

    // EOF 退出语义（探针①的产物级复核）：关 stdin → 进程 exit 0
    const exitCode = await new Promise<number>((resolve) => {
      srv.once("exit", (c) => resolve(c ?? -1));
      srv.stdin.end();
    });
    chk.check("EOF 即 exit(0)", exitCode === 0, String(exitCode));
  } catch (e) {
    chk.check("驱动异常（超时/畸形帧）", false, e instanceof Error ? e.message : String(e));
    srv.kill();
  } finally {
    rmSync(outDir, { recursive: true, force: true });
  }
  const stat = existsSync(product) ? `产物 ${Math.round(statSync(product).size / 1024)}KB` : "";
  if (chk.failures.length === 0) {
    console.log(`mcp_smoke: PASS——${chk.total} 项断言全绿（${stat}）`);
    return 0;
  }
  console.error(`mcp_smoke: FAIL——${chk.failures.length}/${chk.total} 项红：`);
  for (const f of chk.failures) console.error(`  ✗ ${f}`);
  return 1;
}

if (process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  void drive().then((rc) => { process.exit(rc); });
}
