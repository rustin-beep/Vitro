// W4 第四臂对拍——node/V8 侧跑器（与 rs/src/main.rs 同形）：装载同一份
// wasm-gc 产物（V8 原生 js-string builtins + "_" 常量显式供给，装载逻辑复用
// scripts/wasm_load.mts 统一装载器），NDJSON 请求流逐行 invoke、响应逐行
// 写出。trap（任何异常穿透 invoke）写 `{"__host_trap__":…,"kind":…}` 行并
// 重建实例——与 Rust 侧同策略（trap 后 MoonBit 运行时状态不可信）。
//
// 输出编码：Buffer.from(str, "utf8")——lone surrogate → U+FFFD，与 Rust 侧
// String::from_utf16_lossy 同口径。写出走 fs.writeSync 全缓冲一次落盘
// （#366 教训：process.stdout 异步写 + 早退会丢尾段）。
//
// 用法：node host_node.mts <wasm.wasm> <requests.ndjson> <responses.ndjson>
// 退出码：0 正常（含 trap 行）；2 用法错；1 装载/IO 失败。

import { readFileSync, writeFileSync } from "node:fs";
import { compileGateway, stringConstsOf, type GatewayExports } from "../wasm_load.mts";

function instantiate(buf: BufferSource): GatewayExports {
  const mod = compileGateway(buf);
  const inst = new WebAssembly.Instance(mod, { _: stringConstsOf(buf) } as unknown as WebAssembly.Imports);
  return inst.exports as unknown as GatewayExports;
}

function jsonEscape(s: string): string {
  let out = "";
  for (const ch of s) {
    const c = ch.codePointAt(0) as number;
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (c < 0x20) out += "\\u" + c.toString(16).padStart(4, "0");
    else out += ch;
  }
  return out;
}

function main(): number {
  const argv = process.argv.slice(2);
  if (argv.length !== 3) {
    process.stderr.write("usage: node host_node.mts <wasm.wasm> <requests.ndjson> <responses.ndjson>\n");
    return 2;
  }
  const [wasmPath, reqPath, outPath] = argv as [string, string, string];
  const t0 = performance.now();
  const buf = readFileSync(wasmPath);
  let gw = instantiate(buf);
  const tInst = performance.now() - t0;

  const text = readFileSync(reqPath, "utf8");
  const lines = text.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  const outs: string[] = [];
  let traps = 0;
  const timings: [number, number][] = [];
  const tRun = performance.now();
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i] as string;
    const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
    const tLine = performance.now();
    try {
      outs.push(gw.invoke(line));
    } catch (e) {
      traps += 1;
      const err = e as { constructor?: { name?: string }; message?: string };
      const kind = `v8-${err?.constructor?.name ?? "unknown"}`;
      const msg = String(err?.message ?? e);
      outs.push(`{"__host_trap__":"${jsonEscape(msg)}","kind":"${jsonEscape(kind)}"}`);
      gw = instantiate(buf);
    }
    timings.push([i, performance.now() - tLine]);
  }
  writeFileSync(outPath, Buffer.from(outs.join("\n") + "\n", "utf8"));
  timings.sort((a, b) => b[1] - a[1]);
  const top = timings.slice(0, 10).map(([i, ms]) => `#${i}:${ms.toFixed(0)}ms`).join(",");
  process.stderr.write(
    `[host_node] lines=${lines.length} traps=${traps} instantiate=${tInst.toFixed(0)}ms run=${(performance.now() - tRun).toFixed(0)}ms node=${process.versions.node} v8=${process.versions.v8} top10=${top}\n`,
  );
  return 0;
}

process.exitCode = main();
