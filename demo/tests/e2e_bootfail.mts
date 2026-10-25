// E2E 实测（boot 失败态——#188 红锚批 2026-10-18）：
// 引擎 wasm 装载失败时（产物改名模拟）：banner 出现 + 「运行」按钮必须
// disabled（视觉+语义一致）——修复前按钮可点、点击零反馈（静默）。
// #288-① 门禁（2026-10-24）：拦 worker chunk 模拟「Worker 永不回帖」
// （脚本加载失败 / CSP 拦截形态）——修复前遮罩常驻零提示；修复后
// onerror 兜底 → boot reject → 横幅 + 重试入口 + 遮罩撤。
// 产物改名在 finally 还原；测后还原锚验证正常 boot 不被污染。
// 用法同 e2e_workspace.mts 三步（build / serve_static 8931 / headless chrome 9222）。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { connectCdp, sleep, type CheckResult } from "./cdp.mts";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const PAGE = BASE + "index.html";
const DIST = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "assets");

const results: CheckResult[] = [];
const check = (name: string, ok: boolean, detail: string): void => {
  results.push({ name, ok });
  console.log((ok ? "PASS" : "FAIL") + "  " + name + "  — " + detail);
};

interface BootFailState {
  banner: string | null;
  booted: boolean | null;
  runDisabled: boolean | null;
}

interface WorkerFailState {
  mask: boolean;
  banner: string | null;
  retry: boolean;
  booted: boolean | null;
}

async function run() {
  const { send, evaluate, waitFor } = await connectCdp();
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
    const bootfail = await evaluate<BootFailState>(`({
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
  const restored = await evaluate<boolean | null>("document.querySelector(\"[data-act='run']\")?.disabled ?? null");
  check("B3 产物还原后正常 boot + 运行按钮可点", restored === false, `disabled=${JSON.stringify(restored)}`);

  // ── #288-① 门禁：拦 worker chunk（Worker 永不回帖路径）──────────
  // B1~B3 改的是 wasm 名——Worker 脚本本身活着、能回 ok:false 错误帖；
  // 本 case 改 worker chunk 名：new Worker(404) ⇒ onerror（修复前无人
  // 兜底 ⇒ boot 的 promise 永不 settle ⇒ 遮罩常驻、零横幅零重试）。
  const workerJs = fs.readdirSync(DIST).find((f) => /^engine\.worker-.*\.js$/.test(f));
  if (!workerJs) throw new Error("dist/assets 下无 engine.worker-*.js——产物面漂移");
  const workerHidden = workerJs + ".bak_e2e";
  fs.renameSync(path.join(DIST, workerJs), path.join(DIST, workerHidden));
  try {
    await send("Page.navigate", { url: PAGE + "?bootfailworker=1" });
    await waitFor(`!!document.querySelector(".vr-banner") && !document.querySelector(".vr-boot")`, 20000);
    await sleep(300);
    const w = await evaluate<WorkerFailState>(`({
      mask: !!document.querySelector(".vr-boot"),
      banner: document.querySelector(".vr-banner")?.textContent?.replace(/\\s+/g, " ").slice(0, 80) ?? null,
      retry: [...document.querySelectorAll(".vr-banner button")].some((b) => (b.textContent ?? "").includes("重试")),
      booted: window.__pilot?.session?.booted ?? null,
    })`);
    check("B4 worker 不回帖：遮罩撤 + 失败横幅（不永久转圈）", w.mask === false && !!w.banner && w.booted === false, JSON.stringify(w.banner));
    check("B5 重试入口在场", w.retry === true, `retry=${JSON.stringify(w.retry)}`);
  } finally {
    fs.renameSync(path.join(DIST, workerHidden), path.join(DIST, workerJs));
  }

  // 还原锚：worker 产物还原后整页重载可正常 boot（超时兜底后 killWorker
  // 重建路径的旁证——重试与整页重载走同一条 getWorker）
  await send("Page.navigate", { url: PAGE + "?restored2=1" });
  await waitFor("window.__pilot && window.__pilot.session.booted", 40000);
  check("B6 worker 产物还原后正常 boot", true, "booted=true");

  const fails = results.filter((r) => !r.ok).length;
  console.log(`\n${fails === 0 ? "ALL PASS" : "FAILED"}: ${results.length - fails}/${results.length}`);
  process.exit(fails === 0 ? 0 : 1);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
