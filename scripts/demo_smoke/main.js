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
  compile: ["ok", "diagnostics", "preprocessor_trace", "algorithm_matches"],
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
  check(methodCount === 23, "gateway 方法面 = 23（错误帧自报，icons.get 随 #27 上线）", "实得 " + methodCount);
  const pageTitle = fs.readFileSync(path.join(repoRoot, "demo/index.html"), "utf8");
  const claim = pageTitle.match(/方法面（(\d+) 个，本页消费 (\d+) 个）/);
  check(!!claim && Number(claim[1]) === methodCount, "页面方法面计数与 gateway 一致",
    claim ? "页面写 " + claim[1] + " / 实际 " + methodCount : "页面未找到方法面计数句");
  // 拆分批（2026-10-04，refs #28）：app.js → 入口 + demo/js/ 十一模块 ESM——
  // method 消费面扫入口 + 全部模块（逐字迁移，散布面等价）
  const jsDir = path.join(repoRoot, "demo/js");
  const appSrc = [path.join(repoRoot, "demo/app.ts")]
    .concat(fs.readdirSync(jsDir).filter((f) => f.endsWith(".ts")).sort().map((f) => path.join(jsDir, f)))
    .map((f) => fs.readFileSync(f, "utf8"))
    .join("\n");
  const consumed = new Set([...appSrc.matchAll(/method: "([a-z._]+)"/g)].map((m) => m[1]));
  check(!!claim && Number(claim[2]) === consumed.size, "页面消费计数与 app.js 实消费一致",
    claim ? "页面写 " + claim[2] + " / 实际 " + consumed.size : "—");

  // ── step 族字段契约（2026-10-04 审阅 P2-3：demo_smoke 原先零触 step 族，
  // types.ts 的 wire 声明无任何机判——探针留 tmp/review_20261004/ 本批固化）。
  // 断言口径：StepPayload 顶层 = 协议 v0.1 十四字段白名单键集全等（多键少键
  // 都红，突变 heatmap_line→linee 已证红）；嵌套结构 = 必备键在
  // （array_snapshots 实测多一个未声明 truncated，属「只声明消费面」合法
  // 形态，不做键集全等）。累积推批形态 = 探针 probe2 同款（U1#1 一帧发布
  // 缓冲：首批可为空）。
  {
    const k = cases.find((c) => c.id === "bubble") || cases.find((c) => !c.files && c.stdin === undefined);
    g.reset();
    body(inv({ method: "session.create" }));
    body(inv({ method: "config.set", params: { max_steps: 10000000, call_depth_limit: 10000, deterministic: true } }));
    const comp = body(inv({ method: "compile", params: { source: k.source } }));
    check(comp.ok === true, `[${k.id}] step 面编译 ok`, JSON.stringify(comp.diagnostics || []).slice(0, 80));
    const begin = body(inv({ method: "step.begin", params: {} }));
    check(begin && begin.ok !== false, "step.begin 返回帧", JSON.stringify(begin).slice(0, 80));
    let payloads = [];
    let lastBatch = null;
    for (let i = 0; i < 60 && payloads.length < 12; i++) {
      lastBatch = body(inv({ method: "step.next", params: {} }));
      if (lastBatch.payloads) payloads = payloads.concat(lastBatch.payloads);
      if (lastBatch.finished || lastBatch.trapped) break;
    }
    check(payloads.length > 0, "step.next 累积产出帧", "推尽 60 批零帧——step 族断链");
    if (payloads.length > 0 && lastBatch) {
      for (const f of ["payloads", "finished", "trapped", "trap_message"]) {
        check(f in lastBatch, `step.next 批字段 ${f}`, "缺键");
      }
      const want14 = ["accessed_vars", "algorithm_step", "array_snapshots", "call_stack", "code_line",
        "func_name", "heatmap_count", "heatmap_line", "local_vars", "pointer_snapshots",
        "root_cause_hint", "semantic_label", "step_index", "vis_events"].sort().join(",");
      check(Object.keys(payloads[0]).sort().join(",") === want14,
        "StepPayload 顶层键集 = 协议 v0.1 十四字段白名单", "实得 " + Object.keys(payloads[0]).sort().join(","));
      const withVars = payloads.find((p) => p.local_vars && p.local_vars.length);
      if (withVars) {
        for (const f of ["name", "addr", "is_local", "ty_name", "value"]) {
          check(f in withVars.local_vars[0], `LocalVar 字段 ${f}`, "缺键");
        }
      }
      const withStack = payloads.find((p) => p.call_stack && p.call_stack.length);
      if (withStack) {
        for (const f of ["func_name", "return_line"]) {
          check(f in withStack.call_stack[0], `CallFrame 字段 ${f}`, "缺键");
        }
      }
      const arrSnap = payloads.find((p) => p.array_snapshots && p.array_snapshots.length);
      if (arrSnap) {
        for (const f of ["name", "element_ty", "elements"]) {
          check(f in arrSnap.array_snapshots[0], `ArraySnapshot 字段 ${f}`, "缺键");
        }
      } else {
        check(false, "array_snapshots 帧可采（数组柱状图消费面）", "累积帧未见非空数组快照——用例或引擎面变更？");
      }
    }
  }

  // ── 算法侧栏数据契约（2026-10-04，refs #28）─────────────────────
  // algorithms.js = scripts/gen_demo_algorithms 机判产物。本段三断言：
  // ① 族集与 rules.json（teaching 43 族权威）一致——生成器漂移/手改即红；
  // ② 每族源码 compile ok（43 次，快）；
  // ③ step 标注命中抽验（golden 源/extra 源/math 各一：bubble_sort /
  //    linked_list_append / gcd——全量 43×4000 批太重，完备性由生成器
  //    分组并集断言兜底）。
  // 已知豁免（引擎 code_line 基准偏移致 infer 拿错行文本——两侧同病，
  // 修复挂 Rust 退役后，与差异台账同类）：is_prime、threaded_binary_tree
  // 两族无帧标注，侧栏条件渲染不显示。
  {
    const rulesPath = path.join(repoRoot, "scripts/teaching_annotation_diff/rules.json");
    const rules = JSON.parse(fs.readFileSync(rulesPath, "utf8"));
    const algoSrc = fs.readFileSync(path.join(repoRoot, "demo/algorithms.js"), "utf8");
    const vctx = {};
    vm.createContext(vctx);
    vm.runInContext(algoSrc + "\n;DEMO_ALGORITHMS;", vctx);
    const DEMO = vm.runInContext("DEMO_ALGORITHMS", vctx);
    const items = (DEMO.groups || []).flatMap((g) => g.items || []);
    const ids = new Set(items.map((i) => i.id));
    const want = new Set(rules.migrated_algorithms);
    const missR = [...want].filter((x) => !ids.has(x));
    const extraR = [...ids].filter((x) => !want.has(x));
    check(missR.length === 0 && extraR.length === 0,
      "算法侧栏族集 = rules.json 43 族（机判对账）",
      "缺: " + missR.join(",") + " / 多: " + extraR.join(","));
    check(items.length === want.size, `侧栏族数 ${want.size}`, "实得 " + items.length);
    // 全量纳入（2026-10-04 用户拍板）：43 族 + 变体 + 扩展练习 == templates/*.c
    // 82 全集（Set 语义）；变体/扩展源同样 compile ok
    const xitems = (DEMO.groups || []).flatMap((g) => g.xitems || []);
    const varSrcs = items.flatMap((i) => (i.variants || []).map((v) => ({ tpl: v.tpl, source: v.source })));
    const tplNames = new Set([
      ...items.filter((i) => i.template !== "extra").map((i) => i.template),
      ...varSrcs.map((v) => v.tpl),
      ...xitems.map((x) => x.id),
    ]);
    const diskTpls = fs.readdirSync(path.join(repoRoot, "templates"))
      .filter((t) => fs.existsSync(path.join(repoRoot, "templates", t, "source.c")));
    const diskSet = new Set(diskTpls);
    const ghost = [...tplNames].filter((t) => !diskSet.has(t));
    const notIn = diskTpls.filter((t) => !tplNames.has(t));
    check(ghost.length === 0 && notIn.length === 0,
      "侧栏模板全集对账 = templates/*.c（82 面，Set 语义）",
      "幽灵: " + ghost.join(",") + " / 未纳: " + notIn.join(","));
    let vFail = [];
    for (const v of varSrcs.concat(xitems.map((x) => ({ tpl: x.id, source: x.source })))) {
      g.reset();
      body(inv({ method: "session.create" }));
      const c = body(inv({ method: "compile", params: { source: v.source } }));
      if (c.ok !== true) vFail.push(v.tpl);
    }
    check(vFail.length === 0, `变体+扩展源全部编译通过（${varSrcs.length + xitems.length} 份）`, "失败: " + vFail.join(","));
    let compFail = [];
    let matchHit = null;
    for (const it of items) {
      g.reset();
      body(inv({ method: "session.create" }));
      const c = body(inv({ method: "compile", params: { source: it.source } }));
      if (c.ok !== true) compFail.push(it.id);
      if (!matchHit && Array.isArray(c.algorithm_matches)) {
        const m = c.algorithm_matches.find((x) => x.name === it.id && x.display_name && x.func_name);
        if (m) matchHit = m;
      }
    }
    check(compFail.length === 0, "43 族示例源码全部编译通过", "失败: " + compFail.join(","));
    // compile 帧 algorithm_matches 透出锚（2026-10-04 补——#36 最小路径：
    // teaching detect 的 wire 出口；正向形态 = 某族示例的 compile 帧含同名
    // match 且带 display_name/func_name/confidence——agent 问「什么算法」自此有出口）
    check(!!matchHit && matchHit.confidence > 0,
      "compile 帧 algorithm_matches 正向透出（teaching detect wire 出口）",
      "43 族示例零命中——emitter 或 detect 链路回归");
    // 命中抽验（2026-10-04 审阅 P3-④ 扩面：七组各一代表——3 族抽验不保证
    // 每组标注链路真命中；全量 43×4000 批过重，每组代表 + 豁免族反向锚）
    const spot = ["bubble_sort", "binary_search", "bfs", "bst_insert", "threaded_binary_tree", "linked_list_append", "string_match_kmp", "gcd"];
    // threaded_binary_tree 2026-10-04 反向锚首跑翻红移出豁免：extra 源函数名
    // inorderThreadedTree 命中 detect 且该形态行号偏移不显——确有标注
    const exempt = new Set(["is_prime"]);
    const spotRun = (algo) => {
      const it = items.find((x) => x.id === algo);
      g.reset();
      body(inv({ method: "session.create" }));
      body(inv({ method: "config.set", params: { max_steps: 2000000, call_depth_limit: 10000, deterministic: true, quarantine_budget: 262144 } }));
      body(inv({ method: "compile", params: { source: it.source } }));
      body(inv({ method: "run", params: {} }));
      body(inv({ method: "step.begin", params: {} }));
      let found = false;
      for (let i = 0; i < 1200 && !found; i++) {
        const b = body(inv({ method: "step.next", params: {} }));
        for (const p of b.payloads || []) {
          if (p.algorithm_step && p.algorithm_step.algorithm_name === algo) { found = true; break; }
        }
        if (b.finished || b.trapped) break;
      }
      return found;
    };
    for (const algo of spot) {
      check(spotRun(algo), `[${algo}] step 标注命中抽验（七组代表）`, "1200 批内无该族标注——生成器代表源或引擎链路回归");
    }
    // 豁免反向锚（2026-10-04 审阅 P3-④：恒真 Set 断言无牙——改实测两豁免族
    // 确无标注（引擎 code_line 基准偏移 issue #34 的客观锚；修复后此断言翻红
    // 逼移除豁免并加回命中抽验——豁免转绿即红）
    for (const algo of exempt) {
      check(!spotRun(algo), `[${algo}] 豁免族确无标注（issue #34 行号偏移在案）`,
        "豁免族出现标注 = 引擎行号修复已上线——应移除豁免并把两族加回命中抽验");
    }
  }

  // ── seek / breakpoints.set 契约（2026-10-04，refs #28 键族层消费）──
  {
    const k = cases.find((c) => c.id === "hello") || cases[0];
    g.reset();
    body(inv({ method: "session.create" }));
    body(inv({ method: "config.set", params: { max_steps: 100000, call_depth_limit: 10000, deterministic: true } }));
    body(inv({ method: "compile", params: { source: k.source } }));
    body(inv({ method: "run", params: {} }));
    body(inv({ method: "step.begin", params: {} }));
    for (let i = 0; i < 10; i++) { const b = body(inv({ method: "step.next", params: {} })); if (b.finished) break; }
    const sk = body(inv({ method: "seek", params: { step: 3 } }));
    check(sk && sk.success === true && sk.payload && typeof sk.payload.step_index === "number",
      "seek{step:3} 返回引擎权威帧（success+payload.step_index）", JSON.stringify(sk).slice(0, 80));
    const badSk = body(inv({ method: "seek", params: {} }));
    check(badSk && badSk.ok === false, "seek 缺参回协议错误帧（fail loud）", JSON.stringify(badSk).slice(0, 80));
    const pg = body(inv({ method: "payload.get", params: { step: 0 } }));
    check(pg && Array.isArray(pg.payloads) && "cache_start_step" in pg && "max_collected_step" in pg,
      "payload.get{step:0} 窗口查询三键（payloads/cache_start_step/max_collected_step）", Object.keys(pg || {}).join(","));
    const bp = body(inv({ method: "breakpoints.set", params: { lines: [4] } }));
    check(bp && Array.isArray(bp.lines) && bp.lines.includes(4),
      "breakpoints.set{lines:[4]} 先清后设回显", JSON.stringify(bp));
    // 先清验证（2026-10-04 审阅 P3-④：断言名写「先清后设」却未验先清——
    // 二次 set 后回显须只含新行集（含旧行 = 清空失效）
    const bp2 = body(inv({ method: "breakpoints.set", params: { lines: [5] } }));
    check(bp2 && Array.isArray(bp2.lines) && bp2.lines.includes(5) && !bp2.lines.includes(4),
      "breakpoints.set 二次设回显只含新行（先清生效）", JSON.stringify(bp2));
  }

  const total = pass + fail;
  console.log();
  console.log(`demo_smoke: ${total} 用例项 (PASS ${pass} / FAIL ${fail})`);
  if (fail > 0) { console.log("FAILED: " + failures.join(" | ")); process.exit(1); }
  console.log("demo_smoke 全部通过");
})().catch(e => { console.error("[demo_smoke] 异常:", e); process.exit(2); });
