// Vitro 试点 · session 层雏形（F1，#119 迁移设计的 lib/session 落点）——
// gateway 调用 / 帧数组 / seek / 播放状态的单点。组件只读本层，不直接
// 摸 Worker 与 DOM。
//
// 响应式分界（best practices：$state 只给需要响应式的量；大数据走 raw）：
//   - session 标量/文案字段：UI 响应面——索引/播放态/状态文案/预算参数；
//   - session.frames（$state.raw）：帧大数据**引用替换响应、内容不代理**。
//     $derived 经 frameAt() 读它时依赖跟踪照常生效。
"use strict";

import type { Diagnostic, StepPayload, VisEvent } from "../js/types.ts";
import { KEYS, storeGet, storeSet } from "./persisted.svelte.ts";
import { toast } from "./toasts.svelte.ts";
import { buildCallTree } from "../js/calltree.ts";
import { statementEvents } from "./lib/visEvents.ts";
import { ICONS_DIGEST } from "../js/icons.ts";
import { ui } from "./ui.svelte.ts";
import { goldenOf, type GoldenState } from "./lib/golden.ts";
import { workspace, workspaceFilesForCompile } from "./lib/workspace.svelte.ts";

// 共享状态 = 官方推荐形态（best practices：classes with $state fields）——
// $state.raw 只能作声明初始化器/类字段，不可嵌在 $state({}) 字面量里
// （state_invalid_placement，2026-10-15 编译器实测）。
export interface CatalogCard {
  lang: string;
  category: string;
  code_str: string;
  title: string;
  explanation: string;
  icon: string;
  common_causes?: string[];
  [k: string]: unknown;
}

