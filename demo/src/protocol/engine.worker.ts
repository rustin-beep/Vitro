// Vitro 试点 · 引擎 Worker（F1，refs #122）——wasm gateway 整体搬进
// Web Worker：编译/执行/采帧全部离开主线程，非法代码（死循环/长程序）
// 不再阻塞 UI（用户 2026-10-15 点名的两病之一）。主线程只经 postMessage
// RPC 与本 Worker 通信；1925 次 step.next 全在 Worker 内闭环，帧数组
// structured clone 一次性回传。
//
// 协议序列照抄 demo/js/timetravel.ts stepCollect（reset→session.create→
// compile→run→step.begin→step.next 循环），不做任何协议面发明。
"use strict";

import { loadGateway, setGateway, invoke, bodyOf, type GatewayExports } from "../../js/gw.ts";
import type { Diagnostic, Frame } from "../../js/types.ts";
import { latin1ToUtf8 } from "../../js/util.ts";
import type { StepPayload, StepNextResult } from "../../js/types.ts";
import wasmUrl from "../../wasm.wasm?url";

let gw: GatewayExports | null = null;
let textsInstalled = false;
// wasm 资产走打包器 emit（publicDir=false，见 vite.config.ts）。?url 显式
// 资产形态（#139）：构建期源缺失 = build 直接红；此前 new URL 形态在 CI
// 裸检出（wasm 不入库、构建后才拷）下静默保留相对路径，Pages 运行时
// 404 且 boot 无 catch 全程无提示。
const WASM_URL = wasmUrl;

/** #130 批② demo 接线（三步，CLI inject_texts_at_startup 同构 fail-soft）：
 *  ①动态懒加载语言包（vite 懒 chunk，产物 moonbit js target 构建期 cp 到
 *  demo/teaching/langpack/——与 wasm.wasm 同发射产物纪律）②texts_json()
 *  取 payload 文本 ③texts.install 注入引擎——之后建议文案/诊断卡文案全量
 *  可用。注入失败不阻断（引擎表保持产物内现状，console 明示）。幂等。 */
async function installTexts(): Promise<void> {
  if (textsInstalled) return;
  textsInstalled = true;
  try {
    const m = await import("../../teaching/langpack/langpack.js");
    const payload = m.texts_json();
    const resp = invoke({ method: "texts.install", params: { payload } });
    if (!resp.ok) {
      // 错误帧不折叠（must 同语义）——但语言包注入失败不阻断 boot
      console.warn("[vitro] 语言包注入失败（引擎表保持产物内现状）：", String(resp.error ?? "").slice(0, 120));
    }
  } catch (err) {
    console.warn("[vitro] 语言包懒加载失败（引擎表保持产物内现状）：", String((err as Error)?.message ?? err).slice(0, 120));
  }
}

async function ensureGw(): Promise<GatewayExports> {
  if (!gw) {
    gw = await loadGateway(WASM_URL);
    setGateway(gw); // invoke() 读 gw.ts 模块内单例——装载后必须注册
    await installTexts(); // #130 批②：语言包启动注入（boot 链内完成，先于任何 compile）
  }
  return gw;
}

/** must = 错误帧不折叠：顶层 ok:false 即抛（旧栈 bodyOf 把错误帧折叠成
 *  {}，静默假态一路传到 UI——审阅 A-P1 实锤 run.ts:208 pill 显示字面量
 *  "undefined"。session 层第一天生效「ok:false 即异常、异常必可渲染」）。 */
function must<T>(resp: Frame<T>): T {
  if (!resp.ok) throw new Error(String(resp.error ?? "协议错误帧（无错误文本）"));
  return bodyOf(resp);
}

export interface CollectResult {
  frames: StepPayload[];
  stopped: string;
  outputs: { stdout: string; stderr: string; note: string }; // 四通道视图（note = 引擎文本域）
  ms: number; // 采集墙钟（含编译+run+step 循环）
  versions: { engine: string; protocol: string };
  /** 编译期诊断全集（F4 残留① run 视图诊断卡：旧栈 renderDiagnostics 语义——
   *  compile.ok=false 时回传列表供卡片渲染，不再只抛首条 message）。 */
  diagnostics: Diagnostic[];
  /** 预处理宏展开轨迹（旧栈 renderPpTrace 同源）。 */
  ppTrace: string[];
  /** 编译业务域 ok（result.ok）——false 时 frames 为空、诊断卡是主反馈面。 */
  compileOk: boolean;
  /** run 六字段出口（A8：返回码/VM 步数统计卡 + A2 waiting_input 驱动）。 */
  run: { status: string; return_value: number; steps_executed: number; waiting_input: boolean } | null;
}

type EngineCfg = Record<string, unknown>;

