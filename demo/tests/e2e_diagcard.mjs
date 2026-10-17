// E2E 实测（F4 残留① 诊断卡）：CDP 驱动 Edge 无头，对 vite 产物做真页面验证。
// 用法（三步，本地资产——CI 无 Edge 不进流水线）：
//   1. cd demo && node node_modules/vite/bin/vite.js build        （产物 dist/）
//   2. node tests/serve_static.mjs 8931                            （静态服，后台）
//   3. msedge --headless=new --remote-debugging-port=9222 --user-data-dir=<tmp> \
//        --no-proxy-server http://127.0.0.1:8931/index.html    （后台）
//      node tests/e2e_diagcard.mjs http://127.0.0.1:8931/          （本脚本，node 25）
// 前置：moonbit/_build 的 wasm-gc 产物须已 cp 到 demo/wasm.wasm（新鲜度见 #123①）。
// 场景：
//   S1 编译失败：未声明变量 → .diag-card.failed + E3023 + badge 计数 + jumpy 点击 → .cm-diagline
//   S2 成功带警：W1019 宏副作用 → .diag-card 非 failed + W1019 + 「1 警告」badge + pp 轨迹折叠展开
//   S3 空态：无诊断程序 → 「无编译期诊断」
// 说明：CDP WebSocket 用 Node 22+ 全局 WebSocket（本脚本经 node 25 实测）；
// /json/list 走 node:http 直连（环境带 HTTP_PROXY，fetch/undici 会被代理
// 拦截致 ECONNREFUSED——本地 CDP 禁走代理；Edge 侧对应加 --no-proxy-server）。
import http from "node:http";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const PAGE = BASE + "index.html";

const BAD = 'int main(void) {\n  int y = 5;\n  return y + z;\n}\n';
const WARN = '#define BAD(x) ((x)+(x))\nint main(void) {\n  int i = 1;\n  int r = BAD(i++);\n  return r;\n}\n';
const CLEAN = 'int main(void) {\n  int a = 1;\n  return a;\n}\n';

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
    const v = await evaluate(expr);
    if (v) return v;
    if (Date.now() - t0 > timeout) throw new Error("waitFor 超时: " + expr.slice(0, 120));
    await sleep(step);
  }
}

async function key(type, key, code, windowsVirtualKeyCode, modifiers = 0, text) {
  await send("Input.dispatchKeyEvent", { type, modifiers, key, code, windowsVirtualKeyCode, text });
}

async function getEditorText() {
  return evaluate("document.querySelector('.cm-content')?.textContent ?? ''");
}

async function setEditor(text) {
  // 真鼠标点击（focus() 在 headless 下不稳——点击坐标来自元素 boundingBox）。
  // 坑（2026-10-16 实测）：Backspace 清空后 CM6 焦点掉到 BODY（空编辑器
  // 失焦），此后 insertText 静默丢失——必须先重点击再插入。
  const box = await evaluate(`(() => { const r = document.querySelector('.cm-content')?.getBoundingClientRect(); return r ? {x: r.x + r.width/2, y: r.y + Math.min(r.height/2, 20)} : null; })()`);
  if (!box) throw new Error("找不到 .cm-content");
  const clickCm = async () => {
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: box.x, y: box.y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: box.x, y: box.y, button: "left", clickCount: 1 });
    await sleep(120);
  };
  await clickCm();
  await key("keyDown", "a", "KeyA", 65, 2 /* ctrl */);
  await key("keyUp", "a", "KeyA", 65, 2);
  await key("keyDown", "Backspace", "Backspace", 8);
  await key("keyUp", "Backspace", "Backspace", 8);
  await sleep(120);
  await clickCm(); // 空文档失焦补救——重点击后再插入
  await send("Input.insertText", { text });
  await sleep(250);
  // 回读校验：内容不符即失败（禁「变量没进产物就下结论」——#123 P2 教训同族）
  const got = await getEditorText();
  if (!got.includes(text.split("\n")[1]?.trim() ?? "\u0000")) {  // 哨兵用转义（字面 NUL 会让 git 判二进制）
    throw new Error("编辑器内容写入失败：回读=" + JSON.stringify(got.slice(0, 80)));
  }
}

async function clickCollect() {
  await evaluate("[...document.querySelectorAll('button')].find(b => b.textContent.includes('采集帧流'))?.click()");
}

