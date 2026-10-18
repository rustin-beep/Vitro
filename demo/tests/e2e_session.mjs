// E2E 实测（会话/回放/分享族——2026-10-18 前端实测立账批的防线锚）：
// CDP 驱动 Edge 无头，对 vite 产物做真页面验证。锚 ↔ 修复一一对应（红→绿
// 纪律：每锚先证会红——frameAt 突变回 raw 版跑本脚本 F3 即红，突变法见
// 各锚注释）：
//   F1 坏分享 hash 持久横幅（P1-3：toast 会过期，横幅必须常驻；kind:"bad" 同收口）
//   F2 argv 用例采集成功（P1-2：currentCase 深代理 postMessage 克隆崩——
//      崩时 status=采集失败+outputs 残留；修后 stdout 正常零 clone 错）
//   F3 语句级帧口径（P1-1：frameAt 返回 raw 帧致画面全面错位——突变回
//      frames[i] 本锚即红）
//   F4 播完 status 提示（P2-9：播完静默回正零提示）
//   F5 char 数组可视化零崩溃（P1-5：元素 "'a'" Number 化 NaN → key 全撞
//      NaN#0 → each_key_duplicate 每帧崩）
//   F6 trap E 码 → 手册联动（P2-10：伪下划线变真通道）
// 用法同 e2e_diagcard.mjs 三步（build / serve_static 8931 / headless Edge 9222）。
// 说明：CDP WebSocket 用 Node 22+ 全局 WebSocket；/json/list 走 node:http
// 直连（环境代理会拦本地 CDP——Edge 侧须 --no-proxy-server）。
import http from "node:http";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const PAGE = BASE + "index.html";

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

async function waitFor(expr, timeout = 25000, step = 250) {
  const t0 = Date.now();
  for (;;) {
    const v = await evaluate(expr);
    if (v) return v;
    if (Date.now() - t0 > timeout) throw new Error("waitFor 超时: " + expr.slice(0, 120));
    await sleep(step);
  }
}

/** console.error / uncaught 收集（each_key_duplicate/postMessage 崩走这两通道）。 */
const ERR_COLLECTOR = `(() => {
  window.__errs = [];
  const oe = console.error;
  console.error = (...a) => { window.__errs.push(a.map((x) => String(x?.message ?? x)).join(" ").slice(0, 200)); oe(...a); };
  window.addEventListener("error", (e) => window.__errs.push("UNCAUGHT: " + e.message));
})()`;
const errs = () => evaluate("JSON.stringify(window.__errs ?? [\"收集器未挂\"])");

/** 点课（内容 tab → 展开全部章节 → 定位 lesson lid → 点击）并等**本课**采集
 *  完成：epoch 判据（点课触发 collect 开头 ++epoch——「collecting=false 且
 *  frames>0」在点课同步空窗会被上一课残留帧骗过，2026-10-18 首跑实锤）。 */
async function pickLesson(lid, waitMs = 25000) {
  await evaluate(`(() => {
    const tabs = [...document.querySelectorAll("button.tab")];
    tabs.find((b) => b.textContent.trim() === "内容")?.click();
    return tabs.length;
  })()`);
  await sleep(350);
  await evaluate(`(() => {
    [...document.querySelectorAll("button.chap-head")].forEach((h) => { if (h.getAttribute("aria-expanded") === "false") h.click(); });
  })()`);
  await sleep(300);
  const e0 = await evaluate("window.__pilot.session.epoch");
  const clicked = await evaluate(`(() => {
    const hit = [...document.querySelectorAll("button.lesson")].find((b) => b.querySelector(".lid")?.textContent === ${JSON.stringify(lid)});
    if (!hit) return false;
    hit.click();
    return true;
  })()`);
  if (!clicked) throw new Error(`找不到课程 ${lid}`);
  await waitFor(`(() => { const s = window.__pilot.session; return s.epoch > ${e0} && !s.collecting && s.frames.length > 0; })()`, waitMs);
}

