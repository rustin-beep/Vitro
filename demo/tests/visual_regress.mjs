// 像素闸（#222 P0 第三批，2026-10-21；P0 状态补全 2026-10-22）：16 状态 × 主题 × 视口。
//
// 基线口径：**只在 CI runner + Chrome 生成**——字体栅格化跨 OS 不同，
// （拍板稿假设 CI 是 Ubuntu；本仓 ci.yml 实为 windows-latest，DESIGN.md §7 已记录更正）
// 本机生成的基线在 Linux 上必假红。所以：
//   - 基线目录 `demo/tests/visual/baseline/` 由 `.github/workflows/visual_baseline.yml`
//     （workflow_dispatch）生成并作为 artifact 上传，维护者下载后入库；
//   - 比对仅在「基线存在且平台一致」时武装；否则打印 ::warning:: 跳过（不静默，
//     也不伪造通过）；
//   - 本地只做 `--update` 预习 + 同机比对（用于改样式时的自查，不入库）。
//
// 确定性：清 localStorage → 固定 data-size=14 / data-motion=off / 逐图 data-theme；
// 等 fonts.ready + 两帧 rAF；耗时类文本（输出块的 ms）用掩膜剔除。
//
// 用法：
//   node demo/tests/visual_regress.mjs http://127.0.0.1:8931/             # 比对
//   node demo/tests/visual_regress.mjs http://127.0.0.1:8931/ --update    # 人工令：重写本机基线
//   node demo/tests/visual_regress.mjs http://127.0.0.1:8931/ --only work-mid

import http from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { decodePNG, encodePNG, diffRGBA, diffImage, maskRect } from "./visual/png.mjs";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const UPDATE = process.argv.includes("--update");
const ONLY_IDX = process.argv.indexOf("--only");
const ONLY = ONLY_IDX > 0 ? process.argv[ONLY_IDX + 1] : "";
const HERE = dirname(fileURLToPath(import.meta.url));
const BASELINE_DIR = resolve(HERE, "visual/baseline");
const DIFF_DIR = resolve(HERE, "visual/diff");
const THRESHOLD = 0.001; // 拍板稿：单状态 pixel diff ≤ 0.1%

const THEMES = ["paper", "blueprint"];

const STATES = [
  { name: "work-start", w: 1440, h: 900, theme: "paper", act: "seek0" },
  { name: "work-mid", w: 1440, h: 900, theme: "paper", act: "seek12" },
  { name: "work-start-bp", w: 1440, h: 900, theme: "blueprint", act: "seek0" },
  { name: "work-mid-bp", w: 1440, h: 900, theme: "blueprint", act: "seek12" },
  { name: "entry", w: 1440, h: 900, theme: "paper", act: "entry" },
  { name: "entry-bp", w: 1440, h: 900, theme: "blueprint", act: "entry" },
  { name: "ref", w: 1440, h: 900, theme: "paper", act: "ref" },
  { name: "ref-bp", w: 1440, h: 900, theme: "blueprint", act: "ref" },
  { name: "mem", w: 1440, h: 900, theme: "paper", act: "mem" },
  { name: "proto", w: 1440, h: 900, theme: "paper", act: "proto" },
  // P4 专注模式（2026-10-22）：书栏/参数退役后的讲解面
  { name: "focus", w: 1440, h: 900, theme: "paper", act: "focus" },
  // P0 状态补全（2026-10-22）：trap / 编译失败 / 空输出 / 坏链——四态都是
  // 「说清发生了什么 + 一个动作」的诚实面，入像素闸防回退成空白或假绿。
  { name: "state-trap", w: 1440, h: 900, theme: "paper", act: "trap" },
  { name: "state-compilefail", w: 1440, h: 900, theme: "paper", act: "compilefail" },
  { name: "state-emptyout", w: 1440, h: 900, theme: "paper", act: "emptyout" },
  { name: "state-badlink", w: 1440, h: 900, theme: "paper", act: "badlink", hash: "#z1.BROKEN" },
  { name: "work-768", w: 768, h: 1024, theme: "paper", act: "seek12" },
  { name: "work-390", w: 390, h: 844, theme: "paper", act: "seek12" },
];

