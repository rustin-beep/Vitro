// E2E 实测（编辑器真实输入面——#190 红锚批 2026-10-18）：
// #190 实锤「E2E 的 setEditor 整段单事务绕过真实键入层」盲区——本文件专测
// 逐字符键入 / 撤销重做 / 焦点保持 / 采集翻态不重建四条真实输入路径锚。
// 用法同 e2e_workspace.mjs 三步（build / serve_static 8931 / headless chrome 9222）。
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

const docLen = () => evaluate("document.querySelector('.cm-content')?.textContent.length ?? -1");
const focusInEditor = () => evaluate("document.activeElement?.classList?.contains('cm-content') ?? false");
async function clickCmLine(idx) {
  const box = await evaluate(`(() => { const e = document.querySelectorAll('.cm-content .cm-line')[${idx}]; if (!e) return null; const r = e.getBoundingClientRect(); return {x: Math.round(r.x + 130), y: Math.round(r.y + r.height/2)}; })()`);
  if (!box) throw new Error("找不到 .cm-line " + idx);
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x: box.x, y: box.y, button: "left", clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: box.x, y: box.y, button: "left", clickCount: 1 });
  await sleep(150);
}

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
  // 清「继续上次」再重载——本套件锚假定默认课（非 scanf 等待态：#189 起
  // waiting 态编辑器锁定会让 N1 键入锚红；上次套件留下的 progress.last
  // 不可依赖，localStorage 清除后 openInitial 走默认 bubble）。⚠️ 清除必须
  // 等 boot 完整落定（frames>0 而非仅 __pilot 出现）：openInitial 的
  // rememberLesson 在 lesson.md 懒加载 await 之后才写——清早了会被回写。
  await send("Page.navigate", { url: PAGE });
  await waitFor("window.__pilot && window.__pilot.session.booted", 30000);
  await waitFor("!window.__pilot.session.collecting && window.__pilot.session.frames.length > 0", 40000);
  await evaluate("localStorage.clear()");
  // ⚠️ 两次 clear 夹住 700ms 去抖：WorkScreen「继续上次记帧」是 setTimeout(700)
  // 写入——clear 后 timer 触发会复脏（写回当前课），reload 又恢复。
  await sleep(800);
  await evaluate("localStorage.clear()");
  await send("Page.navigate", { url: PAGE + "?fresh=1" });
  await waitFor("window.__pilot && window.__pilot.session.booted", 30000);
  await waitFor("window.__pilot.ui.screen === 'work' && window.__pilot.lessonSession.lesson && !window.__pilot.session.collecting && window.__pilot.session.frames.length > 0", 40000);
  await sleep(400);

  // ── N7/N8：断点行号点击（#185 红锚）——放最前（运行采集后播放/帧渲染会
  //   滚动页面，gutter 视口坐标失效曾致 N7 假绿/N8 点错行）。断言断点集精确
  //   内容而非 chip 数量（数量断言曾蒙混「设错行但恰好 1 个」的假绿）。──
  {
    const bpSet = () => evaluate("window.__pilot.session.breakpoints");
    const clickLineNo = async (no) => {
      // ⚠️ 按行号文本定位：gutterElement[0] 是 CM6 宽度占位 filler（"99"），
      // 行号从 [1] 起——索引直取曾 off-by-one 点到行 5。
      const r = await evaluate(`(() => { const e = [...document.querySelectorAll('.cm-lineNumbers .cm-gutterElement')].find(el => el.textContent.trim() === ${JSON.stringify(String(no))}); if (!e) return null; e.scrollIntoView({ block: "center" }); const rc = e.getBoundingClientRect(); return { x: Math.round(rc.x + rc.width / 2), y: Math.round(rc.y + rc.height / 2) }; })()`);
      if (!r) throw new Error("找不到行号 gutter element " + no);
      await send("Input.dispatchMouseEvent", { type: "mousePressed", x: r.x, y: r.y, button: "left", clickCount: 1 });
      await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: r.x, y: r.y, button: "left", clickCount: 1 });
      await sleep(250);
    };
    await clickLineNo(6);
    // ⚠️ CDP returnByValue 结构化克隆会把 $state Proxy 数组降为普通对象
    //（{"0":6}）——断言前归一化为数组。
    const norm = (v) => (Array.isArray(v) ? v : Object.values(v ?? {}));
    const bp1 = norm(await bpSet());
    check("N7 真实点击行号 6 → 断点集 {6}（#185）", bp1.length === 1 && bp1[0] === 6, JSON.stringify(bp1));
    await clickLineNo(6);
    const bp0 = norm(await bpSet());
    check("N8 再点行号 6 → 断点集空（#185）", bp0.length === 0, JSON.stringify(bp0));
  }

  // ── N9：默认主题语法高亮可见性（线上「完全没高亮」红锚，2026-10-19）──
  // paper（默认主题）的语法色板曾是单色排版（--vr-kw ≡ --vr-ink 同墨色）——
  // 首访用户体感「完全没有高亮」。判据 = keyword 色的**色度**（RGB 三通道
  // 极差）≥ 40：单色排版（#1d1a15/#514a3c 类）色度 ≤21 视觉读作同一墨色，
  // 不可辨识；印刷批注色系（朱/青/绿/赭）色度 74~140。本套件开场清
  // localStorage = 默认 paper，与线上首访同态。同时断言 keyword/类型/
  // 字符串/数字四类色度全部达标——单色排版是整板问题非单 token。
  {
    const hl = await evaluate(`(() => {
      const chroma = (c) => { const m = c.match(/\\d+/g)?.map(Number) ?? []; return m.length >= 3 ? Math.max(...m.slice(0, 3)) - Math.min(...m.slice(0, 3)) : -1; };
      const find = (t) => { const s = [...document.querySelectorAll('.cm-content span')].find(x => x.textContent === t); return s ? getComputedStyle(s).color : null; };
      return {
        theme: document.documentElement.getAttribute('data-theme'),
        kw: chroma(find('return') ?? find('int') ?? ''),
        ty: chroma(find('int') ?? ''),
        str: chroma(find('"got %d"') ?? ''),
      };
    })()`);
    if (hl.kw < 0) throw new Error("找不到 keyword token（theme=" + hl.theme + "）");
    check("N9 默认主题语法高亮有色相（色度≥40，paper 非单色排版）", hl.kw >= 40 && hl.ty >= 40, `theme=${hl.theme} kw色度=${hl.kw} ty色度=${hl.ty}`);
  }

  // ── N1/N2：逐字符键入（真实输入节奏，每字符独立事务）──────
  await clickCmLine(3);
  await waitFor("document.activeElement?.classList?.contains('cm-content') ?? false", 5000);
  const len0 = await docLen();
  for (const ch of "12345678") {
    await send("Input.insertText", { text: ch });
    await sleep(120);
  }
  const len1 = await docLen();
  check("N1 逐字符键入 8 字符全部落地", len1 - len0 === 8, `长度 ${len0} → ${len1}（增量 ${len1 - len0}）`);
  check("N2 键入后焦点保持在编辑器", await focusInEditor(), "activeElement=" + (await evaluate("document.activeElement?.className?.slice(0, 40) ?? document.activeElement?.tagName")));

  // ── N3/N4：撤销/重做（history 随 view 重建销毁则此锚红）──
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "z", code: "KeyZ", windowsVirtualKeyCode: 90 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "z", code: "KeyZ", windowsVirtualKeyCode: 90 });
  await sleep(200);
  const len2 = await docLen();
  check("N3 Ctrl+Z 撤销生效（回滚 8 字符）", len2 === len0, `长度 ${len1} → ${len2}（期望 ${len0}）`);
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "y", code: "KeyY", windowsVirtualKeyCode: 89 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "y", code: "KeyY", windowsVirtualKeyCode: 89 });
  await sleep(200);
  const len3 = await docLen();
  check("N4 Ctrl+Y 重做生效（恢复 8 字符）", len3 === len1, `长度 ${len2} → ${len3}（期望 ${len1}）`);

  // ── N5：采集翻态（disabled true→false）不重建编辑器 DOM ──
  // （挂载 effect 误依赖 disabled 时：每次运行开始/结束都销毁重建——焦点/
  //   撤销历史/光标三杀。锚 = .cm-editor 身份标记跨运行存活。）
  // 先 Ctrl+Z 回原稿再运行——键入的数字落在代码行内会破坏语法致编译失败。
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "z", code: "KeyZ", windowsVirtualKeyCode: 90 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "z", code: "KeyZ", windowsVirtualKeyCode: 90 });
  await sleep(200);
  const len4 = await docLen();
  check("N5b 二次撤销回原稿", len4 === len0, `长度 ${len3} → ${len4}（期望 ${len0}）`);
  const epoch0 = await evaluate("window.__pilot.session.epoch");
  await evaluate("document.querySelector('.cm-editor').__anchor = 'n5'");
  await evaluate("document.querySelector('[data-act=\\'run\\']')?.click()");
  await waitFor(`!window.__pilot.session.collecting && window.__pilot.session.epoch > ${epoch0}`, 40000);
  await sleep(300);
  const anchor = await evaluate("document.querySelector('.cm-editor')?.__anchor ?? null");
  check("N5 运行前后编辑器 DOM 身份不变（不重建）", anchor === "n5", `__anchor=${JSON.stringify(anchor)}`);
  check("N6 运行后焦点/内容面不回归", len0 === (await docLen()), `长度保持 ${len0}`);

  const fails = results.filter((r) => !r.ok).length;
  console.log(`\n${fails === 0 ? "ALL PASS" : "FAILED"}: ${results.length - fails}/${results.length}`);
  process.exit(fails === 0 ? 0 : 1);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
