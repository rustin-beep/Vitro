"use strict";
// vitro 统一 CLI 壳——wasm 臂（#49 批一，2026-10-06）
//
// 形态：gateway wasm-gc 产物的 Node 宿主壳。四子命令（run/compile/step/api）
// 参数面与 rc 五值表对齐 native vitro.exe（CLI_PROTOCOL_V1 spec 单源）；
// launcher（scripts/bin/vitro|.cmd）默认调本壳，node 缺失/版本不足
// （本文件 exit 3）降级 native exe。
//
// 通道契约（与 native 的同形基础——差异消灭在源头，非 canonicalize）：
//   - stdout：output.delta stdout 的 delta 是 Latin-1 折回形态（字节域
//     既定口径），本壳 Buffer.from(delta,'latin1') 逆折回落原始字节——
//     与 native write_stdout（C stub fwrite 原样字节）逐字节一致；
//   - note：output.delta note 已是 UTF-8 解码原文（gateway 侧
//     utf8_text_partial 修复），逐行 `// NOTE ` 前缀——与 native 同形；
//   - trap/exit 标记行：run 帧 trap/return_value 字段（与 native 同源
//     vm.error/ret）；
//   - compile 诊断三级行：compile 帧 diagnostics[].severity 分支渲染。
//
// backend 标注：启动 stderr 恒一行 `[vitro] backend=wasm (node <ver>)`
// （launcher 降级臂对称发 backend=native）；run --json 事件行另带
// backend 字段；api 帧透传不动（协议纯净，断言走 stderr 行）。
//
// 退出码（spec §2）：0=正常 / 1=编译错 / 2=trap / 3=步数超限（run 帧
// steps_executed == max_steps 值判——到达即停，与 cli_run_json 同口径）
// / 4=用法/IO。

const fs = require("fs");
const path = require("path");

const MIN_NODE = 25;
const [maj] = process.versions.node.split(".").map(Number);
if (maj < MIN_NODE) {
  process.stderr.write(
    `[vitro] node ${process.versions.node} < ${MIN_NODE}（js-string builtins 需要）\n`,
  );
  process.exitCode = 3;
  return;
}

const REPO = path.join(__dirname, "..", "..");
const WASM = path.join(
  REPO, "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm",
);
const BACKEND = "wasm";
// run/step 的 config.set 全量（与 cli_run_json / cli_step 同值——rc=3 值判
// 依赖其中的 max_steps）
const RUN_CONFIG = {
  max_steps: 10000000, call_depth_limit: 10000, deterministic: true, quarantine_budget: 262144,
};

let inv;
let rawInvoke;
async function loadGateway() {
  const buf = fs.readFileSync(WASM);
  const mod = new WebAssembly.Module(buf, {
    builtins: ["js-string"], importedStringConstants: "_",
  });
  const inst = await WebAssembly.instantiate(mod, {});
  const g = inst.exports;
  let id = 0;
  rawInvoke = (frame) => JSON.parse(g.invoke(JSON.stringify(frame)));
  inv = (method, params) => rawInvoke({ id: ++id, method, params: params || {} });
}

function usageExit(code) {
  process.stderr.write(
    `用法: vitro <run|compile|step|api> [args]  （backend=${BACKEND}；协议契约见 docs/spec/CLI_PROTOCOL_V1.md）\n` +
    `  run <file.c> [--dump-memory out] [-i in] [--json] [-- <argv...>]\n` +
    `  compile <file.c | -> [--json]\n` +
    `  step <file.c | -> [--max-steps N] [--json|--summary]\n` +
    `  api <method> [params-json] | api --batch < frames.ndjson\n`,
  );
  throw new ExitNow(code);
}

// die = 立即退出语义（throw + 顶层 catch 设 exitCode——process.exit 与
// stdout 异步写竞态会触发 node libuv 断言，禁用）
class ExitNow extends Error {
  constructor(code) { super(`exit ${code}`); this.code = code; }
}
function die(msg, code) {
  process.stderr.write(msg + "\n");
  throw new ExitNow(code);
}

// ── 源收集：主文件 + quote-include 递归（wasm 无 include_reader，走
// compile{files} 内存 vfs——与 native include_reader 语义等价；seen 防
// 含守卫环的合法自引用库）──
function collectFiles(mainFile, stdinSrc) {
  const files = [];
  const seen = new Set();
  const walk = (p, name) => {
    if (seen.has(name)) return;
    seen.add(name);
    let src;
    try {
      src = fs.readFileSync(p, "utf8");
    } catch {
      return;
    }
    files.push({ filename: name, source: src });
    const re = /^[ \t]*#[ \t]*include[ \t]*"([^"]+)"/gm;
    let m;
    while ((m = re.exec(src)) !== null) {
      walk(path.join(path.dirname(p), m[1]), m[1]);
    }
  };
  if (stdinSrc !== undefined) {
    files.push({ filename: mainFile, source: stdinSrc });
    return files;
  }
  walk(mainFile, path.basename(mainFile));
  if (files.length === 0) {
    die(`// COMPILE-ERROR io 1:1 源文件不可读或为空：${mainFile}`, 4);
  }
  return files;
}

