// wasm-gc gateway 的 Node 宿主驱动 + 冒烟（S7 批五号，R11 证据链）。
//
// 用法：node scripts/wasm_gateway/host.js [--wasm <path>]
//   产物默认取 moonbit/_build/wasm-gc/release/build/gateway/gateway.wasm
//   （缺省回落 debug 形态——体积断言只对 release 生效，见下）。
//
// 宿主契约（与 gateway/moon.pkg 的 use-js-builtin-string 对偶）：
//   new WebAssembly.Module(buf, { builtins: ['js-string'], importedStringConstants: '_' })
//   ——String 参数/返回直传，零手写 imports（产物 imports 实测为空）。
//
// R11 证据链要求（重建：真 E3070/E3061 断言 + 体积断言 + 产物更名，
// 每条护栏先证红）：本脚本的断言不是「模块能实例化」级冒烟，而是
// 走 NDJSON 全链（compile→run→output.delta→memory.regions→input.feed
// 续跑）+ 两条真教学 trap 断言（E3070 strcpy 越界 / E3061 NULL 解引用
// 受检）+ 4 导出面 + 体积上限（防依赖性膨胀回归）。
//
// 自报口径（CI 断言口径，格式稳定勿改；facts 键未接——如需机器采集在 facts.go runKeys 登记）：
//   wasm_gateway 冒烟: N (PASS x / FAIL y)

"use strict";
const fs = require("fs");
const path = require("path");
const { compileGateway, stringConstsOf, instantiateGateway } = require("../wasm_load.js");

const args = process.argv.slice(2);
let wasmPath = "";
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--wasm" && i + 1 < args.length) wasmPath = args[i + 1];
}
const repoRoot = path.resolve(__dirname, "../..");
if (!wasmPath) {
  const release = path.join(repoRoot, "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm");
  const debug = path.join(repoRoot, "moonbit/_build/wasm-gc/debug/build/gateway/wasm/wasm.wasm");
  wasmPath = fs.existsSync(release) ? release : debug;
}
const isRelease = wasmPath.includes(path.join("release", "build"));

let pass = 0, fail = 0;
const failures = [];
function check(cond, label, detail) {
  if (cond) { pass++; console.log(`  PASS  ${label}`); }
  else { fail++; failures.push(label); console.log(`  FAIL  ${label}  ${detail || ""}`); }
}