let msgId = 0;
const pending = new Map();
let ws;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function send(method, params = {}) {
  const id = ++msgId;
  return new Promise((res, rej) => {
    pending.set(id, { res, rej });
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function evaluate(expr) {
  const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw new Error("eval: " + JSON.stringify(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text));
  return r.result.value;
}

// 导航/重载窗口的 CDP 竞态：页面上下文销毁瞬间 Runtime.evaluate 会返回
// -32000（Cannot find context with specified id / Execution context was
// destroyed）。这是「页面正在换」的正常瞬态，不是断言失败——waitFor 只对它
// 退避重试；其余 CDP 错误照旧 fail loud（Master 线 2026-10-22 反馈实锤：
// badlink 态 reload 后偶发整闸 flaky）。
function isContextRace(err) {
  return String(err).includes("-32000");
}

async function waitFor(expr, timeout = 60000) {
  const t0 = Date.now();
  for (;;) {
    let v;
    try {
      v = await evaluate(expr);
    } catch (err) {
      if (!isContextRace(err)) throw err;
      v = undefined;
    }
    if (v) return;
    if (Date.now() - t0 > timeout) throw new Error("waitFor 超时: " + expr.slice(0, 100));
    await sleep(200);
  }
}

async function connect() {
  const targets = await new Promise((res, rej) => {
    http
      .get({ host: "127.0.0.1", port: 9222, path: "/json/list" }, (r) => {
        let body = "";
        r.on("data", (c) => (body += c));
        r.on("end", () => {
          try {
            res(JSON.parse(body));
          } catch (e) {
            rej(e);
          }
        });
      })
      .on("error", rej);
  });
  const page = targets.filter((t) => t.type === "page").find((t) => t.url.includes("index.html")) ?? targets.filter((t) => t.type === "page")[0];
  if (!page) throw new Error("CDP 无 page target");
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => {
    ws.onopen = res;
    ws.onerror = rej;
  });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id);
      pending.delete(m.id);
      if (m.error) p.rej(new Error(JSON.stringify(m.error)));
      else p.res(m.result);
    }
  };
  await send("Page.enable");
  await send("Runtime.enable");
}

// 点击 helper：先按 aria-label 精确匹配（顶栏「课程目录」按钮的文字是「课程」），
// 再按 title 前缀、文本全等、文本包含兜底——E2E 里同款口径。
const CLICK = (label) =>
  `(() => {
    const els = [...document.querySelectorAll('button, a, [role="button"]')];
    const hit =
      els.find((x) => (x.getAttribute('aria-label') || '') === ${JSON.stringify(label)}) ||
      els.find((x) => (x.getAttribute('title') || '').startsWith(${JSON.stringify(label)})) ||
      els.find((x) => x.textContent.trim() === ${JSON.stringify(label)}) ||
      els.find((x) => x.textContent.includes(${JSON.stringify(label)}));
    if (!hit) return false;
    hit.click();
    return true;
  })()`;

