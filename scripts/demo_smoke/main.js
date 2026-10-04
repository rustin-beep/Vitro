// demo_smoke：demo 页预置用例的协议级判定闸（2026-09-30 审阅 P1-2 立闸）。
//
// 背景（03-D17 形态）：demo 的静态资产（HTML/JS/CSS）不在任何既有闸的扫描
// 面内——页面字段名写错、golden 数字漂移、用例坏掉都全绿。本闸把探针固化：
// 对 cases.js 每个预置用例实跑协议链，① golden 逐字节比对；② 页面渲染所
// 需的响应字段存在性（缺键即红——P1-2 的注入场景：out.total→out.totall
// 这类漂移当场红）。
//
// 形态先例：scripts/wasm_gateway/host.js（同为 node 零依赖判定脚本、同为
// wasm-gc 宿主、同走 js-string builtins 契约；Go 判定纪律在 wasm 宿主场景
// 由 node 先例豁免）。
//
// 自报口径（稳定单行，勿改）：demo_smoke: N 用例 (PASS x / FAIL y)
// J9 证红（已留痕）：篡改 cases.js 任一 golden 字符 → exit 1，还原复绿。
//
// 用法：node scripts/demo_smoke/main.js [--wasm <path>]
//   产物默认取 release 形态（回落 debug 同 host.js）——CI 在 wasm-gc
//   构建步之后跑，复用同一产物。

"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

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

let pass = 0, fail = 0;
const failures = [];
function check(cond, label, detail) {
  if (cond) { pass++; console.log(`  PASS  ${label}`); }
  else { fail++; failures.push(label); console.log(`  FAIL  ${label}  ${detail || ""}`); }
}

// Latin-1 字节域 → UTF-8 还原（demo/app.js 同款口径——两处必须一致）
function latin1ToUtf8(delta) {
  if (!delta) return "";
  const bytes = new Uint8Array(delta.length);
  for (let i = 0; i < delta.length; i++) bytes[i] = delta.charCodeAt(i) & 0xff;
  return new TextDecoder("utf-8").decode(bytes);
}

// ── 加载 DEMO_CASES（cases.js 是浏览器脚本，const 无导出——vm 执行取值）──
function loadCases() {
  const src = fs.readFileSync(path.join(repoRoot, "demo/cases.js"), "utf8");
  const ctx = {};
  vm.createContext(ctx);
  vm.runInContext(src + "\n;DEMO_CASES;", ctx);
  return ctx.DEMO_CASES || vm.runInContext("DEMO_CASES", ctx);
}

// ── 渲染必需字段（demo/app.js 消费面的字段清单；缺键 = 页面静默 undefined）──
const REQUIRED = {
  compile: ["ok", "diagnostics", "preprocessor_trace"],
  run: ["status", "return_value", "trap", "waiting_input", "steps_executed"],
  output: ["delta", "cursor", "total", "stream"],
  memory: [
    "regions", "region_counts", "free_list", "quarantine",
    "heap_base", "heap_offset", "alloc_counter",
  ],
  regionEntry: ["addr", "size", "name", "ty", "is_heap", "is_freed", "alloc_line", "alloc_by", "kind"],
  quarantine: ["bytes", "budget", "blocks"],
  regionCounts: ["global", "stack", "heap"],
};

function assertKeys(obj, keys, label) {
  const missing = keys.filter((k) => !(k in obj));
  check(missing.length === 0, `${label} 字段齐全`, "缺: " + missing.join(","));
}

