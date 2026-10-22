// E2E 实测（boot 失败态——#188 红锚批 2026-10-18）：
// 引擎 wasm 装载失败时（产物改名模拟）：banner 出现 + 「运行」按钮必须
// disabled（视觉+语义一致）——修复前按钮可点、点击零反馈（静默）。
// 产物改名在 finally 还原；测后还原锚验证正常 boot 不被污染。
// 用法同 e2e_workspace.mjs 三步（build / serve_static 8931 / headless chrome 9222）。
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const PAGE = BASE + "index.html";
const DIST = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "assets");

let msgId = 0;
const pending = new Map();
let ws;

function send(method, params = {}) {
  const id = ++msgId;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function evaluate(expr) {
  const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw new Error("eval 异常: " + JSON.stringify(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text));
  return r.result.value;
}
async function waitFor(expr, timeout = 20000, step = 250) {
  const t0 = Date.now();
  for (;;) {
    if (await evaluate(expr)) return true;
    if (Date.now() - t0 > timeout) throw new Error("waitFor 超时: " + expr.slice(0, 120));
    await sleep(step);
  }
}

const results = [];
const check = (name, ok, detail) => { results.push({ name, ok }); console.log((ok ? "PASS" : "FAIL") + "  " + name + "  — " + detail); };

async function run() {
  const targets = await (async () => {
    // CI 竞态修复（2026-10-18）：chrome DevTools 端口就绪前连接会
    // ECONNREFUSED（sleep 固定等待竞态）——拒绝即退避重试（10×500ms）
    for (let attempt = 0; ; attempt++) {
      try {
        return await new Promise((resolve, reject) => {
          http.get({ host: "127.0.0.1", port: 9222, path: "/json/list" }, (res) => {
    let b = ""; res.on("data", (c) => (b += c)); res.on("end", () => { try { resolve(JSON.parse(b)); } catch (e) { reject(e); } });
          }).on("error", reject);
        });
        } catch (e) {
          if (attempt >= 19 || !String(e).includes("ECONNREFUSED")) throw e;
          await new Promise((r) => setTimeout(r, 1000));
        }
      }
  })();
  const pages = targets.filter((t) => t.type === "page");
  const page = pages.find((t) => t.url.includes("index.html")) ?? pages[pages.length - 1];
  if (!page) throw new Error("CDP 无 page target");
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id); pending.delete(m.id);
      if (m.error) p.reject(new Error(JSON.stringify(m.error))); else p.resolve(m.result);
    }
  };
  await send("Page.enable");
  await send("Runtime.enable");

  // 定位引擎 wasm 产物并临时改名（fail loud：找不到就是构建产物面变了）
  const wasm = fs.readdirSync(DIST).find((f) => /^wasm-.*\.wasm$/.test(f));
  if (!wasm) throw new Error("dist/assets 下无 wasm-*.wasm——产物面漂移");
  const hidden = wasm + ".bak_e2e";
  fs.renameSync(path.join(DIST, wasm), path.join(DIST, hidden));
  try {
    await send("Page.navigate", { url: PAGE + "?bootfail=1" });
    // banner 出现（bootError 态渲染完成）
    await waitFor("window.__pilot !== undefined", 15000);
    await waitFor(`!!document.querySelector("[role=alert], .vr-bootbanner") || (window.__pilot && !window.__pilot.session.booted && !window.__pilot.ui.ready === false)`, 15000);
    await sleep(800);
    const bootfail = await evaluate(`({
      banner: document.querySelector("[role=alert], .vr-bootbanner")?.textContent?.replace(/\\s+/g, " ").slice(0, 60) ?? null,
      booted: window.__pilot?.session?.booted ?? null,
      runDisabled: document.querySelector("[data-act='run']")?.disabled ?? null,
    })`);
    check("B1 boot 失败 banner 出现", !!bootfail.banner && bootfail.booted === false, JSON.stringify(bootfail.banner));
    check("B2 运行按钮 disabled（不可点）", bootfail.runDisabled === true, `disabled=${JSON.stringify(bootfail.runDisabled)}`);
  } finally {
    // 还原产物（必须执行——污染后续步骤 = 事故）
    fs.renameSync(path.join(DIST, hidden), path.join(DIST, wasm));
  }

  // 还原锚：正常 boot 恢复（等采集结束——collecting 期间 disabled 是 #188 修复的正确语义）
  await send("Page.navigate", { url: PAGE + "?restored=1" });
  await waitFor("window.__pilot && window.__pilot.session.booted", 40000);
  await waitFor("window.__pilot.ui.screen === 'work' && !window.__pilot.session.collecting", 40000);
  const restored = await evaluate("document.querySelector(\"[data-act='run']\")?.disabled ?? null");
  check("B3 产物还原后正常 boot + 运行按钮可点", restored === false, `disabled=${JSON.stringify(restored)}`);

  const fails = results.filter((r) => !r.ok).length;
  console.log(`\n${fails === 0 ? "ALL PASS" : "FAILED"}: ${results.length - fails}/${results.length}`);
  process.exit(fails === 0 ? 0 : 1);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