class SessionState {
  booted = $state(false);
  collecting = $state(false);
  epoch = $state(0); // 采集代号：切课/重置 = invalidate() 递增，在途采集回传即弃（防迟到覆写——旧栈 P0 竞态的 Worker 化放大形态，审阅 A-P0）
  playing = $state(false);
  batching = $state(false); // 批量推进中（bench/scrub）——FLIP 等交互动画此态关闭
  fps = $state(initFps()); // 播放帧率（档位见 ReplayBar；持久化=playback-fps 键）
  cap = $state(initCap()); // 采集帧预算（持久化=collect-cap 键；原 demo 硬上限 4000 → 可配）
  /** 帧大数据：引用替换响应、内容不深代理（采完只读）。⚠️ 帧源不可放
   * 模块级普通变量——非响应源不被 $derived 跟踪，首算后永不重算
   * （2026-10-15 浏览器实测踩坑：柱与变量表恒空即此因）。 */
  frames = $state.raw([] as StepPayload[]);
  idx = $state(0);
  status = $state("未采集——编辑源码后点「采集帧流」");
  stopped = $state("");
  versions = $state({ engine: "", protocol: "" });
  perf = $state({ collectMs: 0, replayPerFrameUs: 0 });
  outputs = $state({ stdout: "", stderr: "", note: "" }); // 四通道输出（采集时一次性拉齐）
  /** 编译期诊断全集（F4 残留①：worker 回传全集——含 warning/hint；run 视图
   *  诊断卡渲染。raw 不代理：加载后只读）。 */
  diagnostics = $state.raw([] as Diagnostic[]);
  /** 预处理宏展开轨迹（诊断卡折叠次块——旧栈 renderPpTrace 语义）。 */
  ppTrace = $state.raw([] as string[]);
  /** 编译业务域 ok——false = 零帧，诊断卡是主反馈面（stopped 留空不走
   *  trap pill 语义：编译失败不是「受检终止」）。 */
  compileOk = $state(true);
  gran = $state<"stmt" | "insn">(initGran()); // 粒度：insn=指令级（帧全集）/ stmt=语句级（按行合并组尾帧）
  /** 播放帧序列（粒度派生——审阅 A-P2-12 处方：派生生成不 mutate 真源）。
   *  语句级 = 按行合并组尾帧（coalesceStmt 物理保留 util.ts，tests 锚零改动）。
   *  事件表与帧序列**同一次派生**，保证逐位对齐（见 lib/visEvents.ts 头注：
   *  组尾帧自身常无 vis_events，语句级必须组内聚合，否则 ty=2 交换全丢）。 */
  private view = $derived.by((): { frames: StepPayload[]; events: VisEvent[][]; rawIndex: number[] } => {
    const raw = this.frames;
    if (this.gran === "insn") {
      return {
        frames: raw,
        events: raw.map((f) => f.vis_events ?? []),
        rawIndex: raw.map((_, i) => i),
      };
    }
    return statementEvents(raw);
  });
  viewFrames = $derived(this.view.frames);
  /** 与 viewFrames 逐位对齐的帧事件全集。 */
  viewEvents = $derived(this.view.events);
  /** 与 viewFrames 逐位对齐的原流帧下标（raw 表查表用）。 */
  viewRawIndex = $derived(this.view.rawIndex);
  /** 第 i 个回放帧的事件全集（组件/动效消费的单点；空帧返回空数组）。 */
  eventsAt(i: number): VisEvent[] {
    return this.viewEvents[i] ?? [];
  }
  /** view 下标 → 原流帧下标（调用树 frameNode / time_travel 等 raw 表查表用）。 */
  rawIndexAt(i: number): number {
    return this.viewRawIndex[i] ?? i;
  }
  capabilities = $state.raw<Record<string, unknown> | null>(null);
  contracts = $state.raw<Record<string, unknown> | null>(null);
  /** semantic_labels 词表（A19：引擎帧为对象数组 {id,domain,status,template,
   *  example}——此前误声明 string[] 只留 id 串，协议页全字段渲染的面丢了）。 */
  labels = $state.raw<unknown[]>([]);
  /** 诊断目录（error_catalog 协议数据归 session 层；组件纯展示）。
   *  不代理——加载后只读。 */
  catalog = $state.raw([] as CatalogCard[]);
  /** 调用树（帧全集 buildCallTree 产物 + frameNode 帧→节点映射；采集完成时构建）。
   *  树模型含 parent 互相引用——raw 不代理防循环引用代理开销。 */
  tree = $state.raw<import("../js/calltree.ts").CallTree | null>(null);
  /** 内存地图（memory.regions = 会话当前态快照，非帧级——旧栈同语义；
   *  采集完成时拉取，UAF/泄漏教学看结束态 freed 块与隔离区）。 */
  memory = $state.raw<import("../js/types.ts").MemoryRegions | null>(null);
  /** 断点行集合（SvelteSet 响应式；编辑器行号点击 toggle、采集时下发给
   *  breakpoints.set——旧栈模块级单例跨用例渗入的病在会话单点关死）。 */
  breakpoints = $state<number[]>([]); // 断点行数组（普通 $state 深响应——SvelteSet 在此链三轮异常后弃用）
  // ── A2-A8 主链面（#140）─────────────────────────────────────
  /** 会话配置基准（A4：UI 可写四字段；collect 时 config.set——configHint
   *  只合并不写回，「下一用例自动恢复基准」旧栈语义）。 */
  cfg = $state({ deterministic: false, max_steps: 10000000, call_depth_limit: 10000, quarantine_budget: 262144 });
  argvText = $state(""); // A3：argv 输入框（空格分隔；空则回落用例 argv）
  cfgMsg = $state(""); // A6：配置应用/覆盖反馈文案（旧栈 cfg-msg 语义）
  /** A8：run 六字段出口统计（返回码/VM 步数统计卡；编译失败 = null）。 */
  runStats = $state<{ status: string; return_value: number; steps_executed: number; waiting_input: boolean } | null>(null);
  stdinDraft = $state("42"); // A2：stdin 输入草稿（旧栈默认 42）
  /** 当前用例（A7 golden 对照 + configHint/argv 的单源锚）：点课时设置，
   *  null = 无预置真值（golden 区诚实缺席）。files = A9 multi_file 用例的
   *  多编译单元（非工作区模式下 collect 的 compile.files 来源）。
   *  raw 不代理：本对象经 postMessage 直传 Worker（argv/files/configHint
   *  三通道）——$state 深代理进 structured clone 必炸
   *  「could not be cloned」（2026-10-18 argv_prog 100% 复现）；用例是
   *  只读快照、点课整体替换写入，raw 语义恰配。 */
  currentCase = $state.raw<{ id: string; label: string; source: string; referenceOutput?: string | undefined; referenceTrap?: string | undefined; referenceKind?: string | undefined; configHint?: Record<string, unknown> | undefined; argv?: string[] | undefined; files?: Array<{ filename: string; source: string }> | undefined } | null>(null);
  appliedCfg = $state.raw<Record<string, unknown> | null>(null); // A5：config.get 回读视图
  /** A15：回放全宽（播放中隐藏左栏，可视化独占整行——旧栈 replay-wide
   *  同语义；设置态由本层单点管理，与 playing 相与生效）。 */
  replayWide = $state(storeGet(KEYS.replayWide) === "on");
  /** 编辑器当前源码（golden「已改稿」判定的活值——currentCase.source 是课稿
   *  原文，不能拿它自比；工作态 / 采集 / 分享还原三处写入）。 */
  liveSource = $state("");
  /** Clang golden 对照态（输出块徽章 / 诊断摘要 / 参考态同一投影）。
   *  设计说明 §12.2：未到末帧只报「自动对照」，末帧才判 ✓/✗，改过源码
   *  诚实失效（stale）——不拿旧预期比新代码。 */
  golden = $derived.by<GoldenState>(() =>
    goldenOf({
      kase: this.currentCase,
      source: this.liveSource,
      outputs: this.outputs,
      stopped: this.stopped,
      waiting: !!this.runStats?.waiting_input,
      paused: this.bpPaused,
      idx: this.idx,
      total: this.viewFrames.length,
    }),
  );
  /** 编译期错误的单行摘要（一句话诊断条 / 参考态跳转种子）。 */
  firstError = $derived(this.diagnostics.find((d) => d.severity === "error") ?? null);
  /** 运行期 trap（stopped 头部为受检终止——编译失败 ≠ trap，两态不混）。 */
  trapped = $derived(this.stopped.startsWith("受检终止"));
  /** 断点暂停（引擎 paused 批次——采集停在断点行）。 */
  bpPaused = $derived(this.stopped.startsWith("⏸"));
  /** 仪器数据面的显示帧：末帧常是程序收尾的 prog 帧（无数组快照、无局部
   *  变量、空调用栈），直接渲染会让「末帧终态」读成「数据丢了」。此处**只**
   *  给数组/变量面沿用最近一帧有数据的帧，并在块头标注「沿用第 N 帧」；
   *  时间轴/状态行/当前行染仍报真实帧号（读数不得张冠李戴）。 */
  displayIdx = $derived.by(() => {
    const vs = this.viewFrames;
    if (!vs.length) return 0;
    const hasData = (f: StepPayload): boolean => (f.array_snapshots?.length ?? 0) > 0 || (f.local_vars?.length ?? 0) > 0;
    const at = vs[this.idx];
    if (at !== undefined && hasData(at)) return this.idx;
    for (let i = this.idx - 1; i >= 0; i -= 1) {
      const f = vs[i];
      if (f !== undefined && hasData(f)) return i;
    }
    return this.idx;
  });
}