async function setupState(st) {
  await send("Emulation.setDeviceMetricsOverride", { width: st.w, height: st.h, deviceScaleFactor: 1, mobile: st.w < 600 });
  await send("Page.navigate", { url: BASE + "index.html?visual=" + Date.now() + (st.hash ?? "") });
  await waitFor("window.__pilot && window.__pilot.session.booted", 60000);
  if (st.act === "badlink") {
    // 坏链横幅是持久 DOM（F1 锚同判据）；不等它直接截会把「已还原」拍成基准
    await waitFor("document.querySelector('.vr-banner b')?.textContent?.includes('无法还原')", 30000);
  }
  await evaluate("localStorage.clear(); true");
  await send("Page.reload", { ignoreCache: true });
  await waitFor("window.__pilot && window.__pilot.ui.ready", 60000);
  // 坏链态不落课（boot 的还原分支只出横幅）：没有帧流可等——等它只会
  // 90s 超时（2026-10-22 实锤）。其余态都必须有首课帧流。
  if (st.act === "badlink") {
    await waitFor("document.querySelector('.vr-banner b')?.textContent?.includes('无法还原')", 30000);
  } else {
    // localStorage.clear 后 reload 并不保证首课是默认 bubble：App 的 beforeunload
    // persistFrame 会把「上次课」又写回去（2026-10-22 实测：上一轮 E2E 停在 uaf，
    // 像素 baseline 就截到 uaf）。这里显式 openById('bubble') 钉死首课。
    await waitFor("window.__pilot && !window.__pilot.session.collecting", 90000);
    await evaluate("window.__pilot.lessonSession.openById('bubble', 'basic'); true");
    await waitFor(
      "window.__pilot && window.__pilot.lessonSession.lesson?.id === 'bubble' && window.__pilot.session.viewFrames.length > 0 && !window.__pilot.session.collecting",
      90000,
    );
    // 首访采集完会自动播放：不先停播，seek 后的 350ms 等待里帧会继续走
    // （work-start 实测两跑一帧之差 → 当前行高亮带 0.97% 假红）。
    if (await evaluate("window.__pilot.session.playing")) {
      await evaluate(`document.querySelector('[data-act="play"]')?.click(); true`);
      await sleep(120);
    }
    // 模式页的数据面在 collect 之后才拉（memory.regions / capabilities）：
    // 只等帧流会在数据未到时截到空态（mem 实测 10.5% 假红）。
    if (st.act === "mem") await waitFor("!!window.__pilot.session.memory", 30000);
    if (st.act === "proto") await waitFor("!!window.__pilot.session.capabilities", 30000);
  }
  await evaluate(`document.documentElement.setAttribute("data-size", "14"); document.documentElement.setAttribute("data-motion", "off"); true`);
  await sleep(300);
  if (st.act === "seek0" || st.act === "seek12") {
    const i = st.act === "seek0" ? 0 : 12;
    await evaluate(`(() => { const s = document.querySelector('.vr-seek'); s.value = ${i}; s.dispatchEvent(new Event('input', { bubbles: true })); return true; })()`);
  } else if (st.act === "entry") {
    if (!(await evaluate(CLICK("课程目录")))) throw new Error("entry 点击失败");
  } else if (st.act === "ref") {
    if (!(await evaluate(CLICK("诊断手册")))) throw new Error("ref 点击失败");
  } else if (st.act === "mem") {
    if (!(await evaluate(CLICK("内存")))) throw new Error("mem 点击失败");
  } else if (st.act === "proto") {
    if (!(await evaluate(CLICK("协议")))) throw new Error("proto 点击失败");
  } else if (st.act === "focus") {
    await evaluate("window.__pilot.ui.focus = true; true");
    await sleep(250);
  } else if (st.act === "trap") {
    // 真 trap（uaf 末帧）而非伪造横幅：走课程真源 + 引擎实跑
    await evaluate("window.__pilot.lessonSession.openById('uaf', 'basic')");
    await waitFor("!window.__pilot.session.collecting && window.__pilot.session.viewFrames.length > 0", 60000);
    await evaluate("window.__pilot.seek(window.__pilot.session.viewFrames.length - 1); true");
    await sleep(250);
    await evaluate("document.querySelector('.vr-diag-pill')?.click(); true");
  } else if (st.act === "compilefail" || st.act === "emptyout") {
    const src =
      st.act === "compilefail"
        ? "#include <stdio.h>\nint main(void) { int x = ; return 0; }"
        : "#include <stdio.h>\nint main(void) { return 0; }";
    await evaluate(`window.__pilot.lessonSession.setShared(${JSON.stringify(src)}); true`);
    await evaluate(`window.__pilot.collect(${JSON.stringify(src)})`);
    await waitFor("!window.__pilot.session.collecting", 60000);
    if (st.act === "compilefail") await evaluate("document.querySelector('.vr-diag-pill')?.click(); true");
    await sleep(250);
  }
  // 光标归位：CM6 光标位置影响 matching-bracket/选区渲染，而暂停点不同会让
  // 光标落在不同行的括号上（work-start 同机两跑 1.95% 假红的真因）。合成
  // 鼠标事件在 headless 下时灵时不灵（实测两次一跑点中一跑没点中），改走
  // DOM Selection：把选区折叠到 .cm-content 起点并广播 selectionchange，
  // CM6 的 DOM 选区同步层会把它写回 state——无坐标、无命中区。
  await evaluate("window.__pilot.session.breakpoints = []; true");
  const cursorSet = await evaluate(`(() => {
    const el = document.querySelector('.cm-content');
    if (!el) return false;
    el.focus();
    const sel = window.getSelection();
    if (!sel) return false;
    const range = document.createRange();
    range.selectNodeContents(el);
    range.collapse(true);
    sel.removeAllRanges();
    sel.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
    return true;
  })()`);
  if (cursorSet) {
    await evaluate("document.querySelector('.vr-kicker')?.click(); true");
    await sleep(80);
  }
  // 吐司是时间态（trap / 编译失败各弹一条，4.2s 后自清）——截图前点掉，
  // 否则基线随「距采集多久」漂（同机两次 --update 都能哈希不同）。
  await evaluate("document.querySelectorAll('.vr-toast button').forEach((b) => b.click()); true");
  await sleep(120);
  await evaluate(`document.documentElement.setAttribute("data-theme", ${JSON.stringify(st.theme)}); true`);
  await evaluate("document.fonts.ready.then(() => true)");
  await sleep(350);
  await evaluate("document.activeElement instanceof HTMLElement ? (document.activeElement.blur(), true) : true");
  await evaluate("new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r(true))))");
}

