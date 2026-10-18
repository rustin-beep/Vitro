// E2E 实测（工作区 / 回放 / 设置 / 主链面——2026-10-18 前端改造批重定向）：
// CDP 驱动 Edge 无头，对 vite 产物做真页面验证。W1–W17 锚语义不变，选择器
// 随新 IA（三态 + 诊断带 + vr-* 类名）迁移；workspace 条保留 ws-* 类名契约。
//
// 用法同 e2e_diagcard.mjs 三步（build / serve_static 8931 / headless Edge 9222）。
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

const edText = () => evaluate("[...document.querySelectorAll('.cm-line')].map(e => e.textContent).join('\\n')");
async function clickCm() {
  const box = await evaluate("(() => { const r = document.querySelector('.cm-content')?.getBoundingClientRect(); return r ? {x: Math.round(r.x + r.width/2), y: Math.round(r.y + Math.min(r.height/2, 20))} : null; })()");
  if (!box) throw new Error("找不到 .cm-content");
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x: box.x, y: box.y, button: "left", clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: box.x, y: box.y, button: "left", clickCount: 1 });
  await sleep(120);
}
async function setEditor(text) {
  await waitFor("!window.__pilot.session.collecting", 20000);
  await clickCm();
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "a", code: "KeyA", windowsVirtualKeyCode: 65 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "a", code: "KeyA", windowsVirtualKeyCode: 65 });
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 });
  await sleep(120);
  await clickCm();
  await send("Input.insertText", { text });
  await sleep(300);
  // 回读校验（CM6 与 readOnly/焦点时序的坑：写不进去时立即红，不静默继续）
  const got = await edText();
  const norm = (s) => s.replace(/\s+/g, " ").trim();
  if (norm(got) !== norm(text)) {
    throw new Error("编辑器内容写入失败（W3 族）：回读=" + JSON.stringify(got.slice(0, 80)));
  }
}