// ── 持久化初值（读有兜底，写有兜底——persisted 层统一）────────────────
// ⚠️ 必须先于 new SessionState()：类字段初始化器立即调用 initFps/initCap，
// const 声明不提升（TDZ，2026-10-15 浏览器实测抓过 TypeError）。
const FPS_STEPS = [2, 8, 30, 60, 120, 240]; // A24（#140）：恢复旧栈六档
function initFps(): number {
  const v = Number(storeGet(KEYS.playbackFps));
  // 默认 8 帧/秒（2026-10-18 改造：设计稿速度档「8 帧/秒 · 默认」——
  // 教学节奏宁慢勿快；显式选过档位的用户保持）
  return FPS_STEPS.includes(v) ? v : 8;
}
function initGran(): "stmt" | "insn" {
  const v = storeGet(KEYS.stepGran);
  // 默认语句级（行为拍板 2026-10-17：教学首屏按语句读，指令级是深挖档）；
  // 显式选过 insn 的用户保持
  return v === "insn" ? "insn" : "stmt";
}
function initCap(): number {
  const v = Number(storeGet(KEYS.cap));
  return v >= 100 && v <= 200000 ? Math.round(v) : 20000;
}

export const session = new SessionState();

/** 当前帧 = 粒度派生序列（viewFrames）的第 i 帧——UI 的帧计数/滑条/idx 全
 *  走 viewFrames 口径（语句级 = 组尾帧），此处必须同口径：返回 raw 帧
 *  frames[i] 会让行染/数组可视化/变量表/调用栈在语句级全面错位
 *  （2026-10-18 实测：末帧 i=34 渲染 raw[34].code_line=13 而非组尾帧）。
 *  指令级两序列同长，行为不变。 */
