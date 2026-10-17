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

let gw: GatewayExports | null = null;
// wasm 资产走打包器 emit（publicDir=false，见 vite.config.ts）
const WASM_URL = new URL("../../wasm.wasm", import.meta.url).href;

async function ensureGw(): Promise<GatewayExports> {
  if (!gw) {
    gw = await loadGateway(WASM_URL);
    setGateway(gw); // invoke() 读 gw.ts 模块内单例——装载后必须注册
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
}

async function collect(source: string, cap: number, bpLines: number[], files?: Array<{ filename: string; source: string }>): Promise<CollectResult> {
  const g = await ensureGw();
  const t0 = performance.now();
  g.reset();
  must(invoke({ method: "session.create", params: {} }));
  // config.set 基准（与 demo run.ts buildBaseConfig 同值，fw_pilot 实证）——
  // **漏此步快照面整个缺失**（array_snapshots/local_vars 恒空，2026-10-15
  // 浏览器实测踩坑），帧粒度与 config 挂钩
  must(invoke({
    method: "config.set",
    params: { max_steps: 10000000, call_depth_limit: 10000, deterministic: false, quarantine_budget: 262144 },
  }));
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
    };
  }
  must(invoke({ method: "run", params: {} }));
  must(invoke({ method: "step.begin", params: {} }));
  const frames: StepPayload[] = [];
  let stopped = "";
  let batch;
  do {
    batch = must<StepNextResult>(invoke({ method: "step.next", params: {} }));
    if (batch.payloads) frames.push(...batch.payloads);
    if (batch.waiting_input) { stopped = "程序等待输入（scanf）——回放到暂停点为止"; break; }
    if (batch.trapped) { stopped = "受检终止：" + String(batch.trap_message || "").split("\n")[0]; break; }
  } while (!batch.finished && frames.length < cap);
  // 帧上限语义（用户 2026-10-15 点名修「4000 硬上限」）：上限是**前端采集
  // 预算**而非引擎能力——到顶显式说明引擎未截断，可调大重采；彻底解法
  // （稀疏/事件采集）挂 F2 的 #89。
  if (frames.length >= cap) stopped = stopped || `已达采集上限 ${cap} 帧（引擎未截断）——可调大上限重采`;
  // 输出四通道收集（照旧栈 finishRun 的 pull 形态：output.delta 分页拉到 total）；
  // stdin 喂入（waiting_input 场景）暂不在采集循环内——挂 F4 工作区批。
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
  return {
    frames,
    stopped,
    outputs,
    ms: Math.round(performance.now() - t0),
    versions: { engine: g.engine_version(), protocol: g.protocol_version() },
    // 编译成功也回传诊断（warning/hint 级——旧栈 renderDiagnostics 在 ok
    // 检查前调用，警告随成功一并展示；零诊断 = 空列表）
    diagnostics: comp.diagnostics ?? [],
    ppTrace: comp.preprocessor_trace ?? [],
    compileOk: true,
  };
}

/** wire 侧 Latin-1 折回 → UTF-8 还原：物理保留 util.ts 同名纯函数
 *  （TextDecoder 正确组合多字节序列；中文输出 mojibake 的既有解法）。 */

self.onmessage = async (e: MessageEvent) => {
  const { id, op, source, cap, method, params, bpLines, files } = e.data as {
    id: number; op: string; source?: string; cap?: number; method?: string; params?: Record<string, unknown>; bpLines?: number[]; files?: Array<{ filename: string; source: string }>;
  };
  try {
    if (op === "boot") {
      const g = await ensureGw();
      postMessage({ id, ok: true, data: { engine: g.engine_version(), protocol: g.protocol_version() } });
    } else if (op === "collect") {
      postMessage({ id, ok: true, data: await collect(source ?? "", cap ?? 20000, bpLines ?? [], files) });
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