(async () => {
  if (!fs.existsSync(wasmPath)) {
    console.error(`[demo_smoke] 找不到产物: ${wasmPath}——先 cd moonbit && moon build --release --target wasm-gc gateway/wasm`);
    process.exit(2);
  }
  const cases = loadCases();
  check(Array.isArray(cases) && cases.length >= 10, `cases 加载（${cases ? cases.length : 0} 个）`, "cases.js 解析失败？");

  const mod = new WebAssembly.Module(fs.readFileSync(wasmPath), { builtins: ["js-string"], importedStringConstants: "_" });
  const g = (await WebAssembly.instantiate(mod, {})).exports;
  let id = 0;
  const inv = (o) => JSON.parse(g.invoke(JSON.stringify({ id: ++id, ...o })));
  const body = (r) => (r && r.result !== undefined ? r.result : r);

  for (const k of cases) {
    g.reset();
    // compile（files 或 source 形态，与 app.js 一致）
    const comp = body(inv({
      method: "compile",
      params: k.files ? { files: k.files.map((f) => ({ filename: f.filename, source: f.source })) }
                      : { source: k.source },
    }));
    assertKeys(comp, REQUIRED.compile, `[${k.id}] compile`);
    const runResp = body(inv({ method: "run", params: k.argv ? { argv: k.argv } : {} }));
    assertKeys(runResp, REQUIRED.run, `[${k.id}] run`);

    if (runResp.waiting_input) {
      const fed = body(inv({ method: "input.feed", params: { text: (k.stdin || "42") + "\n" } }));
      Object.assign(runResp, fed);
    }
    const out = body(inv({ method: "output.delta", params: { cursor: 0, stream: "stdout" } }));
    assertKeys(out, REQUIRED.output, `[${k.id}] output.delta`);
    const stdout = latin1ToUtf8(out.delta || "");

    const mem = body(inv({ method: "memory.regions" }));
    assertKeys(mem, REQUIRED.memory, `[${k.id}] memory.regions`);
    assertKeys(mem.region_counts || {}, REQUIRED.regionCounts, `[${k.id}] region_counts`);
    assertKeys(mem.quarantine || {}, REQUIRED.quarantine, `[${k.id}] quarantine`);
    check((mem.regions || []).length === 0 || Object.keys(mem.regions[0]).length >= REQUIRED.regionEntry.length - 1,
          `[${k.id}] region 条目字段`, JSON.stringify((mem.regions || [])[0] || {}).slice(0, 100));

    // golden 逐字节比对（referenceOutput / referenceTrap 两类）
    if (k.referenceKind === "stdout" && k.referenceOutput !== undefined) {
      check(stdout === k.referenceOutput,
            `[${k.id}] golden 逐字节一致`,
            `期望 ${JSON.stringify(k.referenceOutput)} 实得 ${JSON.stringify(stdout)}`);
    }
    if (k.referenceKind === "trap" && k.referenceTrap !== undefined) {
      check((runResp.trap || "").includes(k.referenceTrap),
            `[${k.id}] trap 含 ${k.referenceTrap}`,
            `实得 ${(runResp.trap || "").slice(0, 60)}`);
    }
    // 状态与用例语义一致性
    if (k.referenceKind === "trap") {
      check(runResp.status === "trap", `[${k.id}] 状态 = trap`, "实得 " + runResp.status);
    } else if (k.stdin === undefined && !k.files) {
      // 无交互用例应自行跑到 finished（waiting 只允许显式 stdin 演示用例）
      check(runResp.status === "finished" || runResp.waiting_input === true,
            `[${k.id}] 状态可终`, "实得 " + runResp.status);
    }
  }

  // 协议方法面（错误帧自报清单为单源）+ 页面标题计数对账：
  // gateway 方法数 == 页面宣称数；消费数 == app.js 的 method: "..." 去重数。
  // （审阅 P2-2：原 methodCount 变量算了从不参与断言——守护空转，本批接上）
  const bad = body(inv({ method: "no.such" }));
  const errMsg = (bad.error && bad.error.message) || JSON.stringify(bad);
  check(bad.ok === false, "未知方法回 protocol 错误帧", errMsg.slice(0, 80));
  const mListMatch = errMsg.match(/已接：([\s\S]+)$/);
  // 斜杠并写项（session.create/reset/destroy）按展开计；dump 族提示以全角
  // 分号开头且不在"已接："直报段——按分号截断排除（J9 证红抓过 21 的过计形态）
  const methodCount = mListMatch
    ? mListMatch[1].split(/[；;]/)[0].split(/[、/]/).map((x) => x.trim()).filter(Boolean).length
    : 0;
  check(methodCount === 21, "gateway 方法面 = 21（错误帧自报）", "实得 " + methodCount);
  const pageTitle = fs.readFileSync(path.join(repoRoot, "demo/index.html"), "utf8");
  const claim = pageTitle.match(/方法面（(\d+) 个，本页消费 (\d+) 个）/);
  check(!!claim && Number(claim[1]) === methodCount, "页面方法面计数与 gateway 一致",
    claim ? "页面写 " + claim[1] + " / 实际 " + methodCount : "页面未找到方法面计数句");
  // 拆分批（2026-10-04，refs #28）：app.js → 入口 + demo/js/ 十模块 ESM——
  // method 消费面扫入口 + 全部模块（逐字迁移，散布面等价）
  const jsDir = path.join(repoRoot, "demo/js");
  const appSrc = [path.join(repoRoot, "demo/app.ts")]
    .concat(fs.readdirSync(jsDir).filter((f) => f.endsWith(".ts")).sort().map((f) => path.join(jsDir, f)))
    .map((f) => fs.readFileSync(f, "utf8"))
    .join("\n");
  const consumed = new Set([...appSrc.matchAll(/method: "([a-z._]+)"/g)].map((m) => m[1]));
  check(!!claim && Number(claim[2]) === consumed.size, "页面消费计数与 app.js 实消费一致",
    claim ? "页面写 " + claim[2] + " / 实际 " + consumed.size : "—");

  const total = pass + fail;
  console.log();
  console.log(`demo_smoke: ${total} 用例项 (PASS ${pass} / FAIL ${fail})`);
  if (fail > 0) { console.log("FAILED: " + failures.join(" | ")); process.exit(1); }
  console.log("demo_smoke 全部通过");
})().catch(e => { console.error("[demo_smoke] 异常:", e); process.exit(2); });
