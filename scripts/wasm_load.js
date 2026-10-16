"use strict";
// gateway wasm-gc 产物的统一装载器（#126 收口，2026-10-16）。
//
// 机制：产物的 import 段含 "_" 模块的字符串字面量常量（编译选项
// importedStringConstants 的外置形态，4000+ 条随源码演进）。node >= 23
// （V8 13+）对带 builtins 编译选项的模块自动容错供给（Module.imports()
// 报空即其表现——V8 视为已满足）；node 22 严格校验，宿主不显式供给即
// LinkError: Import #0 "_": module is not an object or function
// （#126 在 node 22.22.2 实测；node 25 行为矩阵 C 形态同报错可复现佐证）。
// 供给形态 = name→name 字符串映射：import 的 field 名本身就是常量值。
//
// 常量清单从「无选项裸编译」枚举——裸编译下 "_" 恒为普通 import（无内建
// 参与，标准行为），不依赖 V8 版本对选项编译 imports() 的差异处理。
// 产物若未来剥离常量段（#120 方向），枚举为 0、供给空对象亦无害
// （node >= 23 自动供给兜底）。
//
// 勿回退形态：host.js 旧两段式兜底用 Proxy 返回函数 → V8 illegal cast
// （2026-09-29 勘误「Node 22 不工作」的真因是供给形态错误，非版本不兼容）。
//
// 消费方：scripts/vitro_cli/main.js、scripts/wasm_gateway/host.js、
// scripts/demo_smoke/main.js（demo/js/gw.ts 浏览器侧 Chrome/Edge 自动
// 供给，留前端域）。MIN_NODE 哨兵不在本层（launcher/vitro_cli 的版本
// 门是 #126 连带决定，另立拍板）。

function compileGateway(buf) {
  return new WebAssembly.Module(buf, {
    builtins: ["js-string"], importedStringConstants: "_",
  });
}

function stringConstsOf(buf) {
  const consts = {};
  const bare = new WebAssembly.Module(buf);
  for (const imp of WebAssembly.Module.imports(bare)) {
    if (imp.module === "_") consts[imp.name] = imp.name;
  }
  return consts;
}

async function instantiateGateway(buf) {
  const mod = compileGateway(buf);
  return WebAssembly.instantiate(mod, { _: stringConstsOf(buf) });
}

module.exports = { compileGateway, stringConstsOf, instantiateGateway };