async function bootWait() {
  await waitFor("window.__pilot && window.__pilot.session.booted", 30000);
  await waitFor("window.__pilot.lessonSession.lesson && !window.__pilot.session.collecting && window.__pilot.session.frames.length > 0", 40000);
  await sleep(400);
}
async function openEntry() {
  if (await evaluate("window.__pilot.ui.screen === 'entry'")) return;
  await evaluate(`document.querySelector('[aria-label="课程目录"]')?.click()`);
  await waitFor("window.__pilot.ui.screen === 'entry'");
  await sleep(250);
}
async function pickLesson(id, waitMs = 30000) {
  await openEntry();
  await waitFor("!window.__pilot.session.collecting", 30000);
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
  // 新工作态比旧两栏页更高（标题/运行条/参数条）——固定 1440×900 视口，
  // 否则 headless 默认小窗口里编辑器中心落在视口外，真实点选失败（实测）。
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url: PAGE });
  await bootWait();

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
    editor: [...document.querySelectorAll('.cm-line')].map(e => e.textContent).join('\\n'),
  }))()`);
  check("W1 chips 四文件（剪枝/过滤生效）", JSON.stringify(w1.chips) === JSON.stringify(["main.c", "util.h", "util.c", "extra.c"]), JSON.stringify(w1.chips));
  check("W1 目录名 + active=main.c", w1.name === "mockproj（4）" && w1.active === "main.c", w1.name + " / " + w1.active);
  check("W1 编辑器载入 main.c 内容", w1.editor.includes('#include "util.h"') && w1.editor.includes("add(2, 3)"), w1.editor.slice(0, 60));

  // ── W2 多文件采集（compile.files + vfs include）──
  await evaluate("document.querySelector('[data-act=\"run\"]')?.click()");
  await waitFor("window.__pilot.session.outputs.stdout.length > 0", 20000);
  const w2 = await evaluate("window.__pilot.session.outputs.stdout.trim()");
  check("W2 compile.files 多单元 + include 解析（stdout=5）", w2 === "5", JSON.stringify(w2));

  // ── W3 dirty 标记 + 编辑器键入同步 ──
  await setEditor(MAIN_C.replace("add(2, 3)", "add(20, 30)"));
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
    editor: [...document.querySelectorAll('.cm-line')].map(e => e.textContent).join('\\n'),
  }))()`);
  check("W5 切到 util.c（编辑器 = util.c 内容）", w5a.active === "util.c" && w5a.editor.includes("int add(int a, int b)"), w5a.active);
  await evaluate("[...document.querySelectorAll('.ws-chip')].find(c => c.textContent.includes('main.c'))?.click()");
  await sleep(300);
  const w5b = await edText();
  check("W5 切回 main.c（缓冲保留 add(20,30)）", w5b.includes("add(20, 30)"), w5b.slice(0, 60));

  // ── W6 Ctrl+S 保存（改 util.c 后快捷键写回）──
  await evaluate("[...document.querySelectorAll('.ws-chip')].find(c => c.textContent.includes('util.c'))?.click()");
  await sleep(400);
  await setEditor(UTIL_C.replace("a + b", "a * b"));
  await send("Input.dispatchKeyEvent", { type: "keyDown", modifiers: 2, key: "s", code: "KeyS", windowsVirtualKeyCode: 83 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", modifiers: 2, key: "s", code: "KeyS", windowsVirtualKeyCode: 83 });
  await waitFor("(window.__wsWrites['util.c'] ?? '').includes('a * b')", 8000);
  check("W6 Ctrl+S 写回 util.c（a*b）", true, (await evaluate("window.__wsWrites['util.c'] ?? ''")).slice(0, 50));

  // ── W7 关闭 guard：dirty 时 confirm(false) 不关 / confirm(true) 关 ──
  await clickCm();
  await send("Input.insertText", { text: "\n// dirty again" });
  await sleep(300);
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
  await pickLesson("bubble");
  await sleep(400);
  const w9 = await evaluate(`(() => ({
    title: document.querySelector('.vr-note-page h2')?.textContent?.trim() ?? '',
    hasRealBlock: (document.querySelector('.vr-note-page')?.textContent ?? '').includes('这门课在做什么'),
    pageTitle: document.querySelector('.vr-title')?.textContent?.trim() ?? '',
    blocks: [...document.querySelectorAll('.vr-note-page > *')].map(e => e.tagName.toLowerCase()).slice(0, 4),
  }))()`);
  check("W9 叙述面板渲染真源（glob 懒加载）", w9.hasRealBlock === true && w9.pageTitle.includes("冒泡排序"), JSON.stringify(w9).slice(0, 200));

  // ── W10 点课 guard：dirty 工作区 + confirm(false) 不切 / confirm(true) 保存后切 ──
  await evaluate("[...document.querySelectorAll('.ws-bar .ws-open')].find(b => b.textContent.includes('打开文件夹'))?.click()");
  await waitFor("document.querySelectorAll('.ws-chip').length === 4", 20000);
  // 打开工作区会触发编辑器整文替换（CM6 外部同步）——等它落定再点，否则
  // 键入会被随后的同步覆盖（W10 首跑实锤：chips 0 = 没脏就被 guard 放行）
  await waitFor("(document.querySelector('.cm-line')?.textContent ?? '').includes('stdio.h')", 10000);
  await sleep(400);
  await clickCm();
  await send("Input.insertText", { text: "\n// guard dirty" });
  await sleep(300);
  const dirtyPre = await evaluate("!!document.querySelector('.ws-chip.dirty')");
  if (!dirtyPre) throw new Error("W10 前置失败：工作区未进入 dirty 态");
  await sleep(300);
  await evaluate("window.__confirmAnswer = false");
  await openEntry();
  await evaluate(`[...document.querySelectorAll('.vr-chapter')].find(b => b.textContent.includes('排序'))?.click()`);
  await sleep(300);
  await evaluate(`[...document.querySelectorAll('.vr-lesson-row')].find(b => b.querySelector('.vr-id')?.textContent === 'bubble_sort')?.click()`);
  await sleep(300);
  await evaluate("document.querySelector('.vr-preview .vr-open')?.click()");
  await sleep(500);
  const w10a = await evaluate(`(() => ({
    active: window.__pilot.workspace.active,
    dirty: window.__pilot.workspace.dirty,
    screen: window.__pilot.ui.screen,
  }))()`);
  check("W10 confirm(false) → 选课中止（工作区不关、不跳工作态）", w10a.active === true && w10a.dirty === true && w10a.screen === "entry", JSON.stringify(w10a));
  await evaluate("window.__confirmAnswer = true");
  await evaluate("document.querySelector('.vr-preview .vr-open')?.click()");
  await waitFor("window.__pilot.ui.screen === 'work' && !window.__pilot.session.collecting", 20000);
  const w10b = await evaluate(`(() => ({
    chips: document.querySelectorAll('.ws-chip').length,
    saved: (window.__wsWrites['main.c'] ?? '').includes('guard dirty'),
    lesson: window.__pilot.lessonSession.lesson?.id,
  }))()`);
  check("W10 confirm(true) → 保存 + 关工作区 + 切工作态", w10b.chips === 0 && w10b.saved === true && w10b.lesson === "bubble_sort", JSON.stringify(w10b));

  // ── W11 主题切换 + 刷新持久化（localStorage 真恢复）──
  const theme0 = await evaluate("document.documentElement.getAttribute('data-theme')");
  await evaluate("document.querySelector('[data-theme-toggle]')?.click()");
  await sleep(300);
  const theme1 = await evaluate("document.documentElement.getAttribute('data-theme')");
  check("W11 主题切换生效（data-theme 变更）", theme0 !== theme1, theme0 + " → " + theme1);
  await send("Page.navigate", { url: PAGE + "?r=" + Date.now() }); // cache-bust：同 URL 无 fragment 可能不重载
  await bootWait();
  const theme2 = await evaluate("document.documentElement.getAttribute('data-theme')");
  check("W11 刷新后主题保持（localStorage 持久化真恢复）", theme2 === theme1, "刷新后 " + theme2 + "（期望 " + theme1 + "）");

  // ── W12 分享往返（点分享 → #z1. 片段 → 重载还原编辑器）──
  const shareProg = "int main(void) {\n  return 7;\n}\n";
  await setEditor(shareProg);
  await waitFor("(() => { const b = document.querySelector('[data-act=\"share\"]'); return !!b && !b.disabled; })()", 20000);
  await evaluate("document.querySelector('[data-act=\"share\"]')?.click()");
  await waitFor("document.querySelector('.vr-share-input')?.value?.startsWith('http')", 10000);
  await sleep(400);
  const hash = await evaluate("location.hash");
  check("W12 分享写入 #z1. 片段", typeof hash === "string" && hash.startsWith("#z1."), String(hash).slice(0, 46));
  // cache-bust query 强制完整导航（同路径仅变 fragment 是 same-document 导航，boot 链不重跑）
  await send("Page.navigate", { url: PAGE + "?share=" + Date.now() + hash });
  await waitFor("window.__pilot && window.__pilot.session.booted", 30000);
  await waitFor("window.__pilot.lessonSession.title === '分享的代码' && !window.__pilot.session.collecting", 30000);
  await sleep(500);
  const restored = await edText();
  check("W12 重载后编辑器还原分享代码（unpackSource 链）", restored.includes("return 7"), JSON.stringify(restored).slice(0, 70));

  // ── W13 回放交互（播放/单步/seek/粒度）──
  {
    // 分享还原**不自动运行**（不可信输入边界）——此处显式点「运行」
    await evaluate("document.querySelector('[data-act=\"run\"]')?.click()");
    await waitFor("window.__pilot.session.viewFrames.length > 1", 25000);
    // 采集完自动播放——先暂停并归零
    if (await evaluate("window.__pilot.session.playing")) {
      await evaluate("document.querySelector('[data-act=\"play\"]')?.click()");
      await sleep(150);
    }
    await evaluate("window.__pilot.seek(0)");
    await sleep(150);
    const c0 = await evaluate("({ at: window.__pilot.session.idx, total: window.__pilot.session.viewFrames.length })");
    check("W13 采集后帧计数可见", c0.total > 1, JSON.stringify(c0));
    await evaluate("document.querySelector('[aria-label=\"下一帧\"]')?.click()");
    await sleep(200);
    const c1 = await evaluate("window.__pilot.session.idx");
    check("W13 下一帧 +1", c1 === c0.at + 1, JSON.stringify([c0.at, c1]));
    await evaluate("document.querySelector('[aria-label=\"上一帧\"]')?.click()");
    await sleep(200);
    const c2 = await evaluate("window.__pilot.session.idx");
    check("W13 上一帧 -1", c2 === c0.at, JSON.stringify([c1, c2]));
    // 播放 → 帧推进 → 暂停（默认 8 帧/秒：首帧间隔 125ms，且 headless 下
    // 定时器可能被渲染挤到 ~300ms——用 waitFor 等推进，不赌固定 sleep）
    await evaluate("document.querySelector('[data-act=\"play\"]')?.click()");
    await sleep(60);
    const playing = await evaluate("window.__pilot.session.playing");
    const advanced = await waitFor(`window.__pilot.session.idx > ${c2}`, 4000).catch(() => false);
    const c3 = await evaluate("window.__pilot.session.idx");
    check("W13 播放推进帧", playing === true && c3 > c2, playing + " " + JSON.stringify([c2, c3]) + " advanced=" + advanced);
    if (await evaluate("window.__pilot.session.playing")) {
      await evaluate("document.querySelector('[data-act=\"play\"]')?.click()");
    }
    await sleep(300);
    const c4 = await evaluate("window.__pilot.session.idx");
    await sleep(300);
    const c5 = await evaluate("window.__pilot.session.idx");
    check("W13 暂停后帧不再推进", c4 === c5, JSON.stringify([c4, c5]));
    // 滑条 seek 到末帧
    await evaluate(`(() => { const r = document.querySelector('input[aria-label="帧滑条"]'); if (!r) return; r.value = r.max; r.dispatchEvent(new Event('input', { bubbles: true })); })()`);
    await sleep(300);
    const c6 = await evaluate("({ at: window.__pilot.session.idx, total: window.__pilot.session.viewFrames.length })");
    check("W13 滑条 seek 到末帧", c6.at === c6.total - 1, JSON.stringify(c6));
    // 粒度切换：指令级帧数 > 语句级帧数
    const totalOf = () => evaluate("window.__pilot.session.viewFrames.length");
    await evaluate("[...document.querySelectorAll('.vr-grain button')].find(b => b.textContent.includes('指令级'))?.click()");
    await sleep(500);
    const tInsn = await totalOf();
    await evaluate("[...document.querySelectorAll('.vr-grain button')].find(b => b.textContent.includes('语句级'))?.click()");
    await sleep(500);
    const tStmt = await totalOf();
    check("W13 粒度切换改变帧口径（指令级 > 语句级）", tInsn > tStmt && tStmt > 0, `insn=${tInsn} stmt=${tStmt}`);
  }

  // ── W14 设置浮层（五主题 / 字号 / 动效 + 持久化）──
  {
    await evaluate("document.querySelector('[data-settings]')?.click()");
    await waitFor("!!document.querySelector('.vr-popover')", 5000);
    const themes = [["ice", "明亮实验室"], ["rose", "奶油手账"], ["soft", "绒面深蓝"], ["paper", "白天（纸）"], ["blueprint", "夜航图"]];
    let themeOk = true, shadeOk = true;
    for (const [t, name] of themes) {
      await evaluate(`[...document.querySelectorAll('.vr-theme-btn')].find(b => b.textContent.trim() === '${name}')?.click()`);
      await sleep(150);
      const st = await evaluate("({ t: document.documentElement.getAttribute('data-theme'), s: document.documentElement.getAttribute('data-shade') })");
      if (st.t !== t) themeOk = false;
      const wantShade = (t === "soft" || t === "blueprint") ? "night" : "day";
      if (st.s !== wantShade) shadeOk = false;
    }
    check("W14 五主题逐个生效", themeOk, "");
    check("W14 昼夜 shade 跟随主题族", shadeOk, "");
    // 字号 16
    await evaluate("[...document.querySelectorAll('.vr-seg[aria-label=\"字号\"] button')].find(b => b.textContent.trim() === '16')?.click()");
    await sleep(150);
    const size = await evaluate("document.documentElement.getAttribute('data-size')");
    check("W14 字号 16 档生效", size === "16", String(size));
    // 动效关（先确保在开态，再点关）
    const m0 = await evaluate("document.documentElement.getAttribute('data-motion')");
    if (m0 === "off") { await evaluate("document.querySelector('.vr-switch')?.click()"); await sleep(150); }
    await evaluate("document.querySelector('.vr-switch')?.click()");
    await sleep(150);
    const motion = await evaluate("document.documentElement.getAttribute('data-motion')");
    check("W14 动效关闭 → data-motion=off", motion === "off", String(motion));
    // 持久化：重载后 主题/字号/动效 三者保持
    const before = await evaluate("({ t: document.documentElement.getAttribute('data-theme'), s: document.documentElement.getAttribute('data-size'), m: document.documentElement.getAttribute('data-motion') })");
    await send("Page.navigate", { url: PAGE });
    await bootWait();
    const after = await evaluate("({ t: document.documentElement.getAttribute('data-theme'), s: document.documentElement.getAttribute('data-size'), m: document.documentElement.getAttribute('data-motion') })");
    check("W14 重载后主题/字号/动效三持久化", JSON.stringify(before) === JSON.stringify(after), JSON.stringify([before, after]));
  }

  // ── W15 主链面：统计 + golden 对照（hello：ret 0 / 步数 > 0 / ✓）──
  await pickLesson("hello");
  await waitFor("!window.__pilot.session.playing", 20000);
  await sleep(300);
  const w15 = await evaluate(`(() => {
    const s = window.__pilot.session;
    return {
      ret: s.runStats?.return_value ?? null, steps: s.runStats?.steps_executed ?? 0,
      golden: s.golden.kind, badge: document.querySelector('.vr-badge')?.textContent?.trim() ?? '',
      statline: document.querySelector('.vr-statline')?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
    };
  })()`);
  check("W15 统计 + golden 对照（hello：ret 0/步数>0/✓）", w15.ret === 0 && w15.steps > 0 && w15.golden === "ok" && w15.badge.startsWith("✓"), JSON.stringify(w15));

  // W16 scanf 课：waiting_input → stdin 行（默认 42）→ 喂入续跑 → got 42
  await pickLesson("scanf");
  await waitFor("document.querySelector('.vr-stdin-row')", 20000);
  const w16a = await evaluate(`(() => ({
    draft: document.querySelector('.vr-stdin-row input')?.value ?? '',
    statline: document.querySelector('.vr-statline')?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
  }))()`);
  check("W16a waiting 态 stdin 行出现（默认 42 + 返回码 —）", w16a.draft === "42" && w16a.statline.includes("返回码 —"), JSON.stringify(w16a));
  await evaluate("document.querySelector('.vr-stdin-row .vr-btn')?.click()");
  await waitFor("!window.__pilot.session.runStats?.waiting_input", 20000);
  await sleep(400);
  const w16b = await evaluate(`(() => {
    const s = window.__pilot.session;
    return { stdout: s.outputs.stdout, ret: s.runStats?.return_value, golden: s.golden.kind, badge: document.querySelector('.vr-badge')?.textContent?.trim() ?? '' };
  })()`);
  // golden 判定口径 = 末帧（设计说明 §12.2）——喂入重采后停在帧 0，需走到末帧
  await evaluate("window.__pilot.seek(window.__pilot.session.viewFrames.length - 1)");
  await sleep(400);
  const w16c = await evaluate(`(() => ({ stdout: window.__pilot.session.outputs.stdout, ret: window.__pilot.session.runStats?.return_value, golden: window.__pilot.session.golden.kind }))()`);
  check("W16b 喂入续跑（stdout got 42 + 返回码 0 + golden ✓）", w16c.stdout === "got 42" && w16c.ret === 0 && w16c.golden === "ok", JSON.stringify(w16c));

  // W17 golden 失效态（诚实边界）：编辑器键入后不拿旧预期比新代码
  await clickCm();
  await send("Input.insertText", { text: " " });
  await sleep(500);
  const w17 = await evaluate(`(() => ({ kind: window.__pilot.session.golden.kind, badge: document.querySelector('.vr-badge')?.textContent?.trim() ?? '' }))()`);
  check("W17 golden 失效文案（编辑器修改后）", w17.kind === "stale" && w17.badge.includes("已修改"), JSON.stringify(w17));

  const fails = results.filter((r) => !r.ok).length;
  console.log(`\n===== ${results.length - fails}/${results.length} 通过${fails ? "，失败 " + fails + " 项" : ""} =====`);
  ws.close();
  process.exit(fails ? 1 : 0);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