function readStdinText() {
  return fs.readFileSync(0, "utf8");
}

// 诊断三级行（compile_and_report 同形：severity → 前缀 + code 字段直用）
function renderDiagnostics(result, out) {
  const w = out || process.stdout;
  for (const d of result.diagnostics || []) {
    if (d.severity === "error") {
      w.write(`// COMPILE-ERROR ${d.code} ${d.line}:${d.column} ${d.message}\n`);
    }
  }
  for (const d of result.diagnostics || []) {
    if (d.severity === "warning") {
      w.write(`// COMPILE-WARNING ${d.code} ${d.line}:${d.column} ${d.message}\n`);
    }
  }
  for (const d of result.diagnostics || []) {
    if (d.severity === "hint") {
      w.write(`// COMPILE-HINT ${d.code} ${d.line}:${d.column} ${d.message}\n`);
    }
  }
}

const hasErrors = (result) => (result.diagnostics || []).some((d) => d.severity === "error");

// stdout 通道字节还原（Latin-1 折回 → 原始字节；尾换行保形与 native
// stdout_bytes_of 同形：空/无尾换行补一个）
function writeStdoutBytes(delta) {
  let buf = Buffer.from(delta, "latin1");
  if (buf.length === 0 || buf[buf.length - 1] !== 0x0a) {
    buf = Buffer.concat([buf, Buffer.from([0x0a])]);
  }
  process.stdout.write(buf);
}

// ── run ─────────────────────────────────────────────────────────
function parseRunArgs(args) {
  const ra = { file: "", dumpMem: "", stdinFile: "", jsonMode: false, argv: [] };
  let i = 0;
  let passthrough = false;
  while (i < args.length) {
    const a = args[i];
    if (passthrough) { ra.argv.push(a); i++; continue; }
    if (a === "--") { passthrough = true; }
    else if (a === "--json") { ra.jsonMode = true; }
    else if (a === "--dump-memory" && i + 1 < args.length) { ra.dumpMem = args[++i]; }
    else if (a === "-i" && i + 1 < args.length) { ra.stdinFile = args[++i]; }
    else if (!a.startsWith("-") || a === "-") {
      if (ra.file === "") { ra.file = a; }
      else if (a !== "-") { ra.argv.push(a); }
    }
    i++;
  }
  return ra;
}