(async () => {
  if (!fs.existsSync(wasmPath)) {
    console.error(`[wasm-gateway] 找不到产物: ${wasmPath}——先 cd moonbit && moon build --release --target wasm-gc gateway`);
    process.exit(2);
  }
  const buf = fs.readFileSync(wasmPath);
  console.log(`产物: ${wasmPath}（${buf.length} bytes, ${isRelease ? "release" : "debug"}）`);

  // ── 4 导出面（F-5）──
  const mod = compileGateway(buf);
  const exportNames = WebAssembly.Module.exports(mod).map(e => e.name);
  check(exportNames.includes("invoke") && exportNames.includes("reset") &&
        exportNames.includes("protocol_version") && exportNames.includes("engine_version"),
        "4 函数导出面（invoke/reset/protocol_version/engine_version）", exportNames.join(","));
  // 「零 imports」在字节层不成立（2026-09-29 审阅 P3 勘误）：import 段含
  // "_" 模块的字符串字面量常量（新版 V8 的高层 API 不计入，旧版/字节层
  // 可见）——正确口径 = 零**功能性** imports（除 "_" 外无任何模块依赖，
  // js-string 内建由宿主编译选项供给）。#126 起口径走裸编译枚举（选项
  // 编译下 node>=23 的 imports() 报空——恒绿弱断言；裸编译列出全量条目
  // 后再滤，真断言）
  const functionalImports = WebAssembly.Module.imports(new WebAssembly.Module(buf))
    .filter(i => i.module !== "_" && i.module !== "wasm:js-string");
  check(functionalImports.length === 0,
        "零功能性 imports（除字符串常量/内建外无依赖）",
        JSON.stringify(functionalImports));
  // #126 供给面锚：常量枚举非空（产物形态在意外联回归——如 import 段被
  // 剥离则此处红，提示装载层与产物形态失配）+ 显式供给实例化成功
  const consts = stringConstsOf(buf);
  check(Object.keys(consts).length > 0,
        '"_" 常量供给面存在（枚举 ' + Object.keys(consts).length + " 条）");
  // 统一装载器实例化（#126：显式 name→name 供给——node 22 严格校验的
  // 真因修复；旧两段式 Proxy 兜底（返回函数 = illegal cast）已删勿回退）
  const inst = await instantiateGateway(buf);
  const g = inst.exports;

  // protocol_version 锚：#90 v0.2 首批激活（code_file）升格（2026-10-17
  // 云端 CI 红收口——原锚 v0.1 在 #90 后陈旧）；单源 = @protocol.SCHEMA_VERSION
  check(g.protocol_version() === "v0.2", "protocol_version = v0.2", g.protocol_version());
  // ENGINE_VERSION ↔ moon.mod 版本失联锚（2026-09-29 审阅 P3-5）：
  // 读 moon.mod 的 version 逐字对比——发版忘 bump 即红
  const modText = fs.readFileSync(path.join(repoRoot, "moonbit/moon.mod"), "utf8");
  const modVer = (modText.match(/version\s*=\s*"([^"]+)"/) || [])[1];
  check(g.engine_version() === modVer,
        "engine_version == moon.mod version（失联即红）", `${g.engine_version()} vs ${modVer}`);

  // ── NDJSON 全链（与 serve_smoke 同语义的 wasm 宿主面）──
  function invoke(line) { return g.invoke(line); }
  function parse(line) { return JSON.parse(line); }

  // compile + run + output.delta
  const src = '#include <stdio.h>\nint main(){ printf("hi"); return 7; }\n';
  const jsrc = JSON.stringify(src);
  const r1 = parse(invoke(`{"id":1,"method":"compile","params":{"source":${jsrc}}}`));
  check(r1.ok === true && r1.result.ok === true, "compile 成功", JSON.stringify(r1).slice(0, 120));
  const r2 = parse(invoke(`{"id":2,"method":"run"}`));
  check(r2.result.status === "finished" && r2.result.return_value === 7,
        "run finished 返回 7", JSON.stringify(r2).slice(0, 120));
  const r3 = parse(invoke(`{"id":3,"method":"output.delta","params":{"cursor":0,"stream":"stdout"}}`));
  check(r3.result.delta === "hi" && r3.result.cursor === 2,
        "output.delta = hi（stdout 通道）", JSON.stringify(r3).slice(0, 120));

  // input.feed 续跑链（Interactive 默认 → waiting → feed → finished）
  const src2 = '#include <stdio.h>\nint main(){ int n; scanf("%d", &n); printf("got %d", n); return 0; }\n';
  invoke(`{"id":4,"method":"compile","params":{"source":${JSON.stringify(src2)}}}`);
  const r5 = parse(invoke(`{"id":5,"method":"run"}`));
  check(r5.result.waiting_input === true, "scanf 无输入 → waiting_input", JSON.stringify(r5).slice(0, 120));
  const r6 = parse(invoke(`{"id":6,"method":"input.feed","params":{"text":"42\\n"}}`));
  check(r6.result.status === "finished" && r6.result.return_value === 0,
        "input.feed 续跑 finished", JSON.stringify(r6).slice(0, 120));

  // memory.regions（C2 三段式）
  const r7 = parse(invoke(`{"id":7,"method":"memory.regions"}`));
  const counts = r7.result.region_counts;
  check(counts && typeof counts.global === "number" && typeof counts.stack === "number" &&
        typeof counts.heap === "number", "memory.regions 三段式计数", JSON.stringify(r7.result).slice(0, 120));

  // ── 真 trap 断言（R11：E3070 / E3061）──
  // E3070：strcpy 目标栈缓冲容量不足——strcpy 校验堆块容量 + 栈缓冲容量
  invoke(`{"id":8,"method":"reset"}`);
  const srcE3070 = '#include <string.h>\nint main(){ char buf[4]; strcpy(buf, "hello world"); return 0; }\n';
  invoke(`{"id":9,"method":"compile","params":{"source":${JSON.stringify(srcE3070)}}}`);
  const r10 = parse(invoke(`{"id":10,"method":"run"}`));
  check(r10.result.status === "trap" && r10.result.trap.includes("E3070"),
        "E3070 真 trap（strcpy 栈缓冲越界）", JSON.stringify(r10.result).slice(0, 160));

  // E3061：NULL 解引用受检（*p = 1 形态经受检访存单入口）
  invoke(`{"id":11,"method":"reset"}`);
  const srcE3061 = '#include <stdlib.h>\nint main(){ int* p = NULL; *p = 1; return 0; }\n';
  invoke(`{"id":12,"method":"compile","params":{"source":${JSON.stringify(srcE3061)}}}`);
  const r13 = parse(invoke(`{"id":13,"method":"run"}`));
  check(r13.result.status === "trap" && r13.result.trap.includes("NULL"),
        "E3061 真 trap（NULL 解引用受检）", JSON.stringify(r13.result).slice(0, 160));

  // reset 导出直调（无方法帧场景）
  g.reset();
  const r14 = parse(invoke(`{"id":14,"method":"config.get"}`));
  check(r14.result.compiled === false, "reset() 导出清编译态", JSON.stringify(r14).slice(0, 120));

  // 未知方法 → protocol 错误帧（协议演化纪律 ②）
  const r15 = parse(invoke(`{"id":15,"method":"no.such"}`));
  check(r15.ok === false && r15.error.kind === "protocol", "未知方法回 protocol 错误帧", JSON.stringify(r15).slice(0, 120));

  // shutdown 帧
  const r16 = parse(invoke(`{"id":16,"method":"shutdown"}`));
  check(r16.result.shutdown === true, "shutdown 帧", "");

  // ── 体积断言（release 形态；R11——防依赖性膨胀回归）──
  if (isRelease) {
    check(buf.length < 1_500_000, `体积上限 1.5MB（实测 ${buf.length}）`, "");
  } else {
    console.log(`  SKIP  体积断言（debug 形态 ${buf.length} bytes——release 才判）`);
  }

  const total = pass + fail;
  console.log();
  console.log(`wasm_gateway 冒烟: ${total} (PASS ${pass} / FAIL ${fail})`);
  if (fail > 0) { console.log(`FAILED: ${fail} -> ${failures.join(" | ")}`); process.exit(1); }
  console.log("wasm-gc gateway 冒烟全部通过");
})().catch(e => { console.error("[wasm-gateway] 异常:", e); process.exit(2); });
