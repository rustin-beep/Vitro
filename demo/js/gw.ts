// Vitro demo · gateway 通道（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。TS 重写批：签名类型化 + js-string
// 扩展的 WebAssembly.Options 局部声明合并（DOM lib 缺口，非迁移税））。
"use strict";

import type { Frame } from "./types.ts";

/** gateway wasm-gc 导出面（S7 批五号：4 函数 + js-string builtins 直传）。 */
export interface GatewayExports {
  invoke(s: string): string;
  engine_version(): string;
  protocol_version(): string;
  reset(): void;
  [key: string]: unknown; // wasm 导出面其余符号（mem 等——invoke 通道不消费）
}

let gw: GatewayExports | null = null; // gateway exports
let frameId = 0;

export function setGateway(g: GatewayExports): void { gw = g; }
export function gateway(): GatewayExports {
  if (!gw) throw new Error("gateway 未装载（boot 前调用）");
  return gw;
}

// ── wasm 装载 ─────────────────────────────────────────────
export async function loadGateway(): Promise<GatewayExports> {
  const buf = await (await fetch("wasm.wasm")).arrayBuffer();
  // 与 host.js 同契约：js-string builtins + "_" 字符串常量模块（V8 扩展
  // 编译选项不在 DOM lib 的 ModuleOptions 签名里——@ts-expect-error 注明；
  // 未来 lib 补齐签名后本指令「未使用」即红，双向监控语义）
  // @ts-expect-error V8 js-string builtins 扩展（第二参不在 DOM lib 签名）
  const mod = new WebAssembly.Module(buf, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  const inst = await WebAssembly.instantiate(mod, {});
  return inst.exports as GatewayExports;
}

export function invoke<T = unknown>(obj: Record<string, unknown>): Frame<T> {
  frameId += 1;
  obj.id = frameId;
  return JSON.parse((gw as GatewayExports).invoke(JSON.stringify(obj)));
}

// 响应统一视图：协议所有方法帧均为「顶层 id/ok + result」包裹（含引擎
// trap 与步数超限——2026-09-30 审阅复核修正，此前注释误写顶层平铺形态）；
// bodyOf 保留为防御式取值。
// 参数 Frame<any>：wire 侧本就是 unknown 语义的防御式取值桥——调用点经
// invoke<T> 精确声明，bodyOf 只做「result 有无」的结构判断。
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const bodyOf = <T = Record<string, any>>(r: Frame<any> | null | undefined): T =>
  (r && (r.result as T) !== undefined ? (r.result as T) : (r as unknown as T)) || ({} as T);