export function frameAt(i: number): StepPayload | undefined {
  return session.viewFrames[i];
}

/** 作废在途采集（切用例/切课时调用）：epoch 递增，迟到的采集回传整体丢弃。 */
export function toggleBreakpoint(line: number): void {
  const i = session.breakpoints.indexOf(line);
  if (i >= 0) session.breakpoints.splice(i, 1);
  else session.breakpoints.push(line);
}

export function invalidate(): void {
  session.epoch += 1;
}

// ── Worker RPC ───────────────────────────────────────────────
let worker: Worker | null = null;
let rpcId = 0;
const pending = new Map<number, { resolve: (v: never) => void; reject: (e: Error) => void; timer: ReturnType<typeof setTimeout> }>();

/** RPC 兜底超时（#288-①）：boot/invoke 短面 15s；collect/feed 是长面
 *  （帧采集整段跑完才回帖，大程序可达数十秒）放宽到 120s。Worker 根本
 *  没起来 / 脚本被 CSP 拦 ⇒ 永不回帖 ⇒ promise 永不 settle ⇒ 加载遮罩
 *  常驻零提示——超时与 onerror 双兜底把这条路堵死。 */
const RPC_TIMEOUT_MS = 15_000;
const RPC_TIMEOUT_LONG_MS = 120_000;

/** Worker 实例已不可信（超时/onerror）——terminate 销毁，下次 getWorker
 *  重建。「重试」按钮必须真的重建引擎，而不是继续撞同一个死实例。 */
function killWorker(): void {
  worker?.terminate();
  worker = null;
}

/** Worker 级故障（加载失败 / 运行期未捕获异常 / 消息无法反序列化）——
 *  在途 rpc 本该收到的回帖永远不来了，全部 reject，不让上层干等。 */
function rejectAllPending(err: Error): void {
  for (const p of pending.values()) {
    clearTimeout(p.timer);
    p.reject(err);
  }
  pending.clear();
}

function getWorker(): Worker {
  if (!worker) {
    worker = new Worker(new URL("./protocol/engine.worker.ts", import.meta.url), { type: "module" });
    worker.onmessage = (e: MessageEvent) => {
      const { id, ok, data, error } = e.data as { id: number; ok: boolean; data?: never; error?: string };
      const p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      clearTimeout(p.timer);
      if (ok) p.resolve(data as never);
      else p.reject(new Error(error ?? "worker 无错误信息"));
    };
    worker.onerror = (e: ErrorEvent) => {
      rejectAllPending(new Error(`引擎 Worker 异常（${e.message || e.filename || "未知错误"}）——可点「重试」重建引擎`));
      killWorker();
    };
    worker.onmessageerror = () => {
      rejectAllPending(new Error("引擎 Worker 消息无法反序列化——可点「重试」重建引擎"));
      killWorker();
    };
  }
  return worker;
}

function rpc<T>(msg: Record<string, unknown>, timeoutMs: number = RPC_TIMEOUT_MS): Promise<T> {
  const id = ++rpcId;
  const op = String(msg["op"] ?? msg["method"] ?? "rpc");
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      if (!pending.has(id)) return;
      pending.delete(id);
      killWorker(); // 永不回帖的实例不可信——销毁，重试走重建
      reject(new Error(`引擎 ${op} 无响应（${timeoutMs}ms 超时）——Worker 可能未启动或被浏览器策略拦截，可点「重试」`));
    }, timeoutMs);
    pending.set(id, { resolve: resolve as never, reject, timer });
    getWorker().postMessage({ id, ...msg });
  });
}