/** 掩膜：输出块的「采集 N ms」会随运行浮动——按选择器取包围盒涂灰后再比。 */
async function maskRects() {
  return evaluate(`(() => {
    const sel = ['.vr-out'];
    return sel.map((s) => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) }; }).filter(Boolean);
  })()`);
}

async function shoot(st) {
  const params = { format: "png", fromSurface: true, captureBeyondViewport: false, clip: { x: 0, y: 0, width: st.w, height: st.h, scale: 1 } };
  const r = await send("Page.captureScreenshot", params);
  const img = decodePNG(Buffer.from(r.data, "base64"));
  for (const rect of await maskRects()) maskRect(img, rect);
  return img;
}

function baselinePath(st) {
  return join(BASELINE_DIR, `${st.name}.png`);
}


/** CDP 就绪重试：CI 上 chrome 开端口可能晚于固定 sleep（实测 ECONNREFUSED）。
 *  只重试连接阶段，最多 30s；超时把最后一条错误带出来（fail loud 可诊断）。 */
async function connectWithRetry(port = 9222, timeoutMs = 30000) {
  const t0 = Date.now();
  for (;;) {
    try {
      return await connect(port);
    } catch (e) {
      if (Date.now() - t0 > timeoutMs) throw new Error("CDP " + port + " 在 " + timeoutMs + "ms 内未就绪：" + (e && e.message ? e.message : e));
      await new Promise((r) => setTimeout(r, 500));
    }
  }
}

async function main() {
  await connectWithRetry();
  const states = ONLY ? STATES.filter((s) => s.name.includes(ONLY)) : STATES;
  if (!states.length) throw new Error("--only 没匹配到状态：" + ONLY);

  const indexFile = join(BASELINE_DIR, "index.json");
  if (!UPDATE) {
    if (!existsSync(indexFile)) {
      console.log("::warning::视觉闸未武装：demo/tests/visual/baseline 未入库——需在 CI（windows-latest）跑 workflow_dispatch（visual-baseline）生成并提交基线");
      ws.close();
      return;
    }
    const idx = JSON.parse(readFileSync(indexFile, "utf8"));
    if (idx.platform !== process.platform) {
      console.log(`::warning::视觉闸跳过：基线平台=${idx.platform}，本机=${process.platform}（像素基线不跨 OS 复用；本地只做 --update 预习）`);
      ws.close();
      return;
    }
  }

  mkdirSync(BASELINE_DIR, { recursive: true });
  mkdirSync(DIFF_DIR, { recursive: true });

  let failed = 0;
  const results = [];
  for (const st of states) {
    await setupState(st);
    const shot = await shoot(st);
    const file = baselinePath(st);
    if (UPDATE) {
      writeFileSync(file, encodePNG(shot));
      results.push({ name: st.name, written: true });
      console.log("update", st.name, `${st.w}x${st.h}`, st.theme);
      continue;
    }
    const base = decodePNG(readFileSync(file));
    const d = diffRGBA(base, shot);
    const ok = d.ratio <= THRESHOLD;
    results.push({ name: st.name, ratio: d.ratio, ok, bbox: d.bbox });
    if (!ok) {
      failed++;
      writeFileSync(join(DIFF_DIR, `${st.name}.diff.png`), encodePNG(diffImage(base, shot)));
      console.error(`FAIL ${st.name} diff=${(d.ratio * 100).toFixed(3)}% 变更 ${d.changed}/${d.total}px bbox=${JSON.stringify(d.bbox)} → visual/diff/${st.name}.diff.png`);
    } else {
      console.log(`PASS ${st.name} diff=${(d.ratio * 100).toFixed(3)}%`);
    }
  }
  if (UPDATE) {
    writeFileSync(
      indexFile,
      JSON.stringify({ version: 1, platform: process.platform, arch: process.arch, theme: THEMES, shots: states.map((s) => ({ name: s.name, w: s.w, h: s.h, theme: s.theme })) }, null, 2) + "\n",
    );
    console.log(`visual_regress: 本机基线已写入 ${BASELINE_DIR}（${states.length} 张；不入库——正式基线由 CI Ubuntu 生成）`);
    ws.close();
    return;
  }
  console.log(`visual_regress: ${states.length - failed}/${states.length} 通过（阈值 ${(THRESHOLD * 100).toFixed(1)}%）`);
  ws.close();
  if (failed) process.exit(1);
}

main().catch((e) => {
  console.error("visual_regress 异常:", e?.message ?? e);
  process.exit(1);
});
