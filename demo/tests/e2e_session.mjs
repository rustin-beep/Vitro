// E2E 实测（会话/回放/分享族——2026-10-18 前端改造批重定向）：
// CDP 驱动 Edge 无头，对 vite 产物做真页面验证。锚 ↔ 修复一一对应：
//   F1 坏分享 hash 持久横幅（P1-3：toast 会过期，横幅必须常驻）
//   F2 argv 用例采集成功（P1-2：currentCase 深代理 postMessage 克隆崩）
//   F3 语句级帧口径（P1-1：frameAt 返回 raw 帧致画面全面错位）
//   F4 播完 status 提示（P2-9：播完静默回正零提示）；F4b 末帧状态行
//   F5 char 数组**全帧 sweep** 零 each_key_duplicate（P1-5；2026-10-18 加固）
//   F6 trap E 码 → 手册联动（P2-10：伪下划线变真通道）
//   F7 课程目录全章渲染（重名课 id 防护：structures/josephus 实测 2026-10-18）
//   B0 未迁移课无分镜条 / B1 分镜条点幕 = 跳幕首帧（#222 P1 第二片，2026-10-21）
//   B2 幕头随帧更新 + 浅树压扁（#222 P1 第三片，2026-10-21）
//   B3 三栏 + 底栏时间轴 + 首屏（#222 P1 第四片，2026-10-21）
//   B4 逐行注记（#222 P1 第五片，2026-10-21）
//   B5 本幕讲解 + 展开全文（#222 P1 第六片，2026-10-21）
// 用法同 e2e_diagcard.mjs 三步（build / serve_static 8931 / headless Edge 9222）。
// ⚠️ 旧锚点 .pilot-head/.tab/.bars/button.lesson 已随旧五 tab DOM 退役。
// 说明：CDP WebSocket 用 Node 22+ 全局 WebSocket；/json/list 走 node:http 直连。
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

/** 打开课程目录（若已在目录态则跳过；参考态先返回实验台——顶栏「课程」
 *  只在工作态渲染，参考态只有「返回实验台 + 课程目录」链接）。 */
async function openEntry() {
  if (await evaluate("window.__pilot.ui.screen === 'entry'")) return;
  if (await evaluate("window.__pilot.ui.screen !== 'work'")) {
    await evaluate(`[...document.querySelectorAll('button')].find(b => b.getAttribute('aria-label') === '返回实验台')?.click()`);
    await waitFor("window.__pilot.ui.screen === 'work'");
    await sleep(200);
  }
  await evaluate(`document.querySelector('[aria-label="课程目录"]')?.click()`);
  await waitFor("window.__pilot.ui.screen === 'entry'");
  await sleep(250);
}

/** 目录选课 → 预览 → 在实验台打开 → 等本课采集完成（epoch 判据，防上一课
 *  残留帧骗过 collecting=false 的空窗）。课程可能不在当前章：逐章扫描。 */
async function pickLesson(id, waitMs = 30000) {
  await openEntry();
  await waitFor("!window.__pilot.session.collecting", 30000); // 首访自动采集可能仍在跑
  const chapters = await evaluate("document.querySelectorAll('.vr-chapter').length");
  let found = false;
  for (let i = 0; i < chapters; i++) {
    await evaluate(`document.querySelectorAll('.vr-chapter')[${i}]?.click()`);
    await sleep(120);
    found = await evaluate(`!![...document.querySelectorAll('.vr-lesson-row')].find(b => b.querySelector('.vr-id')?.textContent === ${JSON.stringify(id)})`);
    if (found) break;
  }
  if (!found) throw new Error(`找不到课程 ${id}`);
  await evaluate(`[...document.querySelectorAll('.vr-lesson-row')].find(b => b.querySelector('.vr-id')?.textContent === ${JSON.stringify(id)})?.click()`);
  await sleep(200);
  const e0 = await evaluate("window.__pilot.session.epoch");
  await evaluate("document.querySelector('.vr-preview .vr-open')?.click()");
  await waitFor(`window.__pilot.ui.screen === 'work' && window.__pilot.lessonSession.lesson?.id === ${JSON.stringify(id)} && window.__pilot.session.epoch > ${e0} && !window.__pilot.session.collecting`, waitMs);
}