export class RpcError extends Error {
  readonly frame: Record<string, unknown>;
  constructor(frame: Record<string, unknown>) {
    super(String(frame["error"] ?? "协议错误帧（无错误文本）"));
    this.frame = frame;
  }
}

/** 通用方法调用（catalog/协议面等模块数据通道）：错误帧不折叠——顶层
 *  ok:false 抛 RpcError（帧原样挂 frame 供细读），成功回 result。 */
export async function call<T>(method: string, params: Record<string, unknown> = {}): Promise<T> {
  const resp = await rpc<Record<string, unknown>>({ op: "invoke", method, params });
  if (resp["ok"] === false) throw new RpcError(resp);
  return (resp["result"] ?? resp) as T;
}

// ── 对外动作 ────────────────────────────────────────────────
export async function boot(): Promise<void> {
  session.versions = await rpc<{ engine: string; protocol: string }>({ op: "boot" });
  session.booted = true;
}

/** 诊断目录拉取（引擎就绪后调一次；失败留空不阻塞页面，错误走 toast）。 */
export async function loadProto(): Promise<void> {
  try {
    const [cap, contracts, labels] = await Promise.all([
      call<Record<string, unknown>>("capabilities"),
      call<Record<string, unknown>>("contracts"),
      call<{ labels?: unknown[] }>("semantic_labels"),
    ]);
    session.capabilities = cap;
    session.contracts = contracts;
    session.labels = labels.labels ?? [];
  } catch (err) {
    toast("err", "协议面加载失败：" + String((err as Error).message).slice(0, 60));
  }
}

export async function loadCatalog(): Promise<void> {
  try {
    const r = await call<{ catalog?: CatalogCard[] }>("error_catalog");
    // A18（#140）：C 卡 lang 过滤（C++ 历史卡不展示——旧栈 catalog.ts 同语义）
    session.catalog = (r.catalog ?? [])
      .filter((c) => String(c.lang ?? "C").toLowerCase() === "c")
      .sort((a, b) => a.code_str.localeCompare(b.code_str));
    // A18：icons digest 对拍（本地 icons.ts 表 vs 引擎 icons.get——漂移即
    // 告警；抽样单 id 轻量探测，失败不阻塞手册）
    try {
      const ig = await call<{ digest?: string }>("icons.get", { ids: ["uaf"] });
      if (ig?.digest && ig.digest !== ICONS_DIGEST) {
        toast("err", "图标表 digest 与引擎不一致——本地 icons.ts 需再生成");
      }
    } catch { /* icons.get 不可用不阻塞 */ }
  } catch (err) {
    toast("err", "诊断目录加载失败：" + String((err as Error).message).slice(0, 60));
  }
}

