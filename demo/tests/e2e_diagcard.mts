// E2E 实测（诊断带）：CDP 驱动 Edge 无头，对 vite 产物做真页面验证。
// 用法（三步，本地资产——CI 无 Edge 不进流水线）：
//   1. cd demo && node node_modules/vite/bin/vite.js build        （产物 dist/）
//   2. node tests/serve_static.mts 8931                            （静态服，后台）
//   3. msedge --headless=new --remote-debugging-port=9222 --user-data-dir=<tmp> \
//        --no-proxy-server http://127.0.0.1:8931/index.html    （后台）
//      node tests/e2e_diagcard.mts http://127.0.0.1:8931/          （本脚本，node 25）
// 前置：moonbit/_build 的 wasm-gc 产物须已 cp 到 demo/wasm.wasm（新鲜度见 #123①）。
//
// 2026-10-18 前端改造批重定向（IA 五 tab → 三态 + 诊断带）：
//   S1 编译失败：未声明变量 → 一句话诊断（E3023 + 定位 + 修复建议）+ 定位按钮 → .cm-diagline
//   S2 成功带警：W1019 宏副作用 → 摘要「编译 ✓ 1 警告」+ 诊断行 + pp 轨迹折叠展开
//   S3 空态：无诊断程序 → 摘要「编译 ✓」+ 展开明细「编译期 · 无诊断」
//   S4 断点链：bp gutter 点击 → 点 + 行装饰 → 再点清
//   S5 断点采集：挂断点后采集必须停在断点（paused 停止 + 文案）
import { connectCdp, sleep, type CdpClient, type CheckResult } from "./cdp.mts";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const PAGE = BASE + "index.html";

const BAD = 'int main(void) {\n  int y = 5;\n  return y + z;\n}\n';
const WARN = '#define BAD(x) ((x)+(x))\nint main(void) {\n  int i = 1;\n  int r = BAD(i++);\n  return r;\n}\n';
const CLEAN = 'int main(void) {\n  int a = 1;\n  return a;\n}\n';

interface S1 {
  compileOk: boolean;
  mode: string;
  screen: string;
  pill: string;
  code: string;
  loc: string;
  msg: string;
  fix: string;
  rows: number;
  firstErr: string;
}
interface S1b { diagline: boolean; focused: boolean; statusLine: string }
interface S2Row { code: string; msg: string; fix: string }
interface S2 { compileOk: boolean; pill: string; rows: S2Row[]; view: number; traceToggle: string; error: boolean }
interface S3 { diags: number; pill: string; error: boolean; rows: number; cells: number }
interface S4 { visible: number; bpline: boolean }
interface S5 { stopped: string; frames: number }

let send: CdpClient["send"] = () => Promise.reject(new Error("CDP 未连接"));
let evaluate: CdpClient["evaluate"] = () => Promise.reject(new Error("CDP 未连接"));
let waitFor: CdpClient["waitFor"] = () => Promise.reject(new Error("CDP 未连接"));

async function key(type: string, key: string, code: string, windowsVirtualKeyCode: number, modifiers = 0, text?: string): Promise<void> {
  await send("Input.dispatchKeyEvent", { type, modifiers, key, code, windowsVirtualKeyCode, text });
}

async function getEditorText(): Promise<string> {
  // CM6 的 .cm-content textContent 把各行**粘连**（block 元素无换行符）——
  // 回读必须按 .cm-line 逐行 join，否则归一化会把 `;}` 判成缺空格（实测）。
  return evaluate("[...document.querySelectorAll('.cm-line')].map(e => e.textContent).join('\\n')");
}