async function pullOutputs(): Promise<{ stdout: string; stderr: string; note: string }> {
  // 输出四通道收集（照旧栈 finishRun 的 pull 形态：output.delta 分页拉到
  // total）。collect 与 feed 两通道共用（feed 后全量重拉——cursor 是会话
  // 域游标，重拉即最新全量，session 侧整体替换）。
  const outputs = { stdout: "", stderr: "", note: "" };
  for (const stream of ["stdout", "stderr", "note"] as const) {
    let cursor = 0;
    for (;;) {
      const o = must<{ delta: string; cursor: number; total: number }>(
        invoke({ method: "output.delta", params: { cursor, stream } }),
      );
      if (stream === "stdout") outputs.stdout += latin1ToUtf8(o.delta);
      else if (stream === "stderr") outputs.stderr += latin1ToUtf8(o.delta);
      else outputs.note += o.delta; // note = 引擎文本域真 UTF-8 直传（旧栈分域解码同款：还原会截 >0xFF 码点必乱码）
      if (o.cursor >= o.total || !o.delta) break;
      cursor = o.cursor;
    }
  }
  return outputs;
}

/** step.next 收帧循环（collect / feed 两通道共用）：paused/waiting/trapped
 *  三停点 + 帧上限。 */
async function drainSteps(cap: number): Promise<{ frames: StepPayload[]; stopped: string }> {
  const frames: StepPayload[] = [];
  let stopped = "";
  let batch;
  do {
    batch = must<StepNextResult>(invoke({ method: "step.next", params: {} }));
    if (batch.payloads) frames.push(...batch.payloads);
    if (batch.waiting_input) { stopped = "程序等待输入（scanf）——在下方输入框喂入续跑"; break; }
    // paused = 引擎推进到断点行的批次暂停（breakpoints.set 语义）——停采
    // 但**保留已采帧**：回放条可走到暂停点观察现场（旧栈同文案）
    if (batch.paused) { stopped = "⏸ 已到断点（引擎暂停）——清除断点后 ↻ 重新采集可继续"; break; }
    if (batch.trapped) { stopped = "受检终止：" + String(batch.trap_message || ""); break; } // 全文保留（trap 详报框——死因报告是白箱课核心内容，不截首行）
  } while (!batch.finished && frames.length < cap);
  return { frames, stopped };
}

async function collect(source: string, cap: number, bpLines: number[], files: Array<{ filename: string; source: string }> | undefined, cfg: EngineCfg, argv: string[] | undefined): Promise<CollectResult> {
  const g = await ensureGw();
  const t0 = performance.now();
  g.reset();
  must(invoke({ method: "session.create", params: {} }));
  // config.set（A4/A6，#140）：cfg = UI 基准 + 用例 configHint 合并后的
  // 最终值（合并在 session 层做，hint 不写回基准——「下一用例自动恢复」
  // 旧栈语义）。**漏此步快照面整个缺失**（array_snapshots/local_vars 恒
  // 空，2026-10-15 浏览器实测踩坑），帧粒度与 config 挂钩
  must(invoke({ method: "config.set", params: cfg }));
  // 工作区模式（F4 残留②）：全量打包 compile.files（引擎 vfs 解析集合内
  // quote-include；active 文件居首 = base_dir 锚，orderForCompile 保证）——
  // 旧栈 buildCompileParams 单一源语义，两条通道同口径
  const comp = files && files.length > 0
    ? must(invoke<{ ok: boolean; diagnostics?: Diagnostic[]; preprocessor_trace?: string[] }>({ method: "compile", params: { files } }))
    : must(invoke<{ ok: boolean; diagnostics?: Diagnostic[]; preprocessor_trace?: string[] }>({ method: "compile", params: { source } }));
  if (!comp.ok) {
    // 编译失败 = 业务域 ok（result.ok，非顶层帧 ok）——F4 残留①：不再只抛
    // 首条 message，回传诊断全集 + pp 轨迹，由 run 视图诊断卡渲染（旧栈
    // renderDiagnostics / renderPpTrace 语义平移）。零帧 + 输出清空
    // （禁陈旧输出滞留造成「失败却见旧 stdout」假态）。
    return {
      frames: [],
      stopped: "编译失败——诊断见「运行」视图",
      outputs: { stdout: "", stderr: "", note: "" },
      ms: Math.round(performance.now() - t0),
      versions: { engine: g.engine_version(), protocol: g.protocol_version() },
      diagnostics: comp.diagnostics ?? [],
      ppTrace: comp.preprocessor_trace ?? [],
      compileOk: false,
      run: null,
    };
  }
  // A3（#140）：argv 通道（run params argv——引擎侧跨 run 存活，serve_run
  // 解析；空数组省略参数，对齐旧栈 runParams 的「有才带」形态）
  const run = must<{ status: string; return_value: number; steps_executed: number; waiting_input: boolean }>(
    invoke({ method: "run", params: argv && argv.length > 0 ? { argv } : {} }),
  );
  must(invoke({ method: "step.begin", params: {} }));
  // 断点下发（A1，#140——旧栈 timetravel.ts stepCollect 语义平移）：
  // **必须落在 step.begin 之后**——begin 重建 vm，重建前设置的断点会被
  // 清掉。此前 bpLines 收下后零使用（无 breakpoints.set、循环无 paused
  // 分支），断点 UI 完整但采集全程跑完不停（GUI+E2E S5 双实证）。
  if (bpLines.length > 0) {
    must(invoke({ method: "breakpoints.set", params: { lines: bpLines } }));
  }
  const { frames, stopped } = await drainSteps(cap);
  // 帧上限语义（用户 2026-10-15 点名修「4000 硬上限」）：上限是**前端采集
  // 预算**而非引擎能力——到顶显式说明引擎未截断，可调大重采；彻底解法
  // （稀疏/事件采集）挂 F2 的 #89。
  const capped = frames.length >= cap;
  const finalStopped = stopped || (capped ? `已达采集上限 ${cap} 帧（引擎未截断）——可调大上限重采` : "");
  const outputs = await pullOutputs();
  return {
    frames,
    stopped: finalStopped,
    outputs,
    ms: Math.round(performance.now() - t0),
    versions: { engine: g.engine_version(), protocol: g.protocol_version() },
    // 编译成功也回传诊断（warning/hint 级——旧栈 renderDiagnostics 在 ok
    // 检查前调用，警告随成功一并展示；零诊断 = 空列表）
    diagnostics: comp.diagnostics ?? [],
    ppTrace: comp.preprocessor_trace ?? [],
    compileOk: true,
    run: { status: run.status, return_value: run.return_value, steps_executed: run.steps_executed, waiting_input: run.waiting_input },
  };
}

