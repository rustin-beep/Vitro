// wasm_load 单元面（#273 四件套：node:test）：合成 wasm 二进制锁装载器契约。
import { test } from "node:test";
import assert from "node:assert/strict";
import { compileGateway, instantiateGateway, stringConstsOf } from "./wasm_load.mts";

function name(s: string): number[] {
  const bytes = [...Buffer.from(s, "utf8")];
  assert.ok(bytes.length < 128, "fixture 长度走单字节 LEB");
  return [bytes.length, ...bytes];
}

function section(id: number, payload: number[]): number[] {
  assert.ok(payload.length < 128, "fixture 段长走单字节 LEB");
  return [id, payload.length, ...payload];
}

// "_" 模块字符串常量（externref 全局）；withEnv 追加 env 模块内存 import——
// 锁 stringConstsOf 的过滤面（只收 "_"）。
function buildWasm(withEnv = false): Uint8Array<ArrayBuffer> {
  const typeSection = section(1, [0x01, 0x60, 0x00, 0x00]);
  const imports = [...name("_"), ...name("hello"), 0x03, 0x6f, 0x00];
  if (withEnv) imports.push(...name("env"), ...name("mem"), 0x02, 0x00, 0x01);
  const importSection = section(2, [withEnv ? 0x02 : 0x01, ...imports]);
  return Uint8Array.from([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, ...typeSection, ...importSection]);
}

test("stringConstsOf 只枚举 \"_\" 模块的 name→name 常量", () => {
  assert.deepEqual(stringConstsOf(buildWasm(true)), { hello: "hello" });
});

test("compileGateway 接受 V8 builtins 选项编译产物", () => {
  const mod = compileGateway(buildWasm());
  assert.ok(mod instanceof WebAssembly.Module);
});

test("instantiateGateway 显式供给 \"_\" 常量后可实例化", async () => {
  const inst = await instantiateGateway(buildWasm());
  assert.ok(inst instanceof WebAssembly.Instance);
});