async function run() {
  // CI 竞态修复（2026-10-18）：chrome DevTools 端口就绪前连接会
  // ECONNREFUSED（sleep 4 固定等待竞态实锤——"DevTools listening"
  // 出现在异常之后）——拒绝即退避重试（10×500ms）
  const targets = await (async () => {
    for (let attempt = 0; ; attempt++) {
      try {
        return await new Promise((resolve, reject) => {
          http.get({ host: "127.0.0.1", port: 9222, path: "/json/list" }, (res) => {
            let body = "";
            res.on("data", (c) => (body += c));
            res.on("end", () => { try { resolve(JSON.parse(body)); } catch (e) { reject(e); } });
          }).on("error", reject);
        });
      } catch (e) {
        if (attempt >= 9 || !String(e).includes("ECONNREFUSED")) throw e;
        await new Promise((r) => setTimeout(r, 500));
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
      const p = pending.get(m.id);
      pending.delete(m.id);
      if (m.error) p.reject(new Error(JSON.stringify(m.error)));
      else p.resolve(m.result);
    }
  };
  await send("Page.enable");
  // 固定桌面视口（2026-10-18 布局对调后，窗口默认 800×600 会让编辑器落到
  // 视口外，鼠标点击无效——所有 E2E 统一 1440×900，与工作区脚本同口径）
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await send("Runtime.enable");

  const results = [];
  const check = (name, ok, detail) => { results.push({ name, ok, detail }); console.log((ok ? "PASS" : "FAIL") + "  " + name + "  — " + detail); };

  // ── F1 坏分享 hash → 持久横幅（P1-3）——cache-bust 强制完整导航 ──
  await send("Page.navigate", { url: PAGE + "?cb=" + Date.now() + "#z1.BROKEN" });
  await waitFor("window.__pilot && window.__pilot.session.booted", 30000);
  await waitFor("document.querySelector('.vr-banner b')?.textContent?.includes('无法还原')", 20000);
  const f1 = await evaluate(`(() => {
    const b = document.querySelector('.vr-banner');
    return { banner: b?.textContent?.replace(/\\s+/g, ' ').trim().slice(0, 50) ?? '', close: !!b?.querySelector('.vr-btn') };
  })()`);
  check("F1 坏 hash 持久横幅（P1-3）", f1.banner.includes("无法还原") && f1.close, JSON.stringify(f1));

  // ── 干净加载 → 后续锚共用会话（等首访落地采集**完成**）──
  await send("Page.navigate", { url: PAGE });
  await waitFor("window.__pilot && window.__pilot.session.booted", 30000);
  // 只等 !collecting 会撞上「boot 完成但 openInitial 尚未开采」的空窗
  await waitFor("window.__pilot.lessonSession.lesson && !window.__pilot.session.collecting && window.__pilot.session.frames.length > 0", 40000);
  await sleep(400);
  await evaluate(ERR_COLLECTOR);

  // ── F2 argv 用例采集成功（P1-2）──
  await pickLesson("argv_prog");
  const f2 = await evaluate(`(() => {
    const s = window.__pilot.session;
    return { stdout: s.outputs.stdout.slice(0, 40), stats: !!s.runStats, frames: s.frames.length };
  })()`);
  const f2errs = JSON.parse(await errs());
  check("F2 argv 采集成功零克隆崩（P1-2）",
    f2.stdout.includes("hello-arg") && f2.stats && f2.frames > 0 && !f2errs.some((e) => e.includes("could not be cloned")),
    JSON.stringify(f2) + " errs=" + f2errs.length);

  // ── B0 未迁移课无分镜条（#222 P1 第二片：scene 真源 = lesson.md；无元数据
  //    的课 scenes=[] → 分镜条整段不渲染，回退现有长文）──
  const b0 = await evaluate(`(() => ({
    beats: document.querySelectorAll('.vr-beat').length,
    bands: document.querySelectorAll('.vr-band').length,
    annots: document.querySelectorAll('.cm-line[data-annot]').length,
    sceneNote: !!document.querySelector('.vr-scenenote'),
    notePage: !!document.querySelector('.vr-note-page'),
  }))()`);
  check("B0 未迁移课：无分镜条/无注记/无本幕卡（回退长文）", b0.beats === 0 && b0.bands === 0 && b0.annots === 0 && b0.sceneNote === false && b0.notePage === true, JSON.stringify(b0));

  // ── F3+F4 语句级口径 + 播完提示（P1-1 / P2-9）──
  await pickLesson("bubble");
  await waitFor("(() => { const s = window.__pilot.session; return !s.playing && s.idx === s.viewFrames.length - 1; })()", 40000);
  const f3 = await evaluate(`(() => {
    const p = window.__pilot, s = p.session;
    return {
      gran: s.gran, view: s.viewFrames.length, raw: s.frames.length,
      same: p.frameAt(s.idx) === s.viewFrames[s.idx],
      status: s.status.slice(0, 12),
      statusLine: document.querySelector('.vr-status')?.textContent?.trim() ?? '',
    };
  })()`);
  check("F3 语句级 frameAt 口径（P1-1）", f3.gran === "stmt" && f3.view < f3.raw && f3.same, JSON.stringify(f3));
  check("F4 播完 status 提示（P2-9）", f3.status.includes("回放完毕"), "status=" + f3.status);
  check("F4b 末帧状态行（末帧 · 可拖回任意帧）", f3.statusLine.includes("末帧"), f3.statusLine);

  // ── B1 分镜轨点幕 = 跳幕首帧（#222 P1 第四片把分镜条移进左栏竖排）：
  //    bubble 4 幕、4 条分幕带，点第 1 幕 → idx 归 0、当前幕/注记同步 ──
  const b1before = await evaluate(`(() => ({
    beats: document.querySelectorAll('.vr-beat').length,
    bands: document.querySelectorAll('.vr-band').length,
    active: document.querySelector('.vr-beat.is-active')?.textContent?.trim() ?? '',
  }))()`);
  await evaluate("document.querySelectorAll('.vr-beat')[0]?.click(); true");
  await sleep(250);
  const b1after = await evaluate(`(() => ({
    idx: window.__pilot.session.idx,
    active: document.querySelector('.vr-beat.is-active')?.textContent?.trim() ?? '',
    note: document.querySelector('.vr-beat.is-active .vr-beat-note')?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
    bandsActive: document.querySelectorAll('.vr-band.is-active').length,
  }))()`);
  check("B1 分镜轨点幕 = 跳幕首帧（#222）",
    b1before.beats === 4 && b1before.bands === 4 && b1before.active.includes("04") &&
      b1after.idx === 0 && b1after.active.includes("01") && b1after.note.includes("数组初始化") && b1after.bandsActive === 1,
    JSON.stringify({ b1before, b1after }));

  // ── B2 幕头 + 浅树压扁（#222 P1 第三片）：当前幕随帧更新、上一幕/下一幕能跳；
  //    bubble 只有 prog → main（2 节点）→ 不画 214px 画布，压成一行面包屑 ──
  const b2 = await evaluate(`(() => ({
    kicker: document.querySelector('.vr-stagehead-kicker')?.textContent?.trim() ?? '',
    title: document.querySelector('.vr-stagehead-title')?.textContent?.trim() ?? '',
    prevDisabled: document.querySelectorAll('.vr-stagehead-nav button')[0]?.disabled,
    compact: !!document.querySelector('.vr-tree-compact'),
    canvas: !!document.querySelector('.vr-canvas'),
  }))()`);
  await evaluate("document.querySelectorAll('.vr-stagehead-nav button')[1]?.click(); true");
  await sleep(250);
  const b2after = await evaluate(`(() => ({
    idx: window.__pilot.session.idx,
    kicker: document.querySelector('.vr-stagehead-kicker')?.textContent?.trim() ?? '',
    title: document.querySelector('.vr-stagehead-title')?.textContent?.trim() ?? '',
  }))()`);
  check("B2 幕头随帧更新 + 浅树压扁（#222）",
    b2.title.includes("起点") && b2.prevDisabled === true && b2.compact === true && b2.canvas === false &&
      b2after.idx === 5 && b2after.title.includes("交换") && b2after.kicker.includes("帧 5–20"),
    JSON.stringify({ b2, b2after }));

  // ── B3 三栏 + 底栏时间轴（#222 P1 第四片）：1440 下 rail / stage / now 左中右
  //    并排、时间轴横跨三栏；代码/数组/时间轴都落在 900px 首屏内 ──
  const b3 = await evaluate(`(() => {
    const box = (sel) => document.querySelector(sel)?.getBoundingClientRect() ?? null;
    const rail = box('.vr-colrail'), stage = box('.vr-colstage'), now = box('.vr-colnow'), dock = box('.vr-coldock');
    const code = box('.vr-code'), cells = box('.vr-cells');
    return {
      railLeft: rail && Math.round(rail.left), stageLeft: stage && Math.round(stage.left), nowLeft: now && Math.round(now.left),
      railW: rail && Math.round(rail.width), nowW: now && Math.round(now.width),
      dockW: dock && Math.round(dock.width), benchW: Math.round(box('.vr-bench').width),
      codeTop: code && Math.round(code.top), cellsTop: cells && Math.round(cells.top), dockTop: dock && Math.round(dock.top),
    };
  })()`);
  check("B3 三栏 + 底栏时间轴（#222）",
    b3.railLeft < b3.stageLeft && b3.stageLeft < b3.nowLeft &&
      b3.railW >= 240 && b3.nowW >= 340 && b3.dockW > b3.benchW * 0.95 &&
      b3.codeTop < 900 && b3.cellsTop < 900 && b3.dockTop < 900,
    JSON.stringify(b3));
  // ── B4 逐行注记（#222 P1 第五片）：帧 12 的三行注记 = 拍板稿 08/09/10 形态；
  //    注记走行属性 + CSS 伪元素（不进 .cm-content 文本面——E2E docLen 不被污染） ──
  await evaluate(`(() => { const s = document.querySelector('.vr-seek'); s.value = 12; s.dispatchEvent(new Event('input', { bubbles: true })); return true; })()`);
  await sleep(300);
  const b4 = await evaluate(`(() => ({
    idx: window.__pilot.session.idx,
    attrs: [...document.querySelectorAll('.cm-line[data-annot]')].map((l) => l.getAttribute('data-annot')),
    inText: (document.querySelector('.cm-content')?.textContent ?? '').includes('←'),
  }))()`);
  check("B4 逐行注记（#222 P1 第五片）",
    b4.idx === 12 && b4.attrs.length === 3 && b4.attrs.includes("t ← 5") && b4.attrs.includes("a[1] ← 1") &&
      b4.attrs.includes("a[2] ← 5") && b4.inText === false,
    JSON.stringify(b4));
  // ── B5 本幕讲解 + 展开全文（#222 P1 第六片）：scene 课默认折叠、本幕卡片随幕更新，
  //    全文在 DOM（折叠不丢内容——W9 锚不受影响）；点 summary 可展开 ──
  const b5 = await evaluate(`(() => ({
    card: document.querySelector('.vr-scenenote')?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
    open: document.querySelector('details.vr-notefull')?.open ?? null,
    fullInDom: (document.querySelector('.vr-note-page')?.textContent ?? '').includes('这门课在做什么'),
  }))()`);
  await evaluate("document.querySelector('details.vr-notefull > summary')?.click(); true");
  await sleep(200);
  const b5open = await evaluate("document.querySelector('details.vr-notefull')?.open === true");
  check("B5 本幕讲解 + 展开全文（#222）",
    b5.card.includes("本幕讲解") && b5.card.includes("交换不是瞬间完成的") && b5.open === false && b5.fullInDom === true && b5open === true,
    JSON.stringify({ b5, b5open }));

  // ── F5 char 数组可视化零崩溃（P1-5）──
  // 2026-10-18 加固：逐帧 seek 全量帧（此前只看首个数组帧 + 800ms，晚帧崩溃
  // 会漏抓）。char 课 146 帧 × 每帧一次数组格/变量/树渲染。
  await evaluate("window.__errs = []");
  await pickLesson("string_match_bf");
  if (await evaluate("window.__pilot.session.playing")) {
    await evaluate(`document.querySelector('[data-act="play"]')?.click()`);
    await sleep(120);
  }
  const f5total = await evaluate("window.__pilot.session.viewFrames.length");
  const f5arr = await evaluate(`window.__pilot.session.viewFrames.findIndex((f) => (f.array_snapshots?.length ?? 0) > 0)`);
  for (let i = 0; i < f5total; i++) {
    await evaluate(`window.__pilot.seek(${i})`);
    await sleep(3);
  }
  if (f5arr >= 0) {
    await evaluate(`window.__pilot.seek(${f5arr})`);
    await sleep(200);
  }
  const f5 = await evaluate(`(() => ({
    cells: document.querySelectorAll(".vr-cell").length,
    frames: window.__pilot.session.frames.length,
    view: window.__pilot.session.viewFrames.length,
    snapAt: window.__pilot.session.viewFrames[window.__pilot.session.idx]?.array_snapshots?.length ?? 0,
  }))()`);
  const f5errs = JSON.parse(await errs());
  check("F5 char 数组全帧零 each_key_duplicate（P1-5）",
    f5.frames > 0 && f5.view === f5total && f5arr >= 0 && f5.cells > 0 && f5errs.every((e) => !e.includes("each_key_duplicate")),
    JSON.stringify(f5) + " sweep=" + f5total + " errs=" + JSON.stringify(f5errs.slice(0, 2)));

  // ── F6 trap E 码 → 手册联动（P2-10）──
  await pickLesson("uaf");
  await sleep(600);
  const hasCode = await waitFor("!!document.querySelector('.vr-trap-body .tp-code[data-ecode]')", 10000).catch(() => false);
  if (hasCode) {
    const code = await evaluate("document.querySelector('.vr-trap-body .tp-code[data-ecode]').getAttribute('data-ecode')");
    await evaluate("document.querySelector('.vr-trap-body .tp-code[data-ecode]').click()");
    await waitFor("window.__pilot.ui.screen === 'ref'", 10000);
    await sleep(400);
    const f6 = await evaluate(`(() => ({
      screen: window.__pilot.ui.screen,
      refCode: window.__pilot.ui.refCode,
      active: document.querySelector('.vr-ref-item.is-active .vr-code-id')?.textContent?.trim() ?? '',
      h1: document.querySelector('.vr-ref-detail h1')?.textContent?.trim() ?? '',
    }))()`);
    check("F6 trap E 码联动手册（P2-10）", f6.screen === "ref" && f6.refCode === code && f6.active === code && !!f6.h1, JSON.stringify({ code, ...f6 }));
  } else {
    check("F6 trap E 码联动手册（P2-10）", false, "uaf 课未产出 trap 详报 E 码徽章");
  }

  // ── F7 课程目录全章可渲染（重名课 id 防护）──
  // 实测形态（2026-10-18）：structures 章同时有 algo `josephus` 与 variant
  // tpl `josephus`——目录 each 若按裸 id keying，扫到该章即 each_key_duplicate
  // 整页崩。此锚逐章点击渲染并要求每章都有课目行。
  await openEntry();
  await evaluate("window.__errs = []");
  const f7chapters = await evaluate("document.querySelectorAll('.vr-chapter').length");
  const f7rows = [];
  for (let i = 0; i < f7chapters; i++) {
    await evaluate(`document.querySelectorAll('.vr-chapter')[${i}]?.click()`);
    await sleep(160);
    f7rows.push(await evaluate("document.querySelectorAll('.vr-lesson-row').length"));
  }
  const f7errs = JSON.parse(await errs());
  check("F7 目录全章可渲染（重名 id each_key_duplicate 防护）",
    f7chapters >= 9 && f7rows.every((n) => n > 0) && f7errs.every((e) => !e.includes("each_key_duplicate")),
    JSON.stringify({ chapters: f7chapters, rows: f7rows, errs: f7errs.slice(0, 2) }));

  // ── F8 首访 shell 先行（#首开性能批 A 红锚，2026-10-19 用户拍板）──
  // 修前：startBoot 的 ui.ready 被 openInitial 的 await collect 挡住——载入
  // 遮罩要等首课采集完成才撤（弱网/移动端首开「巨慢」的主构成段；老框架
  // 「点开即显、采集页面内转」的体感回归目标）。锚 = fresh 首访轮询捕捉
  // (ui.ready=true && frames=0) 组合：修后 shell 先行该窗口必然存在；
  // 修前 ready 与 frames 同时就绪、组合永不存在。CPU 6x 节流放大窗口。
  {
    await send("Emulation.setCPUThrottlingRate", { rate: 6 });
    await send("Page.navigate", { url: PAGE + "?f8=" + Date.now() });
    let caught = false;
    let sawReady = false;
    const t0 = Date.now();
    while (Date.now() - t0 < 30000) {
      const st = await evaluate("({ ready: window.__pilot?.ui?.ready ?? null, frames: window.__pilot?.session?.frames?.length ?? null })").catch(() => null);
      if (st) {
        if (st.ready === true) sawReady = true;
        if (st.ready === true && st.frames === 0) { caught = true; break; }
      }
      await sleep(25);
    }
    await send("Emulation.setCPUThrottlingRate", { rate: 1 });
    check("F8 首访 shell 先行（ui.ready 不等首课采集）", caught, `捕捉到 ready&&frames=0=${caught}（sawReady=${sawReady}）`);
    await waitFor("window.__pilot?.ui?.ready === true", 30000);
    await sleep(600);
  }

  const fails = results.filter((r) => !r.ok);
  console.log(`===== ${results.length - fails.length}/${results.length} 通过 =====`);
  ws.close();
  process.exit(fails.length ? 1 : 0);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
