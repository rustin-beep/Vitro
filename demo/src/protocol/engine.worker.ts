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

export interface CollectResult {
  frames: StepPayload[];
  stopped: string;
  ms: number; // 采集墙钟（含编译+run+step 循环）
  versions: { engine: string; protocol: string };
}

async function collect(source: string, cap: number): Promise<CollectResult> {
  const g = await ensureGw();
  const t0 = performance.now();
  g.reset();
  bodyOf(invoke({ method: "session.create", params: {} }));
  // config.set 基准（与 demo run.ts buildBaseConfig 同值，fw_pilot 实证）——
  // **漏此步快照面整个缺失**（array_snapshots/local_vars 恒空，2026-10-15
  // 浏览器实测踩坑），帧粒度与 config 挂钩
  bodyOf(invoke({
    method: "config.set",
    params: { max_steps: 10000000, call_depth_limit: 10000, deterministic: false, quarantine_budget: 262144 },
  }));
  bodyOf(invoke({ method: "compile", params: { source } }));
  bodyOf(invoke({ method: "run", params: {} }));
  bodyOf(invoke({ method: "step.begin", params: {} }));
  const frames: StepPayload[] = [];
  let stopped = "";
  let batch;
  do {
    batch = bodyOf<StepNextResult>(invoke({ method: "step.next", params: {} }));
    if (batch.payloads) frames.push(...batch.payloads);
    if (batch.waiting_input) { stopped = "程序等待输入（scanf）——回放到暂停点为止"; break; }
    if (batch.trapped) { stopped = "受检终止：" + String(batch.trap_message || "").split("\n")[0]; break; }
  } while (!batch.finished && frames.length < cap);
  // 帧上限语义（用户 2026-10-15 点名修「4000 硬上限」）：上限是**前端采集
  // 预算**而非引擎能力——到顶显式说明引擎未截断，可调大重采；彻底解法
  // （稀疏/事件采集）挂 F2 的 #89。
  if (frames.length >= cap) stopped = stopped || `已达采集上限 ${cap} 帧（引擎未截断）——可调大上限重采`;
  return {
    frames,
    stopped,
    ms: Math.round(performance.now() - t0),
    versions: { engine: g.engine_version(), protocol: g.protocol_version() },
  };
}

self.onmessage = async (e: MessageEvent) => {
  const { id, op, source, cap } = e.data as { id: number; op: string; source?: string; cap?: number };
  try {
    if (op === "boot") {
      const g = await ensureGw();
      postMessage({ id, ok: true, data: { engine: g.engine_version(), protocol: g.protocol_version() } });
    } else if (op === "collect") {
      postMessage({ id, ok: true, data: await collect(source ?? "", cap ?? 20000) });
    } else {
      postMessage({ id, ok: false, error: `未知 op: ${String(op)}` });
    }
  } catch (err) {
    postMessage({ id, ok: false, error: String((err as Error)?.message ?? err) });
  }
};