async function setEditor(text: string): Promise<void> {
  // 首访自动采集期间编辑器是 readOnly（disabled={collecting}）——先等它落定，
  // 否则 Ctrl+A/Backspace 被静默拒绝、文本会追加到旧内容后面（2026-10-18 实锤）。
  await waitFor("!window.__pilot.session.collecting", 20000);
  await sleep(250);
  // 真鼠标点击（focus() 在 headless 下不稳——点击坐标来自元素 boundingBox）。
  // 坑（2026-10-16 实测）：Backspace 清空后 CM6 焦点掉到 BODY（空编辑器
  // 失焦），此后 insertText 静默丢失——必须先重点击再插入。
  const box = await evaluate<{ x: number; y: number } | null>(`(() => { const r = document.querySelector('.cm-content')?.getBoundingClientRect(); return r ? {x: r.x + r.width/2, y: r.y + Math.min(r.height/2, 20)} : null; })()`);
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
  // 回读校验：整段归一化比对（禁「变量没进产物就下结论」——#123 P2 教训同族）
  const norm = (s: string): string => s.replace(/\s+/g, " ").trim();
  const got = await getEditorText();
  if (norm(got) !== norm(text)) {
    throw new Error("编辑器内容写入失败：回读=" + JSON.stringify(got.slice(0, 80)));
  }
}

async function clickRun(): Promise<void> {
  await evaluate("document.querySelector('[data-act=\"run\"]')?.click()");
}

async function bootWait(): Promise<void> {
  await waitFor("window.__pilot && window.__pilot.session.booted", 30000);
  await waitFor("!!document.querySelector('.cm-content')", 20000);
  // 首访落地（bubble 预载）也是一次采集——编辑前必须等它收尾，否则编辑器
  // 处于 readOnly（disabled={collecting}），Ctrl+A/Backspace 被静默拒绝。
  await waitFor("!window.__pilot.session.collecting", 20000);
  await sleep(300);
}

