// Vitro demo · gateway 通道（app.js 拆分批 2026-10-04，refs #28：单体 1370 行 →
// 模块化 ESM——零构建纪律不变，<script type="module"> 静态直开兼容；内容自
// app.js 逐字迁移，仅增 import/export。）
"use strict";

let gw = null; // gateway exports
let frameId = 0;

export function setGateway(g) { gw = g; }
export function gateway() { return gw; }


// ── wasm 装载 ─────────────────────────────────────────────
export async function loadGateway() {
  const buf = await (await fetch("wasm.wasm")).arrayBuffer();
  // 与 host.js 同契约：js-string builtins + "_" 字符串常量模块
  const mod = new WebAssembly.Module(buf, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  const inst = await WebAssembly.instantiate(mod, {});
  return inst.exports;
}

export function invoke(obj) {
  frameId += 1;
  obj.id = frameId;
  return JSON.parse(gw.invoke(JSON.stringify(obj)));
}

// 响应统一视图：协议所有方法帧均为「顶层 id/ok + result」包裹（含引擎
// trap 与步数超限——2026-09-30 审阅复核修正，此前注释误写顶层平铺形态）；
// bodyOf 保留为防御式取值。
export const bodyOf = (r) => (r && r.result !== undefined ? r.result : r) || {};