export async function collect(source: string, _bpLines: number[] = [], opts: { autoplay?: boolean } = {}): Promise<void> {
  if (session.collecting) return;
  const my = ++session.epoch;
  session.collecting = true;
  session.playing = false;
  stopTimer();
  session.status = "Worker 采集中（编译 + run + step 闭环）…";
  // 开采即清陈旧结果（上次课的输出/统计/死因/树不得滞留冒充本次结果——
  // 采集失败时 catch 不写任何域，不清就会残留上一课数据伪装成本课结果
  // （2026-10-18 argv_prog 崩溃时 outputs/runStats 残留链表课实测）
  session.diagnostics = [];
  session.ppTrace = [];
  session.compileOk = true;
  session.outputs = { stdout: "", stderr: "", note: "" };
  session.runStats = null;
  session.stopped = "";
  session.tree = null;
  session.memory = null;
  session.frames = []; // 旧帧流同清：编辑器已是新课源码，回放旧帧 = 行染/画面张冠李戴
  session.idx = 0;
  try {
    // 工作区模式（F4 残留②）：全量打包 compile.files——active 文件 = 编辑器
    // 当前内容（liveSource 显式传，禁读 DOM）；单一源在 workspaceFilesForCompile
    // （旧栈 buildCompileParams 同语义，两条通道同口径）。
    // A9（#140）：非工作区下 multi_file 用例的 files 通道（用例声明多编译
    // 单元——编辑器内容即首单元 main.c，跨文件链接跑通）。
    let files = workspace.active
      ? workspaceFilesForCompile(source)
      : ((session.currentCase?.files as Array<{ filename: string; source: string }> | undefined));
    // 编辑器内容若已被用户改动，用例 files 的 main.c 副本会与编辑器脱节——
    // 此检测面：currentCase.files 存在且 source ≠ files[0].source 时以编辑器
    // 内容为准回写首单元（旧栈 buildCompileParams「编辑器内容即 main.c」同语义）。
    // ⚠️ currentCase.files 是 $state 深代理——postMessage structured clone
    // 不收 Proxy，必须 map 纯化为普通对象（工作区模式返回新建对象故无此坑）。
    if (!workspace.active && files && files.length > 0) {
      files = files.map((f) => ({ filename: f.filename, source: f.source }));
      const first = files[0];
      if (first !== undefined && first.source !== source) {
        files = [{ filename: first.filename, source }, ...files.slice(1)];
      }
    }
    // A4/A6（#140）：config = UI 基准 + 用例 configHint 一次性合并（hint 不
    // 写回基准——下一用例自动恢复，旧栈 cfg-msg 语义）
    const hint = session.currentCase?.configHint as Record<string, unknown> | undefined;
    const cfg: Record<string, unknown> = { ...session.cfg, ...hint };
    if (hint && Object.keys(hint).length > 0) {
      session.cfgMsg = `本用例临时覆盖 config：${Object.entries(hint).map(([k, v]) => `${k}=${String(v)}`).join("，")}（下一用例自动恢复基准）`;
    } else {
      session.cfgMsg = "";
    }
    // A3：argv 用户输入优先，空则回落用例声明（旧栈 runParams 同语义）
    const argvText = session.argvText.trim();
    const argv = argvText ? argvText.split(/\s+/) : (session.currentCase?.argv as string[] | undefined);
    const r = await rpc<{ frames: StepPayload[]; stopped: string; outputs: { stdout: string; stderr: string; note: string }; ms: number; versions: { engine: string; protocol: string }; diagnostics: Diagnostic[]; ppTrace: string[]; compileOk: boolean; run: { status: string; return_value: number; steps_executed: number; waiting_input: boolean } | null }>({
      op: "collect",
      source,
      cap: session.cap,
      bpLines: [...session.breakpoints],
      files,
      cfg,
      argv,
    }, RPC_TIMEOUT_LONG_MS);
    if (my !== session.epoch) return; // 迟到回传：期间有新采集/作废，整体丢弃不碰任何状态
    session.frames = r.frames;
    session.idx = 0;
    // 编译失败时网关可能回传上一轮的 stopped（引擎侧滞留）——按 compileOk
    // 截断，否则旧 trap 会挂在新代码上冒充本次死因（2026-10-18 实测）。
    session.stopped = r.compileOk ? r.stopped : "";
    session.outputs = r.outputs;
    session.diagnostics = r.diagnostics ?? [];
    session.ppTrace = r.ppTrace ?? [];
    session.compileOk = r.compileOk;
    if (!r.compileOk) {
      // 编译失败（F4 残留①）：零帧 + 树/内存清空；诊断卡是主反馈面，
      // stopped 留空（编译失败 ≠ trap pill「受检终止」——两态不得混显）
      session.tree = null;
      session.memory = null;
      session.runStats = null;
      session.perf.collectMs = r.ms;
      session.versions = r.versions;
      const errs = session.diagnostics.filter((d) => d.severity === "error").length;
      session.status = `编译失败——${session.diagnostics.length} 条诊断（${errs} 错误）见诊断带`;
      // 编译失败即回工作态执行模式——诊断带（一句话 + 明细）是保证可见的
      // 反馈面（单页形态下不再有「切到运行 tab」这一步）
      ui.screen = "work";
      ui.mode = "exec";
      toast("err", session.status);
      return;
    }
    session.tree = buildCallTree(r.frames); // 调用树（帧全集 → trie；物理保留 js/calltree.ts 纯函数）
    session.runStats = r.run; // A8：返回码/VM 步数统计卡数据源
    // 采集成功即回工作态执行模式（单页形态「结果立即可见」的等价：
    // 在内存/手册页点采集不该扑空）
    ui.screen = "work";
    ui.mode = "exec";
    try {
      const mem = await call<{ [k: string]: unknown }>("memory.regions");
      session.memory = mem as unknown as import("../js/types.ts").MemoryRegions;
    } catch { session.memory = null; } // memory.regions 失败不阻塞帧回放
    session.perf.collectMs = r.ms;
    session.versions = r.versions;
    session.status = r.frames.length
      ? `采集 ${r.frames.length} 帧 · 耗时 ${r.ms}ms`
      : "零帧——程序无步进（空 main 或立即返回）";
    // 采集完自动播放（行为拍板 2026-10-17，恢复旧栈 stepRecollect 末尾
    // stepPlay 语义——采集即回放的教学节奏）。首访/继续上次的落地采集传
    // autoplay:false（设计稿首访动线：已预载一帧、暂停，不自动播放）。
    if (r.frames.length > 0 && opts.autoplay !== false) togglePlay();
    // 反馈分域：会话态走 status 行；操作结果走 toast（失败/到顶才弹，成功不扰）
    if (r.stopped) toast("err", r.stopped);
  } catch (err) {
    if (my !== session.epoch) return;
    const msg = "采集失败：" + String((err as Error).message);
    session.status = msg;
    toast("err", msg); // 失败原因进 toast 队列（可驻留细读）——status 行保持会话态
  } finally {
    if (my === session.epoch) session.collecting = false; // 仅当仍为当前代号才清旗——迟到回传不得错清新采集的旗
  }
}