/** A2（#140）stdin 喂入续跑：input.feed 延续 waiting_input 的 run（引擎
 *  锚 serve_input_feed_continues_waiting：run→waiting→feed→finished），
 *  随后**重建 step 会话全量重采**——feed 改变执行轨迹，前段帧流已过期；
 *  重采帧覆盖含喂入后半段的完整执行，回放从头可播。 */
async function feed(text: string, cap: number): Promise<CollectResult> {
  const g = await ensureGw();
  const t0 = performance.now();
  const run = must<{ status: string; return_value: number; steps_executed: number; waiting_input: boolean }>(
    invoke({ method: "input.feed", params: { text: text + "\n" } }),
  );
  must(invoke({ method: "step.begin", params: {} }));
  const { frames, stopped } = await drainSteps(cap);
  const outputs = await pullOutputs();
  return {
    frames,
    stopped,
    outputs,
    ms: Math.round(performance.now() - t0),
    versions: { engine: g.engine_version(), protocol: g.protocol_version() },
    diagnostics: [],
    ppTrace: [],
    compileOk: true,
    run: { status: run.status, return_value: run.return_value, steps_executed: run.steps_executed, waiting_input: run.waiting_input },
  };
}

/** wire 侧 Latin-1 折回 → UTF-8 还原：物理保留 util.ts 同名纯函数
 *  （TextDecoder 正确组合多字节序列；中文输出 mojibake 的既有解法）。 */

self.onmessage = async (e: MessageEvent) => {
  const { id, op, source, cap, method, params, bpLines, files, cfg, argv, text } = e.data as {
    id: number; op: string; source?: string; cap?: number; method?: string; params?: Record<string, unknown>; bpLines?: number[]; files?: Array<{ filename: string; source: string }>; cfg?: EngineCfg; argv?: string[]; text?: string;
  };
  try {
    if (op === "boot") {
      const g = await ensureGw();
      postMessage({ id, ok: true, data: { engine: g.engine_version(), protocol: g.protocol_version() } });
    } else if (op === "collect") {
      postMessage({ id, ok: true, data: await collect(source ?? "", cap ?? 20000, bpLines ?? [], files, cfg ?? {}, argv) });
    } else if (op === "feed") {
      // A2 stdin 喂入续跑（前提：会话处于 waiting_input——session 层把门）
      postMessage({ id, ok: true, data: await feed(text ?? "", cap ?? 20000) });
    } else if (op === "invoke") {
      // 通用 RPC 转发（catalog/协议面等模块数据通道）：错误帧不折叠——
      // 顶层 ok:false 原样回传，session 层拆帧抛 RpcError（must 同语义）。
      await ensureGw();
      const resp = invoke({ method: method ?? "", params: params ?? {} });
      postMessage({ id, ok: true, data: resp });
    } else {
      postMessage({ id, ok: false, error: `未知 op: ${String(op)}` });
    }
  } catch (err) {
    postMessage({ id, ok: false, error: String((err as Error)?.message ?? err) });
  }
};
