// E2E 实测（F4 残留② 工作区）：CDP 驱动 Edge 无头 + mock FSA 注入
// （window.showDirectoryPicker 伪造——真页面里跑完打开→chips→切换→dirty→
// 保存→compile.files 多文件采集全链；磁盘写回经 mock createWritable 记录断言）。
// 用法同 e2e_diagcard.mjs（build → serve → Edge --no-proxy-server → 本脚本 node 25）。
import http from "node:http";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const PAGE = BASE + "index.html";

const MAIN_C = '#include <stdio.h>\n#include "util.h"\n\nint main(void) {\n  printf("%d\\n", add(2, 3));\n  return 0;\n}\n';
const UTIL_H = "int add(int a, int b);\n";
const UTIL_C = "int add(int a, int b) {\n  return a + b;\n}\n";
const EXTRA_C = "int extra(void) {\n  return 42;\n}\n";

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
  // 1. 发现 page target 并 attach（node:http 直连——禁走环境代理）。
  // 多 page 时按 URL 过滤取最后一个——陈旧实例残留的同 URL page 会挂死（实锤）
  const targets = await new Promise((resolve, reject) => {
    http.get({ host: "127.0.0.1", port: 9222, path: "/json/list" }, (res) => {
      let b = ""; res.on("data", (c) => (b += c)); res.on("end", () => { try { resolve(JSON.parse(b)); } catch (e) { reject(e); } });
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
      const p = pending.get(m.id); pending.delete(m.id);
      if (m.error) p.reject(new Error(JSON.stringify(m.error))); else p.resolve(m.result);
    }
  };
  await send("Page.enable"); await send("Runtime.enable");
  await send("Page.navigate", { url: PAGE });
  await waitFor("document.querySelector('.pilot-head .badge b')?.textContent?.length > 3", 30000);

  // ── mock FSA 注入（boot 后、点开按钮前）────────────────────────
  await evaluate(`(() => {
    const FS = ${JSON.stringify({
      "main.c": MAIN_C, "util.h": UTIL_H, "util.c": UTIL_C,
      "sub/extra.c": EXTRA_C, "node_modules/junk.c": "int junk(void){return 0;}",
      ".hidden/x.c": "int x(void){return 0;}", "notes.txt": "not a source",
    })};
    window.__wsWrites = {};
    window.__confirmAnswer = true;
    window.confirm = () => window.__confirmAnswer;
    const dirEntries = function* (prefix) {
      const names = new Set();
      for (const k of Object.keys(FS)) {
        const rest = k.startsWith(prefix) ? k.slice(prefix.length) : null;
        if (rest === null || rest === "") continue;
        const seg = rest.split("/")[0];
        if (names.has(seg)) continue;
        names.add(seg);
        if (rest.includes("/")) {
          yield { kind: "directory", name: seg, values: () => dirEntries(prefix + seg + "/") };
        } else {
          yield { kind: "file", name: seg, getFile: async () => ({ size: FS[prefix + seg].length, text: async () => FS[prefix + seg] }),
            createWritable: async () => ({ write: async (d) => { window.__wsWrites[prefix + seg] = d; }, close: async () => {} }) };
        }
      }
    };
    window.showDirectoryPicker = async () => ({ name: "mockproj", kind: "directory", values: () => dirEntries("") });
  })()`);

  // ── W1 打开工作区 ──
  await evaluate("[...document.querySelectorAll('.ws-bar .ws-open')].find(b => b.textContent.includes('打开文件夹'))?.click()");
  await waitFor("document.querySelectorAll('.ws-chip').length === 4", 20000);
  const w1 = await evaluate(`(() => ({
    chips: [...document.querySelectorAll('.ws-chip')].map(c => c.textContent.trim()),
    name: document.querySelector('.ws-name')?.textContent?.trim(),
    active: document.querySelector('.ws-chip.on')?.textContent?.trim(),
    editor: document.querySelector('.cm-content')?.textContent ?? '',
    openGone: ![...document.querySelectorAll('.ws-bar .ws-open')].some(b => b.textContent.includes('打开文件夹')) === false,
  }))()`);
  check("W1 chips 四文件（剪枝/过滤生效）", JSON.stringify(w1.chips) === JSON.stringify(["main.c", "util.h", "util.c", "extra.c"]), JSON.stringify(w1.chips));
  check("W1 目录名 + active=main.c", w1.name === "mockproj（4）" && w1.active === "main.c", w1.name + " / " + w1.active);
  check("W1 编辑器载入 main.c 内容", w1.editor.includes('#include "util.h"') && w1.editor.includes("add(2, 3)"), w1.editor.slice(0, 60));

  // ── W2 多文件采集（compile.files + vfs include）──
  await evaluate("[...document.querySelectorAll('button')].find(b => b.textContent.includes('采集帧流'))?.click()");
  await waitFor("document.querySelector('.ch.stdout')", 20000);
  const w2 = await evaluate("document.querySelector('.ch.stdout')?.textContent?.trim() ?? ''");
  check("W2 compile.files 多单元 + include 解析（stdout=5）", w2 === "5", JSON.stringify(w2));

  // ── W3 dirty 标记 + 编辑器键入同步 ──
  const boxNow = () => evaluate("(() => { const r = document.querySelector('.cm-content')?.getBoundingClientRect(); return r ? {x: Math.round(r.x + r.width/2), y: Math.round(r.y + Math.min(r.height/2, 20))} : null; })()");
  const clickCm = async () => {
    const box = await boxNow(); // 每次重算——编辑器随内容自动增高，旧坐标会点到编辑器外（W6 实锤）
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: box.x, y: box.y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: box.x, y: box.y, button: "left", clickCount: 1 });
    await sleep(120);
  };
  await clickCm();
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "a", code: "KeyA", windowsVirtualKeyCode: 65 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "a", code: "KeyA", windowsVirtualKeyCode: 65 });
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 });
  await sleep(120);
  await clickCm(); // 空文档失焦补救（#123 同族坑）
  await send("Input.insertText", { text: MAIN_C.replace("add(2, 3)", "add(20, 30)") });
  await sleep(300);
  const w3 = await evaluate(`(() => ({
    dirtyMain: document.querySelector('.ws-chip')?.classList.contains('dirty'),
    saveEnabled: !document.querySelector('.ws-save')?.disabled,
  }))()`);
  check("W3 键入 → main.c chip dirty + 保存可用", w3.dirtyMain === true && w3.saveEnabled === true, JSON.stringify(w3));

  // ── W4 保存写回磁盘（mock createWritable 记录）──
  await evaluate("document.querySelector('.ws-save')?.click()");
  await waitFor("(window.__wsWrites['main.c'] ?? '').includes('add(20, 30)')", 8000);
  const w4 = await evaluate(`(() => ({
    written: window.__wsWrites['main.c'] ?? '',
    dirtyAfter: document.querySelector('.ws-chip')?.classList.contains('dirty'),
    saveDisabled: document.querySelector('.ws-save')?.disabled,
  }))()`);
  check("W4 保存写回 + dirty 清除", w4.written.includes("add(20, 30)") && w4.dirtyAfter === false && w4.saveDisabled === true, JSON.stringify({ len: w4.written.length, dirty: w4.dirtyAfter }));

  // ── W5 切换文件：缓冲保留 + active 迁移 ──
  await evaluate("[...document.querySelectorAll('.ws-chip')].find(c => c.textContent.includes('util.c'))?.click()");
  await sleep(300);
  const w5a = await evaluate(`(() => ({
    active: document.querySelector('.ws-chip.on')?.textContent?.trim(),
    editor: document.querySelector('.cm-content')?.textContent ?? '',
  }))()`);
  check("W5 切到 util.c（编辑器 = util.c 内容）", w5a.active === "util.c" && w5a.editor.includes("int add(int a, int b)"), w5a.active);
  await evaluate("[...document.querySelectorAll('.ws-chip')].find(c => c.textContent.includes('main.c'))?.click()");
  await sleep(300);
  const w5b = await evaluate("document.querySelector('.cm-content')?.textContent ?? ''");
  check("W5 切回 main.c（缓冲保留 add(20,30)）", w5b.includes("add(20, 30)"), w5b.slice(0, 60));

  // ── W6 Ctrl+S 保存（改 util.c 后快捷键写回）──
  await evaluate("[...document.querySelectorAll('.ws-chip')].find(c => c.textContent.includes('util.c'))?.click()");
  await sleep(400);
  await clickCm();
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "a", code: "KeyA", windowsVirtualKeyCode: 65 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "a", code: "KeyA", windowsVirtualKeyCode: 65 });
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 });
  await sleep(120);
  await clickCm();
  await send("Input.insertText", { text: UTIL_C.replace("a + b", "a * b") });
  await sleep(300);
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "s", code: "KeyS", windowsVirtualKeyCode: 83 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "s", code: "KeyS", windowsVirtualKeyCode: 83 });
  await waitFor("(window.__wsWrites['util.c'] ?? '').includes('a * b')", 8000);
  check("W6 Ctrl+S 写回 util.c（a*b）", true, (await evaluate("window.__wsWrites['util.c'] ?? ''")).slice(0, 50));

  // ── W7 关闭 guard：dirty 时 confirm(false) 不关 / confirm(true) 关 ──
  await clickCm();
  await send("Input.insertText", { text: "\n// dirty again" });
  await sleep(300);
  const w7pre = await evaluate(`(() => ({
    dirty: [...document.querySelectorAll('.ws-chip')].map(c=>c.textContent.trim()+':'+c.classList.contains('dirty')),
    editorTail: (document.querySelector('.cm-content')?.textContent ?? '').slice(-30),
    saveDisabled: document.querySelector('.ws-save')?.disabled,
  }))()`);
  console.log("W7 pre:", JSON.stringify(w7pre));
  await evaluate("window.__confirmAnswer = false");
  await evaluate("document.querySelector('.ws-close')?.click()");
  await sleep(300);
  const w7a = await evaluate("document.querySelectorAll('.ws-chip').length");
  check("W7 confirm(false) → 工作区不关", w7a === 4, "chips=" + w7a);
  await evaluate("window.__confirmAnswer = true");
  await evaluate("document.querySelector('.ws-close')?.click()");
  await sleep(300);
  const w7b = await evaluate("({ chips: document.querySelectorAll('.ws-chip').length, barGone: !document.querySelector('.ws-name') })");
  check("W7 confirm(true) → 关闭 + chips/name 清", w7b.chips === 0 && w7b.barGone === true, JSON.stringify(w7b));

  // ── W8 关闭后入口仍在（可再开）──
  const w8 = await evaluate("[...document.querySelectorAll('.ws-bar .ws-open')].some(b => b.textContent.includes('打开文件夹'))");
  check("W8 入口常驻（可重新打开）", w8 === true, String(w8));

  // ── W9 点课：叙述懒加载渲染（glob ?url 交付格式真源链）──
  // 形态事实：叙述面板挂在「内容」tab（F4-9b 既定——内容 tab=课程树+叙述），
  // 点课即切「运行」tab（自动采集语义）——断言须切回内容 tab 看 .cnote
  await evaluate("[...document.querySelectorAll('.tab')].find(t => t.textContent.trim() === '内容')?.click()");
  await sleep(300);
  await evaluate("[...document.querySelectorAll('button.lesson')].find(b => b.querySelector('.lid')?.textContent === 'bubble')?.click()");
  await waitFor("document.querySelector('.tab.active')?.textContent?.trim() === '运行'", 15000);
  await evaluate("[...document.querySelectorAll('.tab')].find(t => t.textContent.trim() === '内容')?.click()");
  await waitFor("document.querySelector('.cnote')", 15000);
  const w9 = await evaluate(`(() => ({
    title: document.querySelector('.cnote h1')?.textContent?.trim() ?? '',
    hasRealBlock: (document.querySelector('.cnote')?.textContent ?? '').includes('这门课在做什么'),
    blockTags: [...document.querySelectorAll('.cnote > *')].map(e => e.tagName.toLowerCase()),
  }))()`);
  check("W9 叙述面板渲染真源（glob 懒加载）", w9.hasRealBlock === true && w9.title.includes("冒泡排序"), JSON.stringify(w9).slice(0, 200));

  // ── W10 点课 guard：dirty 工作区 + confirm(false) 不切 / confirm(true) 保存后切 ──
  await evaluate("[...document.querySelectorAll('.ws-bar .ws-open')].find(b => b.textContent.includes('打开文件夹'))?.click()");
  await waitFor("document.querySelectorAll('.ws-chip').length === 4", 20000);
  await clickCm();
  await send("Input.insertText", { text: "\n// guard dirty" });
  await sleep(300);
  await evaluate("window.__confirmAnswer = false");
  await evaluate("[...document.querySelectorAll('.tab')].find(t => t.textContent.trim() === '内容')?.click()");
  await sleep(200);
  // V5 课程树默认收起算法章——点算法课前先展开「排序」章（用户路径如实反映）
  await evaluate("[...document.querySelectorAll('button.chap-head')].find(b => b.textContent.includes('排序'))?.click()");
  await sleep(300);
  await evaluate("[...document.querySelectorAll('button.lesson')].find(b => b.querySelector('.lid')?.textContent === 'bubble_sort')?.click()");
  await sleep(400);
  const w10a = await evaluate(`(() => ({
    chips: document.querySelectorAll('.ws-chip').length,
    onContent: document.querySelector('.tab.active')?.textContent?.trim(),
  }))()`);
  check("W10 confirm(false) → 选课中止（工作区不关、不跳 tab）", w10a.chips === 4 && w10a.onContent === "内容", JSON.stringify(w10a));
  await evaluate("window.__confirmAnswer = true");
  await evaluate("[...document.querySelectorAll('button.lesson')].find(b => b.querySelector('.lid')?.textContent === 'bubble_sort')?.click()");
  await waitFor("document.querySelector('.tab.active')?.textContent?.trim() === '运行'", 10000);
  const w10b = await evaluate(`(() => ({
    chips: document.querySelectorAll('.ws-chip').length,
    saved: (window.__wsWrites['main.c'] ?? '').includes('guard dirty'),
  }))()`);
  check("W10 confirm(true) → 保存 + 关工作区 + 切运行 tab", w10b.chips === 0 && w10b.saved === true, JSON.stringify(w10b));

  // ── W11 主题切换 + 刷新持久化（localStorage 真恢复，非"仅调了 storeSet"）──
  const theme0 = await evaluate("document.documentElement.getAttribute('data-theme')");
  await evaluate("[...document.querySelectorAll('button.icon-btn')].find(b => b.title === '切换主题')?.click()");
  await sleep(300);
  const theme1 = await evaluate("document.documentElement.getAttribute('data-theme')");
  check("W11 主题切换生效（data-theme 变更）", theme0 !== theme1, theme0 + " → " + theme1);
  await send("Page.navigate", { url: PAGE });
  await waitFor("document.querySelector('.pilot-head .badge b')?.textContent?.length > 3", 30000);
  await sleep(400);
  const theme2 = await evaluate("document.documentElement.getAttribute('data-theme')");
  check("W11 刷新后主题保持（localStorage 持久化真恢复）", theme2 === theme1, "刷新后 " + theme2 + "（期望 " + theme1 + "）");

  // ── W12 分享往返（点分享 → #z1. 片段 → 重载还原编辑器）──
  const shareProg = "int main(void) {\n  return 7;\n}\n";
  const sbox = await evaluate("(() => { const r = document.querySelector('.cm-content')?.getBoundingClientRect(); return r ? {x: Math.round(r.x + r.width/2), y: Math.round(r.y + Math.min(r.height/2, 20))} : null; })()");
  const clickEd = async () => {
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: sbox.x, y: sbox.y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: sbox.x, y: sbox.y, button: "left", clickCount: 1 });
    await sleep(150);
  };
  await clickEd();
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "a", code: "KeyA", windowsVirtualKeyCode: 65 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "a", code: "KeyA", windowsVirtualKeyCode: 65 });
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 });
  await sleep(150);
  await clickEd(); // 空文档后焦点掉 BODY（头注坑）——重点击再键入
  await send("Input.insertText", { text: shareProg });
  await sleep(300);
  // 分享按钮在采集中禁用——等就绪（W10 的自动采集可能仍在跑）
  await waitFor("(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === '分享链接'); return !!b && !b.disabled; })()", 20000);
  await evaluate("[...document.querySelectorAll('button')].find(b => b.textContent.trim() === '分享链接')?.click()");
  await sleep(600);
  const hash = await evaluate("location.hash");
  check("W12 分享写入 #z1. 片段", typeof hash === "string" && hash.startsWith("#z1."), String(hash).slice(0, 46));
  await send("Page.navigate", { url: PAGE + hash });
  await waitFor("document.querySelector('.pilot-head .badge b')?.textContent?.length > 3", 30000);
  await sleep(800);
  const restored = await evaluate("document.querySelector('.cm-content')?.textContent ?? ''");
  check("W12 重载后编辑器还原分享代码（unpackSource 链）", restored.includes("return 7"), JSON.stringify(restored).slice(0, 70));

  // ── W13 回放交互（播放/单步/seek/粒度——此前只有快照与帧数文本）──
  {
    // 当前编辑器是 W12 还原的分享代码——直接采集（自足场景，不依赖前面帧）
    await evaluate("[...document.querySelectorAll('button')].find(b => b.textContent.includes('采集帧流'))?.click()");
    await waitFor("document.querySelector('.frame-count')?.textContent?.includes('/')", 25000);
    const parseCount = (t) => { const m = /帧 (\d+)\/(\d+)/.exec(t || ""); return m ? { at: +m[1], total: +m[2] } : null; };
    const c0 = parseCount(await evaluate("document.querySelector('.frame-count')?.textContent"));
    check("W13 采集后帧计数可见", !!c0 && c0.total > 1, JSON.stringify(c0));
    // 单步 ±1
    await evaluate("document.querySelector('[aria-label=\"下一帧\"]')?.click()");
    await sleep(200);
    const c1 = parseCount(await evaluate("document.querySelector('.frame-count')?.textContent"));
    check("W13 下一帧 +1", !!c1 && c1.at === c0.at + 1, JSON.stringify([c0, c1]));
    await evaluate("document.querySelector('[aria-label=\"上一帧\"]')?.click()");
    await sleep(200);
    const c2 = parseCount(await evaluate("document.querySelector('.frame-count')?.textContent"));
    check("W13 上一帧 -1", !!c2 && c2.at === c0.at, JSON.stringify([c1, c2]));
    // 播放 → 帧推进 → 暂停
    // 注意：7 帧 @30fps ≈ 233ms——探测窗口必须小于播放总时长，否则读到的
    // 已是"播完回弹"状态（首跑实测 600ms 必假红）；80ms ≈ 2-3 帧。
    await evaluate("[...document.querySelectorAll('button')].find(b => b.textContent.includes('播放'))?.click()");
    await sleep(80);
    const playing = await evaluate("[...document.querySelectorAll('button')].some(b => b.textContent.includes('暂停'))");
    const c3 = parseCount(await evaluate("document.querySelector('.frame-count')?.textContent"));
    check("W13 播放推进帧", !!playing && !!c3 && c3.at > c2.at, playing + " " + JSON.stringify(c3));
    await evaluate("[...document.querySelectorAll('button')].find(b => b.textContent.includes('暂停'))?.click()");
    await sleep(300);
    const c4 = parseCount(await evaluate("document.querySelector('.frame-count')?.textContent"));
    await sleep(300);
    const c5 = parseCount(await evaluate("document.querySelector('.frame-count')?.textContent"));
    check("W13 暂停后帧不再推进", !!c4 && !!c5 && c4.at === c5.at, JSON.stringify([c4, c5]));
    // 滑条 seek 到末帧
    await evaluate(`(() => { const r = document.querySelector('input[aria-label="帧滑条"]'); if (!r) return; r.value = r.max; r.dispatchEvent(new Event('input', { bubbles: true })); })()`);
    await sleep(300);
    const c6 = parseCount(await evaluate("document.querySelector('.frame-count')?.textContent"));
    check("W13 滑条 seek 到末帧", !!c6 && c6.at === c6.total, JSON.stringify(c6));
    // 粒度切换：指令级帧数 > 语句级帧数
    const totalOf = async () => parseCount(await evaluate("document.querySelector('.frame-count')?.textContent"))?.total ?? -1;
    await evaluate("[...document.querySelectorAll('.gran button')].find(b => b.textContent.includes('指令级'))?.click()");
    await sleep(500);
    const tInsn = await totalOf();
    await evaluate("[...document.querySelectorAll('.gran button')].find(b => b.textContent.includes('语句级'))?.click()");
    await sleep(500);
    const tStmt = await totalOf();
    check("W13 粒度切换改变帧口径（指令级 > 语句级）", tInsn > tStmt && tStmt > 0, `insn=${tInsn} stmt=${tStmt}`);
  }

  // ── W14 设置面板（五主题 / 字号 / 动效 + 持久化）──
  {
    await evaluate("document.querySelector('[data-settings]')?.click()");
    await waitFor("!!document.querySelector('.settings-float')", 5000);
    // 五主题逐个点：data-theme 跟随；glass/soft 为夜（data-shade=night）
    const themes = ["ice", "rose", "paper", "glass", "soft"];
    let themeOk = true, shadeOk = true;
    for (const t of themes) {
      await evaluate(`[...document.querySelectorAll('.settings-float .seg[aria-label="主题"] button')].find(b => b.textContent.trim() === '${t}')?.click()`);
      await sleep(120);
      const st = await evaluate("({ t: document.documentElement.getAttribute('data-theme'), s: document.documentElement.getAttribute('data-shade') })");
      if (st.t !== t) themeOk = false;
      const wantShade = (t === "glass" || t === "soft") ? "night" : "day";
      if (st.s !== wantShade) shadeOk = false;
    }
    check("W14 五主题逐个生效", themeOk, "");
    check("W14 昼夜 shade 跟随主题族", shadeOk, "");
    // 字号 16 → --ed-fs
    await evaluate("[...document.querySelectorAll('.settings-float .seg[aria-label=\"编辑器字号\"] button')].find(b => b.textContent.trim() === '16')?.click()");
    await sleep(120);
    const fs = await evaluate("document.documentElement.style.getPropertyValue('--ed-fs')");
    check("W14 编辑器字号 16px 生效", fs.trim() === "16px", fs);
    // 动效关 → data-motion=off
    await evaluate("[...document.querySelectorAll(\".settings-float .seg[aria-label='界面动效'] button\")].find(b => b.textContent.trim() === '关')?.click()");
    await sleep(120);
    const motion = await evaluate("document.documentElement.getAttribute('data-motion')");
    check("W14 动效关闭 → data-motion=off", motion === "off", String(motion));
    // 持久化：重载后 主题/字号/动效 三者保持
    const before = await evaluate("({ t: document.documentElement.getAttribute('data-theme'), fs: document.documentElement.style.getPropertyValue('--ed-fs'), m: document.documentElement.getAttribute('data-motion') })");
    await send("Page.navigate", { url: PAGE });
    await waitFor("document.querySelector('.pilot-head .badge b')?.textContent?.length > 3", 30000);
    await sleep(500);
    const after = await evaluate("({ t: document.documentElement.getAttribute('data-theme'), fs: document.documentElement.style.getPropertyValue('--ed-fs'), m: document.documentElement.getAttribute('data-motion') })");
    check("W14 重载后主题/字号/动效三持久化", JSON.stringify(before) === JSON.stringify(after), JSON.stringify([before, after]));
  }

  // ── W15-W17 主链面（A2/A7/A8，#140）：统计卡 / stdin 喂入 / golden 对照 ──
  // W15 点 hello（golden "Hello\n"）→ 返回码 0 / VM 步数 > 0 / 对照 ✓
  await evaluate("[...document.querySelectorAll('.tab')].find(t => t.textContent.trim() === '内容')?.click()");
  await sleep(300);
  await evaluate("[...document.querySelectorAll('button.lesson')].find(b => b.querySelector('.lid')?.textContent === 'hello')?.click()");
  await waitFor("window.__pilot?.session?.frames?.length > 0", 20000);
  await sleep(300);
  const w15 = await evaluate(`(() => {
    const cards = [...document.querySelectorAll('.stat-card .stat-value')].map(e => e.textContent.trim());
    const verdict = document.querySelector('.verdict')?.textContent?.trim() ?? '';
    return { ret: cards[0], steps: cards[1], verdict };
  })()`);
  check("W15 统计卡 + golden 对照（hello：ret 0/步数>0/✓）", w15.ret === "0" && Number(w15.steps) > 0 && w15.verdict.startsWith("✓"), JSON.stringify(w15));

  // W16 scanf 课：waiting_input → stdin 行（默认 42）→ 喂入续跑 → got 42
  // （W15 点课已自动切运行 tab——课程树条件渲染卸载，须先切回内容 tab）
  await evaluate("[...document.querySelectorAll('.tab')].find(t => t.textContent.trim() === '内容')?.click()");
  await sleep(300);
  await evaluate("[...document.querySelectorAll('button.lesson')].find(b => b.querySelector('.lid')?.textContent === 'scanf')?.click()");
  await waitFor("document.querySelector('.stdin-row')", 20000);
  const w16a = await evaluate(`(() => ({
    draft: document.querySelector('.stdin-box')?.value ?? '',
    ret: [...document.querySelectorAll('.stat-card .stat-value')][0]?.textContent.trim(),
  }))()`);
  check("W16a waiting 态 stdin 行出现（默认 42 + 返回码 —）", w16a.draft === "42" && w16a.ret === "—", JSON.stringify(w16a));
  await evaluate("document.querySelector('.stdin-row .btn')?.click()");
  await waitFor("!window.__pilot?.session?.runStats?.waiting_input", 20000);
  await sleep(300);
  const w16b = await evaluate(`(() => ({
    stdout: window.__pilot?.session?.outputs?.stdout ?? '',
    ret: [...document.querySelectorAll('.stat-card .stat-value')][0]?.textContent.trim(),
    verdict: document.querySelector('.verdict')?.textContent?.trim() ?? '',
  }))()`);
  check("W16b 喂入续跑（stdout got 42 + 返回码 0 + golden ✓）", w16b.stdout === "got 42" && w16b.ret === "0" && w16b.verdict.startsWith("✓"), JSON.stringify(w16b));

  // W17 golden 失效态（诚实边界）：编辑器键入后不拿旧预期比新代码
  const edBox = await evaluate(`(() => { const r = document.querySelector('.cm-content').getBoundingClientRect(); return { x: Math.round(r.x + 40), y: Math.round(r.y + 10) }; })()`);
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x: edBox.x, y: edBox.y, button: "left", clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: edBox.x, y: edBox.y, button: "left", clickCount: 1 });
  await send("Input.insertText", { text: " " });
  await sleep(500);
  const w17 = await evaluate(`document.querySelector('.ref-box .muted')?.textContent?.trim() ?? ''`);
  check("W17 golden 失效文案（编辑器修改后）", w17.includes("已修改"), w17);

  const fails = results.filter((r) => !r.ok).length;
  console.log(`\n===== ${results.length - fails}/${results.length} 通过${fails ? "，失败 " + fails + " 项" : ""} =====`);
  ws.close();
  process.exit(fails ? 1 : 0);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