export function seek(i: number): void {
  session.idx = Math.max(0, Math.min(i, session.viewFrames.length - 1));
}

/** A2（#140）：stdin 喂入续跑——waiting_input 态把门；worker 侧 input.feed
 *  延续 run 后**重建 step 会话全量重采**（feed 改变执行轨迹，前段帧流
 *  过期），状态写回同 collect 形态。 */
export async function feedStdin(): Promise<void> {
  if (session.collecting || !session.runStats?.waiting_input) return;
  const my = session.epoch;
  session.collecting = true;
  session.playing = false;
  stopTimer();
  session.status = "喂入续跑中（input.feed + 全量重采）…";
  try {
    const r = await rpc<{ frames: StepPayload[]; stopped: string; outputs: { stdout: string; stderr: string; note: string }; ms: number; run: { status: string; return_value: number; steps_executed: number; waiting_input: boolean } | null }>({
      op: "feed",
      text: session.stdinDraft,
      cap: session.cap,
    }, RPC_TIMEOUT_LONG_MS);
    if (my !== session.epoch) return;
    session.frames = r.frames;
    session.idx = 0;
    session.stopped = r.stopped;
    session.outputs = r.outputs;
    session.runStats = r.run;
    session.tree = buildCallTree(r.frames);
    session.perf.collectMs = r.ms;
    session.status = r.frames.length
      ? `喂入后续采 ${r.frames.length} 帧 · 耗时 ${r.ms}ms`
      : "零帧——程序无步进";
    if (r.stopped) toast("err", r.stopped);
    try {
      const mem = await call<{ [k: string]: unknown }>("memory.regions");
      session.memory = mem as unknown as import("../js/types.ts").MemoryRegions;
    } catch { session.memory = null; }
  } catch (err) {
    if (my !== session.epoch) return;
    const msg = "喂入失败：" + String((err as Error).message);
    session.status = msg;
    toast("err", msg);
  } finally {
    if (my === session.epoch) session.collecting = false;
  }
}

/** A4/A5（#140）：config 应用 + config.get 回读。config 在 collect 的
 *  g.reset()+session.create 后由 collect 显式 config.set——本动作的设置
 *  作用于当前 gateway 会话（回读即所见），采集始终以 session.cfg 基准
 *  (+hint) 重设，两条通道不打架。 */