async function cmdRun(args) {
  const ra = parseRunArgs(args);
  if (ra.file === "") {
    process.stderr.write("用法: run <file.c> [--dump-memory out.bin] [-i input.in] [-- <argv...>]\n");
    process.exitCode = 4;
    return;
  }
  if (ra.dumpMem !== "") {
    process.stderr.write(
      "// COMPILE-ERROR io 1:1 wasm 臂不支持 --dump-memory（协议无 1MB 映像导出面，spec §3 登记；映像联走 native 臂）\n",
    );
    process.exitCode = 4;
    return;
  }
  const stdinSrc = ra.file === "-" ? readStdinText() : undefined;
  if (ra.file !== "-" && stdinSrc === undefined) {
    // 预读校验（与 native「源文件不可读」同形）
    try { fs.accessSync(ra.file); } catch {
      die(`// COMPILE-ERROR io 1:1 源文件不可读或为空：${ra.file}`, 4);
    }
  }
  const files = collectFiles(ra.file, stdinSrc);

  inv("session.create");
  inv("config.set", RUN_CONFIG);
  const comp = inv("compile", { files });
  if (ra.jsonMode) {
    process.stdout.write(JSON.stringify({ type: "diag", backend: BACKEND, frame: comp }) + "\n");
  }
  if (!comp.ok || !comp.result.ok || hasErrors(comp.result)) {
    if (!ra.jsonMode) renderDiagnostics(comp.result || { diagnostics: [] });
    process.exitCode = 1;
    return;
  }
  // 成功路径的非错误级诊断（warning/hint）也渲染（native compile_and_report
  // 全量形态——诊断行在程序 stdout 之前；语料对拍首跑即抓漏：bsearch_basic
  // 的 H3057 void* 隐式转换提示此前 wasm 臂静默丢）
  if (!ra.jsonMode) renderDiagnostics(comp.result);
  // argv 恒下发（gateway 语义 = 全量含 argv[0]；零透传也发 [file]）
  const argvFull = [ra.file === "-" ? "main.c" : ra.file, ...ra.argv];
  const runParams = { argv: argvFull };
  // 无输入注入时 headless（batch）语义——对齐 native 文本模式（CLI vm 构造
  // 默认批模式，scanf 耗尽即 EOF 续跑）；gateway 会话缺省 Interactive 会
  // waiting_input 挂起（那是 serve/--json 面向交互的形态，语料对拍 scanf 族
  // 6 例实锤分叉）。--json 模式保持 gateway 原生形态（与 native --json 对齐）
  if (!ra.jsonMode) {
    runParams.batch_input = true;
  }
  if (ra.stdinFile !== "") {
    let text = "";
    try { text = fs.readFileSync(ra.stdinFile, "utf8"); } catch {
      die(`// COMPILE-ERROR io 1:1 输入文件不可读：${ra.stdinFile}`, 4);
    }
    if (!text.endsWith("\n")) text += "\n";
    runParams.input = text;
    runParams.batch_input = true;
  }
  const run = inv("run", runParams);
  if (ra.jsonMode) {
    process.stdout.write(JSON.stringify({ type: "run", backend: BACKEND, frame: run }) + "\n");
  }
  const outStd = inv("output.delta", { cursor: 0, stream: "stdout" });
  const outNote = inv("output.delta", { cursor: 0, stream: "note" });
  if (ra.jsonMode) {
    process.stdout.write(JSON.stringify({ type: "stdout", backend: BACKEND, frame: outStd }) + "\n");
    process.stdout.write(JSON.stringify({ type: "note", backend: BACKEND, frame: outNote }) + "\n");
  } else {
    writeStdoutBytes((outStd.result && outStd.result.delta) || "");
    const note = (outNote.result && outNote.result.delta) || "";
    for (const line of note.split("\n")) {
      if (line !== "") process.stdout.write(`// NOTE ${line}\n`);
    }
    if (run.result && run.result.trap) {
      process.stdout.write(`// TRAP ${run.result.trap}\n`);
    }
    if (run.result && run.result.return_value !== 0) {
      process.stdout.write(`// EXIT ${run.result.return_value}\n`);
    }
  }
  const status = run.result && run.result.status;
  if (status === "trap") {
    if (run.result.steps_executed >= RUN_CONFIG.max_steps) { process.exitCode = 3; return; }
    process.exitCode = 2;
    return;
  }
  process.exitCode = 0;
  return;
}

// ── compile ─────────────────────────────────────────────────────
async function cmdCompile(args) {
  let file = "";
  let jsonMode = false;
  for (const a of args) {
    if (a === "--json") jsonMode = true;
    else if ((!a.startsWith("-") || a === "-") && file === "") file = a;
  }
  if (file === "") {
    process.stderr.write("用法: compile <file.c> [--json]\n");
    process.exitCode = 4;
    return;
  }
  const stdinSrc = file === "-" ? readStdinText() : undefined;
  if (stdinSrc !== undefined && stdinSrc === "") {
    die("// COMPILE-ERROR io 1:1 源文件不可读或为空：-", 4);
  }
  const files = collectFiles(file, stdinSrc);
  const comp = inv("compile", { files });
  if (jsonMode) {
    process.stdout.write(JSON.stringify(comp) + "\n");
    process.exitCode = comp.ok && comp.result && comp.result.ok && !hasErrors(comp.result) ? 0 : 1;
    return;
  }
  renderDiagnostics(comp.result || { diagnostics: [] });
  if (hasErrors(comp.result || {})) { process.exitCode = 1; return; }
  process.stdout.write("// COMPILE-OK\n");
  process.exitCode = 0;
  return;
}