async function run() {
  // 1. 发现 page target 并 attach
  const targets = await new Promise((resolve, reject) => {
    http.get({ host: "127.0.0.1", port: 9222, path: "/json/list" }, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => { try { resolve(JSON.parse(body)); } catch (e) { reject(e); } });
    }).on("error", reject);
  });
  const pages = targets.filter((t) => t.type === "page");
  const page = pages.find((t) => t.url.includes("index.html")) ?? pages[pages.length - 1];
  if (!page) throw new Error("CDP 无 page target");
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id);
      pending.delete(m.id);
      if (m.error) p.reject(new Error(JSON.stringify(m.error)));
      else p.resolve(m.result);
    }
  };
  await send("Page.enable");
  await send("Runtime.enable");

  const results = [];
  const check = (name, ok, detail) => { results.push({ name, ok, detail }); console.log((ok ? "PASS" : "FAIL") + "  " + name + "  — " + detail); };

  // ── F1 坏分享 hash → 持久横幅（P1-3）——cache-bust 强制完整导航：
  // 同路径仅变 hash 是 hashchange 不重载、boot 链不重跑（首跑实锤）──
  await send("Page.navigate", { url: PAGE + "?cb=" + Date.now() + "#z1.BROKEN" });
  await waitFor("document.querySelector('.pilot-head .badge b')?.textContent?.length > 3", 30000);
  await sleep(600); // boot 链的 hash 解析在 boot+协议面之后
  const f1 = await evaluate(`(() => ({
    banner: document.querySelector(".share-error")?.textContent?.trim().slice(0, 40) ?? "",
    closed: !!document.querySelector(".share-err-close"),
  }))()`);
  check("F1 坏 hash 持久横幅（P1-3）", f1.banner.includes("无法还原") && f1.closed, JSON.stringify(f1));

  // ── 干净加载 → 后续锚共用会话 ──
  await send("Page.navigate", { url: PAGE });
  await waitFor("document.querySelector('.pilot-head .badge b')?.textContent?.length > 3", 30000);
  await waitFor("window.__pilot && window.__pilot.session.booted", 15000);
  await evaluate(ERR_COLLECTOR);

  // ── F2 argv 用例采集成功（P1-2）——断言走 stdout/runStats/零 clone 错；
  // status 不参与（采集完自动播放，status 终态=「回放完毕」属预期）──
  await pickLesson("argv_prog");
  const f2 = await evaluate(`(() => {
    const s = window.__pilot.session;
    return { stdout: s.outputs.stdout.slice(0, 40), stats: !!s.runStats, frames: s.frames.length };
  })()`);
  const f2errs = JSON.parse(await errs());
  check("F2 argv 采集成功零克隆崩（P1-2）",
    f2.stdout.includes("hello-arg") && f2.stats && f2.frames > 0 && !f2errs.some((e) => e.includes("could not be cloned")),
    JSON.stringify(f2) + " errs=" + f2errs.length);

  // ── F3+F4 语句级口径 + 播完 status（P1-1 / P2-9）──
  // bubble 采集后自动播放（2026-10-17 拍板）——等播完（playing=false 且 idx 到末帧）
  await pickLesson("bubble");
  await waitFor("(() => { const s = window.__pilot.session; return !s.playing && s.idx === s.viewFrames.length - 1; })()", 30000);
  const f3 = await evaluate(`(() => {
    const p = window.__pilot, s = p.session;
    return {
      gran: s.gran, view: s.viewFrames.length, raw: s.frames.length,
      same: p.frameAt(s.idx) === s.viewFrames[s.idx],
      status: s.status.slice(0, 12),
    };
  })()`);
  check("F3 语句级 frameAt 口径（P1-1）", f3.gran === "stmt" && f3.view < f3.raw && f3.same, JSON.stringify(f3));
  check("F4 播完 status 提示（P2-9）", f3.status.includes("回放完毕"), "status=" + f3.status);

  // ── F5 char 数组可视化零崩溃（P1-5）──
  await evaluate("window.__errs = []"); // 分桶：只看本步新增
  await pickLesson("string_match_bf");
  await sleep(800); // 播放中每帧更新 ArrayBars——崩溃在更新期抛
  const f5 = await evaluate(`(() => ({
    bars: document.querySelectorAll(".bars").length,
    frames: window.__pilot.session.frames.length,
  }))()`);
  const f5errs = JSON.parse(await errs());
  check("F5 char 数组零 each_key_duplicate（P1-5）",
    f5.frames > 0 && f5errs.every((e) => !e.includes("each_key_duplicate")),
    JSON.stringify(f5) + " errs=" + JSON.stringify(f5errs.slice(0, 2)));

  // ── F6 trap E 码 → 手册联动（P2-10）──
  await pickLesson("uaf");
  await sleep(600);
  const hasCode = await waitFor("!!document.querySelector('.tp-code[data-ecode]')", 10000).catch(() => false);
  if (hasCode) {
    const code = await evaluate("document.querySelector('.tp-code[data-ecode]').getAttribute('data-ecode')");
    await evaluate("document.querySelector('.tp-code[data-ecode]').click()");
    await sleep(500);
    const f6 = await evaluate(`(() => ({
      tab: document.querySelector(".tab.active")?.textContent?.trim(),
      search: document.querySelector(".cat-search")?.value ?? "",
      count: document.querySelector(".cat-count")?.textContent?.trim() ?? "",
    }))()`);
    check("F6 trap E 码联动手册（P2-10）", f6.tab === "诊断手册" && f6.search === code, JSON.stringify({ code, ...f6 }));
  } else {
    check("F6 trap E 码联动手册（P2-10）", false, "uaf 课未产出 trap 详报 E 码徽章");
  }

  const fails = results.filter((r) => !r.ok);
  console.log(`===== ${results.length - fails.length}/${results.length} 通过 =====`);
  process.exit(fails.length ? 1 : 0);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