export async function applyCfg(): Promise<void> {
  try {
    await call("config.set", { ...session.cfg });
    const c = await call<Record<string, unknown>>("config.get");
    session.appliedCfg = c;
    session.cfgMsg = `已应用 ✓（deterministic=${String(c["deterministic"])}，max_steps=${String(c["max_steps"])}，call_depth=${String(c["call_depth_limit"])}）`;
    toast("ok", "会话配置已应用");
  } catch (err) {
    session.cfgMsg = "应用失败：" + String((err as Error).message).slice(0, 80);
    toast("err", session.cfgMsg);
  }
}

export function step(delta: number): void {
  seek(session.idx + delta);
}

let timer: ReturnType<typeof setInterval> | undefined;
let lastTick = 0;
function stopTimer(): void {
  if (timer !== undefined) {
    clearInterval(timer);
    timer = undefined;
  }
}

export function togglePlay(): void {
  if (session.playing) {
    session.playing = false;
    stopTimer();
    return;
  }
  if (!session.viewFrames.length) return;
  session.playing = true;
  lastTick = performance.now();
  timer = setInterval(() => {
    const now = performance.now();
    const interval = 1000 / session.fps;
    // A26（#140）：时间戳驱动合成跳帧——定时器/渲染跟不上节奏时按实际
    // 耗时补推进帧数（慢渲染下节奏不失真；钳 1..6 防雪崩跳穿）。
    const n = Math.max(1, Math.min(6, Math.round((now - lastTick) / interval)));
    lastTick = now;
    if (session.idx >= session.viewFrames.length - 1) {
      togglePlay(); // 播完即停
      // 播完必须可感知（2026-10-18 实测：240fps 播完零提示，短程序 30fps
      // 零点几秒播完，用户只见「动几帧突然停」不知是完毕还是卡死）。
      // 走 status 行不走 toast：回放态属会话域状态（toasts 头注分域契约）；
      // 且 toast 悬浮条在此场景实测有焦点副作用（E2E W7 排障记录——
      // toast 存活期内 CM 聚焦被夺，机制未穷尽，回避面见 Toasts.svelte 注）。
      session.status = `回放完毕——共 ${session.viewFrames.length} 帧，已停在末帧（拖滑条或 ◀| 回看）`;
      return;
    }
    step(Math.min(n, session.viewFrames.length - 1 - session.idx));
  }, Math.round(1000 / session.fps));
}

export function setFps(f: number): void {
  const was = session.playing;
  if (was) togglePlay();
  session.fps = f;
  if (was) togglePlay();
  storeSet(KEYS.playbackFps, String(f));
}

export function setGran(g: "stmt" | "insn"): void {
  const was = session.playing;
  if (was) togglePlay();
  session.gran = g;
  session.idx = Math.min(session.idx, session.viewFrames.length - 1);
  if (was) togglePlay();
  storeSet(KEYS.stepGran, g);
}

export function setCap(v: number): void {
  session.cap = v >= 100 && v <= 200000 ? Math.round(v) : 20000;
  storeSet(KEYS.cap, String(session.cap));
}

/** A15：回放全宽开关（设置面板消费；持久化 replayWide 键）。 */
export function setReplayWide(on: boolean): void {
  session.replayWide = on;
  storeSet(KEYS.replayWide, on ? "on" : "off");
}

/** 重置回放视图（工作态运行条「重置」）：停播 + 清帧/诊断/树/内存/输出，
 *  源码不动（重置的是仪器，不是编辑器——改代码后点「运行」重采）。
 *  清场范围与 collect 开采清场同口径，防旧画面冒充新会话。 */
export function resetSession(): void {
  stopTimer();
  session.playing = false;
  session.collecting = false;
  session.frames = [];
  session.idx = 0;
  session.stopped = "";
  session.diagnostics = [];
  session.ppTrace = [];
  session.compileOk = true;
  session.outputs = { stdout: "", stderr: "", note: "" };
  session.runStats = null;
  session.tree = null;
  session.memory = null;
  session.perf.collectMs = 0;
  session.status = "未采集——点「运行」从头采集帧流";
}