async function run() {
  const cdp = await connectCdp();
  ({ send, evaluate, waitFor } = cdp);
  await send("Page.enable");
  // 固定桌面视口（2026-10-18 布局对调后，窗口默认 800×600 会让编辑器落到
  // 视口外，鼠标点击无效——所有 E2E 统一 1440×900，与工作区脚本同口径）
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await send("Runtime.enable");

  const results: CheckResult[] = [];
  const check = (name: string, ok: boolean, detail: string): void => {
    results.push({ name, ok, detail });
    console.log((ok ? "PASS" : "FAIL") + "  " + name + "  — " + detail);
  };

  // 2. 导航 + 等 boot（版本徽章就绪）
  // 先清「继续上次」再重载——progress.last 留下的可能是 scanf 课：#189 起
  // 等待态编辑器锁定会让本套件的 setEditor 写入红（锁定是正确行为，套件
  // 开场态不可依赖上次运行残留）。⚠️ 清除必须等 boot 完整落定（bootWait
  // 而非仅 __pilot 出现）：openInitial 的 rememberLesson 在 lesson.md 懒加载
  // await 之后才写——清早了会被回写（曾竞态红）。
  await send("Page.navigate", { url: PAGE });
  await bootWait();
  await evaluate("localStorage.clear()");
  // ⚠️ 两次 clear 夹住 700ms 去抖：WorkScreen「继续上次记帧」是 setTimeout(700)
  // 写入——bootWait 后立即 clear 会被 timer 复脏（写回当前课），reload 又恢复。
  await sleep(800);
  await evaluate("localStorage.clear()");
  await send("Page.navigate", { url: PAGE + "?fresh=1" });
  await bootWait();
  check("boot 版本徽章", true, await evaluate<string>("document.querySelector('.vr-engine b')?.textContent ?? ''"));

  // ── S1 编译失败 ──
  await setEditor(BAD);
  await clickRun();
  await waitFor("document.querySelector('.vr-diag-error')", 20000);
  const s1 = await evaluate<S1>(`(() => {
    const box = document.querySelector('.vr-diag-error');
    const pill = document.querySelector('.vr-diag-pill');
    return {
      compileOk: window.__pilot.session.compileOk,
      mode: window.__pilot.ui.mode,
      screen: window.__pilot.ui.screen,
      pill: pill?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
      code: box?.querySelector('.vr-diag-code')?.textContent?.trim() ?? '',
      loc: box?.querySelector('.vr-diag-loc')?.textContent?.trim() ?? '',
      msg: box?.querySelector('.vr-diag-msg')?.textContent?.trim() ?? '',
      fix: box?.querySelector('.vr-diag-fix')?.textContent?.trim() ?? '',
      rows: document.querySelectorAll('.vr-diag-row').length,
      firstErr: window.__pilot.session.firstError?.code ?? '',
    };
  })()`);
  check("S1 编译失败态（compileOk=false + 仍在执行模式）", s1.compileOk === false && s1.mode === "exec" && s1.screen === "work", JSON.stringify({ c: s1.compileOk, m: s1.mode, s: s1.screen }));
  check("S1 摘要含「编译 ✗ 1 错误」", s1.pill.includes("编译") && s1.pill.includes("1 错误"), s1.pill);
  check("S1 E3023 + 定位 + 消息", s1.code === "E3023" && s1.loc.includes("main.c 行 3:14") && s1.msg.includes("未声明的变量"), JSON.stringify({ code: s1.code, loc: s1.loc, msg: s1.msg }));
  check("S1 修复建议可见（✚）", s1.fix.startsWith("✚"), s1.fix);

  // 定位按钮 → 编辑器行染
  await evaluate("document.querySelector('.vr-diag-loc')?.click()");
  await sleep(400);
  const s1b = await evaluate<S1b>(`(() => ({
    diagline: !!document.querySelector('.cm-diagline'),
    focused: document.activeElement?.classList?.contains('cm-content') ?? false,
    statusLine: document.querySelector('.vr-status')?.textContent?.trim() ?? '',
  }))()`);
  check("S1 定位跳转高亮 cm-diagline", s1b.diagline === true, JSON.stringify(s1b));
  check("S1 status 行会话态文案", s1b.statusLine.includes("编译失败") && s1b.statusLine.includes("诊断"), s1b.statusLine);

  // ── S2 成功带警（W1019）──
  await setEditor(WARN);
  await clickRun();
  await waitFor("document.querySelector('.vr-diag-row')", 20000);
  const s2 = await evaluate<S2>(`(() => {
    const pill = document.querySelector('.vr-diag-pill')?.textContent?.replace(/\\s+/g, ' ').trim() ?? '';
    const rows = [...document.querySelectorAll('.vr-diag-row')].map((r) => ({
      code: r.querySelector('.c')?.textContent?.trim() ?? '',
      msg: r.querySelector('.m')?.textContent?.trim() ?? '',
      fix: r.querySelector('.fx')?.textContent?.trim() ?? '',
    }));
    return {
      compileOk: window.__pilot.session.compileOk,
      pill,
      rows,
      view: window.__pilot.session.viewFrames.length,
      traceToggle: document.querySelector('.vr-pp-toggle')?.textContent?.trim() ?? '',
      error: !!document.querySelector('.vr-diag-error'),
    };
  })()`);
  check("S2 非失败态 + 「1 警告」", s2.compileOk === true && s2.pill.includes("1 警告") && s2.error === false, JSON.stringify({ pill: s2.pill, error: s2.error }));
  check("S2 W1019 诊断行渲染", s2.rows.some((r) => r.code === "W1019" && r.msg.includes("宏")), JSON.stringify(s2.rows));
  check("S2 采集照常（帧数 > 1）", s2.view > 1, "view=" + s2.view);
  check("S2 pp 轨迹折叠钮", s2.traceToggle.includes("宏展开轨迹") && s2.traceToggle.includes("1 条"), s2.traceToggle);

  // 展开 pp 轨迹
  await evaluate("document.querySelector('.vr-pp-toggle')?.click()");
  await sleep(250);
  const s2b = await evaluate<string>("document.querySelector('.vr-pp-body')?.textContent?.trim() ?? ''");
  check("S2 pp 轨迹展开内容", s2b.includes("BAD(i ++)") || s2b.includes("BAD(i++)"), s2b.slice(0, 80));

  // ── S3 干净程序（零诊断）──
  await setEditor(CLEAN);
  await clickRun();
  await waitFor("window.__pilot.session.frames.length > 0 && !window.__pilot.session.collecting", 20000);
  await sleep(300);
  const s3 = await evaluate<S3>(`(() => {
    const pill = document.querySelector('.vr-diag-pill');
    return {
      diags: window.__pilot.session.diagnostics.length,
      pill: pill?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
      error: !!document.querySelector('.vr-diag-error'),
      rows: document.querySelectorAll('.vr-diag-row').length,
      cells: document.querySelectorAll('.vr-cell').length,
    };
  })()`);
  check("S3 零诊断（摘要「编译 ✓」+ 无 error 行）", s3.diags === 0 && s3.pill.includes("编译 ✓") && s3.error === false, JSON.stringify(s3));
  // 展开明细：编译期 · 无诊断
  await evaluate("document.querySelector('.vr-diag-pill')?.click()");
  await sleep(200);
  const s3b = await evaluate<string>("document.querySelector('.vr-diag-detail')?.textContent?.replace(/\\s+/g, ' ').trim() ?? ''");
  check("S3 明细「编译期 · 无诊断」", s3b.includes("编译期 · 无诊断"), s3b.slice(0, 80));
  await evaluate("document.querySelector('.vr-diag-pill')?.click()");

  // ── S4 断点链（F4 残留④）：bp gutter 点击 → 点 + 行装饰 → 再点清 ──
  const bpBox = await evaluate<{ x: number; y: number } | null>(`(() => {
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
  const s4a = await evaluate<S4>(`(() => {
    const dots = [...document.querySelectorAll('.cm-bpgutter .bp-dot')];
    const visible = dots.filter((d) => getComputedStyle(d).visibility !== 'hidden').length;
    return { visible, bpline: !!document.querySelector('.cm-bpline') };
  })()`);
  check("S4 断点开启（gutter 可见点 + 行装饰）", s4a.visible === 1 && s4a.bpline === true, JSON.stringify(s4a));
  await clickBp();
  const s4b = await evaluate<S4>(`(() => {
    const dots = [...document.querySelectorAll('.cm-bpgutter .bp-dot')];
    const visible = dots.filter((d) => getComputedStyle(d).visibility !== 'hidden').length;
    return { visible, bpline: !!document.querySelector('.cm-bpline') };
  })()`);
  check("S4 断点关闭（再点全清）", s4b.visible === 0 && s4b.bpline === false, JSON.stringify(s4b));

  // ── S5 断点采集行为（A1，#140）：挂断点后采集必须停在断点 ──
  const BPLOOP = 'int main(void) {\n  int s = 0;\n  for (int i = 0; i < 10; i = i + 1)\n    s = s + i;\n  return s;\n}\n';
  await setEditor(BPLOOP); // 行 4 = 循环体首执行行
  await clickBp();
  await clickRun();
  let s5: S5 | null = null;
  for (let i = 0; i < 60; i++) {
    s5 = await evaluate<S5>(`({ stopped: window.__pilot?.session?.stopped ?? '', frames: window.__pilot?.session?.frames?.length ?? -1 })`);
    if (s5.stopped) break;
    await sleep(500);
  }
  check("S5 断点采集停在断点（paused 停止 + 文案）", !!s5 && /断点/.test(s5.stopped) && s5.frames > 0, JSON.stringify(s5));
  // 断点暂停横幅（新 UI）也应可见
  const s5b = await evaluate<string>("document.querySelector('.vr-banner.is-amber')?.textContent?.replace(/\\s+/g, ' ').trim() ?? ''");
  check("S5 断点暂停横幅可见", s5b.includes("断点暂停"), s5b.slice(0, 60));
  await clickBp(); // 清断点还场

  const fails = results.filter((r) => !r.ok).length;
  console.log(`\n===== ${results.length - fails}/${results.length} 通过${fails ? "，失败 " + fails + " 项" : ""} =====`);
  cdp.close();
  process.exit(fails ? 1 : 0);
}

run().catch((e) => { console.error("E2E 异常:", e.message); process.exit(2); });