async function run() {
  // 1. 发现 page target 并 attach（node:http 直连——禁走环境代理）
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

  // 2. 导航 + 等 boot（versions 徽章就绪）
  await send("Page.navigate", { url: PAGE });
  await waitFor("document.querySelector('.pilot-head .badge b')?.textContent?.length > 3", 30000);
  check("boot 版本徽章", true, await evaluate("document.querySelector('.pilot-head .badge b').textContent"));

  // ── S1 编译失败 ──
  await setEditor(BAD);
  await clickCollect();
  await waitFor("document.querySelector('.diag-card')", 20000);
  const s1 = await evaluate(`(() => {
    const card = document.querySelector('.diag-card');
    return {
      failed: card?.classList.contains('failed') ?? null,
      badges: [...card.querySelectorAll('.dc-badge')].map(b => b.textContent.trim()),
      codes: [...card.querySelectorAll('.diag .code')].map(c => c.textContent.trim()),
      msgs: [...card.querySelectorAll('.diag .msg')].map(c => c.textContent.trim()),
      locs: [...card.querySelectorAll('.diag .loc')].map(c => c.textContent.trim()),
      fixes: [...card.querySelectorAll('.diag .fix')].map(c => c.textContent.trim()),
      jumpy: card.querySelectorAll('.diag.jumpy').length,
      activeTab: document.querySelector('.tab.active')?.textContent?.trim(),
    };
  })()`);
  check("S1 卡片失败态", s1.failed === true, JSON.stringify(s1.failed));
  check("S1 徽章计数", JSON.stringify(s1.badges).includes("编译失败") && JSON.stringify(s1.badges).includes("1 错误"), JSON.stringify(s1.badges));
  check("S1 诊断码/消息/定位", s1.codes[0] === "E3023" && s1.msgs[0].includes("未声明的变量") && s1.locs[0].includes("main.c 行 3:14"), JSON.stringify({ codes: s1.codes, locs: s1.locs, msgs: s1.msgs }));
  check("S1 修复建议", s1.fixes.length === 1 && s1.fixes[0].startsWith("✚"), JSON.stringify(s1.fixes));
  check("S1 自动切 run tab", s1.activeTab === "运行", String(s1.activeTab));
  check("S1 jumpy 行数", s1.jumpy === 1, String(s1.jumpy));

  // jumpy 点击 → .cm-diagline 高亮 + 状态行
  await evaluate("document.querySelector('.diag.jumpy')?.click()");
  await sleep(400);
  const s1b = await evaluate(`(() => ({
    diagline: !!document.querySelector('.cm-diagline'),
    focused: document.activeElement?.classList?.contains('cm-content') ?? false,
    statusLine: document.querySelector('.status-line')?.textContent?.trim() ?? '',
  }))()`);
  check("S1 跳转高亮 cm-diagline", s1b.diagline === true, JSON.stringify(s1b));
  check("S1 status 行会话态文案", s1b.statusLine.includes("编译失败") && s1b.statusLine.includes("条诊断"), s1b.statusLine);

  // ── S2 成功带警（W1019）──
  await setEditor(WARN);
  await clickCollect();
  await waitFor("document.querySelector('.diag-card:not(.failed) .diag.warning')", 20000);
  const s2 = await evaluate(`(() => {
    const card = document.querySelector('.diag-card');
    const frameCount = document.querySelector('.frame-count')?.textContent?.trim() ?? '';
    return {
      failed: card?.classList.contains('failed') ?? null,
      badges: [...card.querySelectorAll('.dc-badge')].map(b => b.textContent.trim()),
      codes: [...card.querySelectorAll('.diag .code')].map(c => c.textContent.trim()),
      frameCount,
      traceToggle: card?.querySelector('.dc-trace-toggle')?.textContent?.trim() ?? '',
    };
  })()`);
  check("S2 非失败态 + 警告徽章", s2.failed === false && JSON.stringify(s2.badges).includes("1 警告"), JSON.stringify({ failed: s2.failed, badges: s2.badges }));
  check("S2 W1019 渲染", s2.codes[0] === "W1019", JSON.stringify(s2.codes));
  // 帧计数口径放宽（采集完自动播放拍板后 at 不恒为 1）——断言总帧数 > 1
  check("S2 采集照常（帧数 > 1）", /帧 \d+\/(\d+)/.test(s2.frameCount) && Number(/帧 \d+\/(\d+)/.exec(s2.frameCount)[1]) > 1, s2.frameCount);
  check("S2 pp 轨迹折叠钮", s2.traceToggle.includes("宏展开轨迹") && s2.traceToggle.includes("1 条"), s2.traceToggle);

  // 展开 pp 轨迹
  await evaluate("document.querySelector('.dc-trace-toggle')?.click()");
  await sleep(200);
  const s2b = await evaluate("document.querySelector('.pp-line')?.textContent?.trim() ?? ''");
  check("S2 pp 轨迹展开内容", s2b.includes("BAD(i ++)"), s2b);

  // ── S3 干净程序（零诊断）──
  await setEditor(CLEAN);
  await clickCollect();
  await waitFor("document.querySelector('.diag-card .dc-empty')", 20000);
  const s3 = await evaluate(`(() => ({
    empty: document.querySelector('.diag-card .dc-empty')?.textContent?.trim() ?? '',
    failed: document.querySelector('.diag-card')?.classList.contains('failed') ?? null,
    bars: document.querySelectorAll('.av-item').length,
  }))()`);
  check("S3 零诊断文案", s3.empty === "无编译期诊断" && s3.failed === false, JSON.stringify(s3));

  // ── S4 断点链（F4 残留④）：bp gutter 点击 → 点 + 行装饰 → 再点清 ──
  // y 坐标取 lineNumbers gutter 第 4 行的元素（CM6 gutter 单元格只有标记行
  // 才渲染——行号 gutter 每行都有，是最稳的行定位锚）；x 取 bp gutter 中线
  const bpBox = await evaluate(`(() => {
    const lnEl = document.querySelectorAll('.cm-lineNumbers .cm-gutterElement')[3];
    const g = document.querySelector('.cm-bpgutter');
    if (!lnEl || !g) return null;
    const r = lnEl.getBoundingClientRect(), gr = g.getBoundingClientRect();
    return { x: Math.round(gr.x + gr.width / 2), y: Math.round(r.y + r.height / 2) };
  })()`);
  if (!bpBox) throw new Error("bp gutter / 行号 gutter 定位失败");
  const clickBp = async () => {
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: bpBox.x, y: bpBox.y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: bpBox.x, y: bpBox.y, button: "left", clickCount: 1 });
    await sleep(350);
  };
  await clickBp();
  const s4a = await evaluate(`(() => {
    // 真标记点 ≠ initialSpacer 占位点（spacer 被 CM6 置 visibility:hidden）——
    // 曾把 spacer 误报成断点已渲染（dot:true 假阳性），按可见性过滤
    const dots = [...document.querySelectorAll('.cm-bpgutter .bp-dot')];
    const visible = dots.filter((d) => getComputedStyle(d).visibility !== 'hidden').length;
    return { visible, bpline: !!document.querySelector('.cm-bpline') };
  })()`);
  check("S4 断点开启（gutter 可见点 + 行装饰）", s4a.visible === 1 && s4a.bpline === true, JSON.stringify(s4a));
  await clickBp();
  const s4b = await evaluate(`(() => {
    const dots = [...document.querySelectorAll('.cm-bpgutter .bp-dot')];
    const visible = dots.filter((d) => getComputedStyle(d).visibility !== 'hidden').length;
    return { visible, bpline: !!document.querySelector('.cm-bpline') };
  })()`);
  check("S4 断点关闭（再点全清）", s4b.visible === 0 && s4b.bpline === false, JSON.stringify(s4b));

  // ── S5 断点采集行为（A1，#140）：挂断点后采集必须停在断点——修复前
  // worker 收 bpLines 后零使用（无 breakpoints.set、循环无 paused 分支），
  // 采集全程跑完不停。判据走 window.__pilot 单源（stopped 文案 + 帧数
  // 双判据），是 S4 纯 UI 锚之外的行为面补强。
  const BPLOOP = 'int main(void) {\n  int s = 0;\n  for (int i = 0; i < 10; i = i + 1)\n    s = s + i;\n  return s;\n}\n';
  await setEditor(BPLOOP); // 行 4 = 循环体首执行行
  await clickBp();
  await clickCollect();
  let s5 = null;
  for (let i = 0; i < 60; i++) {
    s5 = await evaluate(`({ stopped: window.__pilot?.session?.stopped ?? '', frames: window.__pilot?.session?.frames?.length ?? -1 })`);
    if (s5.stopped) break;
    await sleep(500);
  }
  check("S5 断点采集停在断点（paused 停止 + 文案）",
    !!s5 && /断点/.test(s5.stopped) && s5.frames > 0, JSON.stringify(s5));
  await clickBp(); // 清断点还场

  const fails = results.filter((r) => !r.ok).length;
  console.log(`\n===== ${results.length - fails}/${results.length} 通过${fails ? "，失败 " + fails + " 项" : ""} =====`);
  ws.close();
  process.exit(fails ? 1 : 0);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