// ── step ────────────────────────────────────────────────────────
async function cmdStep(args) {
  let file = "";
  let jsonMode = false;
  let maxSteps = 100000;
  let i = 0;
  while (i < args.length) {
    const a = args[i];
    if (a === "--json") jsonMode = true;
    else if (a === "--summary") jsonMode = false;
    else if (a === "--max-steps" && i + 1 < args.length) {
      const v = args[++i];
      if (!/^[0-9]+$/.test(v)) die(`用法错: --max-steps 需要整数，得到 '${v}'`, 4);
      maxSteps = parseInt(v, 10);
    } else if ((!a.startsWith("-") || a === "-") && file === "") file = a;
    i++;
  }
  if (file === "") {
    process.stderr.write("用法: step <file.c> [--max-steps N] [--json|--summary]\n");
    process.exitCode = 4;
    return;
  }
  const stdinSrc = file === "-" ? readStdinText() : undefined;
  const files = collectFiles(file, stdinSrc);
  inv("session.create");
  inv("config.set", { ...RUN_CONFIG, max_steps: maxSteps });
  const comp = inv("compile", { files });
  if (!comp.ok || !comp.result.ok || hasErrors(comp.result)) {
    process.stdout.write(JSON.stringify(comp) + "\n");
    process.exitCode = 1;
    return;
  }
  inv("run", { argv: [file === "-" ? "main.c" : file] });
  inv("step.begin");
  let frames = 0;
  let last = null;
  let finished = false;
  let trapped = false;
  let running = true;
  while (running) {
    const r = inv("step.next");
    last = r;
    frames += countPayloads(r);
    if (jsonMode) process.stdout.write(JSON.stringify(r) + "\n");
    const res = r.result || {};
    if (res.finished === true) { finished = true; running = false; }
    else if (res.trapped === true) { trapped = true; running = false; }
    else if (res.waiting_input === true) { running = false; }
  }
  if (jsonMode) {
    process.stdout.write(
      JSON.stringify({ type: "summary", backend: BACKEND, frames, finished, trapped }) + "\n",
    );
  } else {
    process.stdout.write(`帧数: ${frames}\n`);
    const term = finished ? "finished" : trapped ? "trap" : "waiting_input/截断";
    process.stdout.write(`终态: ${term}\n`);
    if (trapped) {
      const msg = (last && last.result && last.result.trap_message) || "";
      process.stdout.write(`死因: ${msg}\n`);
    }
  }
  if (trapped) {
    const msg = (last && last.result && last.result.trap_message) || "";
    // 引擎固定文案前缀判（与 cli_step 同口径——spec §2 限定句）
    if (msg.includes("程序执行步数超过限制")) { process.exitCode = 3; return; }
    process.exitCode = 2;
    return;
  }
  process.exitCode = 0;
  return;
}

function countPayloads(frame) {
  const s = JSON.stringify(frame);
  let n = 0, k = 0;
  const pat = '"step_index":';
  while ((k = s.indexOf(pat, k)) !== -1) { n++; k += pat.length; }
  return n;
}

// ── api ─────────────────────────────────────────────────────────
async function cmdApi(args) {
  let method = "";
  let params = "{}";
  let batch = false;
  for (const a of args) {
    if (a === "--batch") batch = true;
    else if (!a.startsWith("-") && method === "") method = a;
    else if (method !== "" && params === "{}" && a !== "{}") params = a;
  }
  if (batch) {
    if (method !== "") die("用法错: --batch 不与 <method> 并用（帧序列从 stdin 读）", 4);
    const text = readStdinText();
    if (text.trim() === "") die("用法错: --batch 收到空 stdin（喂 NDJSON 请求帧序列）", 4);
    let rc = 0;
    for (const line of text.split("\n")) {
      const l = line.trim();
      if (l === "") continue;
      // 整帧透传（与 CLI api --batch 同语义：请求帧原样进，响应帧原样出）
      const resp = rawInvoke(JSON.parse(l));
      process.stdout.write(JSON.stringify(resp) + "\n");
      if (resp.ok === false) rc = 1;
    }
    process.exitCode = rc;
    return;
  }
  if (method === "") {
    process.stderr.write(
      "用法: api <method> [params-json] | api --batch < frames.ndjson  （例: api memory.regions / api compile '{\"source\":\"int main(){return 0;}\"}'）\n",
    );
    process.exitCode = 4;
    return;
  }
  if (!params.startsWith("{")) {
    die(`用法错: params 须为 JSON 对象字面量，得到 '${params}'`, 4);
  }
  const resp = inv(method, JSON.parse(params));
  process.stdout.write(JSON.stringify(resp) + "\n");
  process.exitCode = resp.ok === false ? 1 : 0;
  return;
}

// ── 入口 ────────────────────────────────────────────────────────
(async () => {
  process.stderr.write(`[vitro] backend=${BACKEND} (node ${process.versions.node})\n`);
  const args = process.argv.slice(2);
  const cmd = args[0];
  if (!cmd || cmd === "help" || cmd === "--help" || cmd === "-h") {
    usageExit(args.length === 0 ? 4 : 0);
  }
  await loadGateway();
  const rest = args.slice(1);
  if (cmd === "run") await cmdRun(rest);
  else if (cmd === "compile") await cmdCompile(rest);
  else if (cmd === "step") await cmdStep(rest);
  else if (cmd === "api") await cmdApi(rest);
  else if (["serve", "dump-tokens", "dump-ast", "dump-typeck", "dump-compile"].includes(cmd)) {
    process.stderr.write(
      `vitro: '${cmd}' 走独立 exe（moonbit/_build/native/release/build/cmd/<name>/——防线调用面，暂不收拢；一次性脚本化用 'vitro api <method> <params>' 覆盖协议方法）\n`,
    );
    process.exitCode = 4;
    return;
  } else {
    process.stderr.write(`vitro: 未知命令 '${cmd}'\n`);
    usageExit(4);
  }
})().catch((e) => {
  if (e instanceof ExitNow) {
    process.exitCode = e.code;
    return;
  }
  process.stderr.write(`[vitro] 壳错误: ${e.message}\n`);
  process.exitCode = 4;
  return;
});
