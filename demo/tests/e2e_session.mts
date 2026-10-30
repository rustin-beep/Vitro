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
//   B6 uaf 三幕分镜（#222 P1 内容扩面，2026-10-21）
//   B7 bubble_sort 六幕分镜（#222 P1 内容扩面，2026-10-22）
//   B8 内存/协议全页形态（#222 P1 两模式，2026-10-22）
//   B9 目录/手册 P2 形态（章路径 + 章节面板 / 六段证据链，2026-10-22）
//   B10 专注模式 F/Esc + ?focus=1（#222 P4，2026-10-22）
//   B11 移动工作台 390 首屏顺序 + 代码折叠（#222 P3，2026-10-22）
//   D1 交换事件：语句级组内聚合 + 双格/连线/编辑分色（#122 D1，2026-10-29）
//   D0 动效治理：开关持久化 + 预算/reduced-motion 旁路（#122 D0，2026-10-29）
//   D2 结构过渡：变量行/脉冲、深树 view→raw 映射与相机平滑（#122 D2，2026-10-29）
// 用法同 e2e_diagcard.mts 三步（build / serve_static 8931 / headless Edge 9222）。
// ⚠️ 旧锚点 .pilot-head/.tab/.bars/button.lesson 已随旧五 tab DOM 退役。
// 说明：CDP WebSocket 用 Node 22+ 全局 WebSocket；/json/list 走 node:http 直连。
import { connectCdp, sleep, type CdpClient, type CheckResult } from "./cdp.mts";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const PAGE = BASE + "index.html";

let send: CdpClient["send"] = () => Promise.reject(new Error("CDP 未连接"));
let evaluate: CdpClient["evaluate"] = () => Promise.reject(new Error("CDP 未连接"));
let cdpWaitFor: CdpClient["waitFor"] = () => Promise.reject(new Error("CDP 未连接"));
const waitFor = (expr: string, timeout = 25000, step = 250): Promise<boolean> =>
  cdpWaitFor(expr, timeout, step);

/** console.error / uncaught 收集（each_key_duplicate/postMessage 崩走这两通道）。 */
const ERR_COLLECTOR = `(() => {
  window.__errs = [];
  const oe = console.error;
  console.error = (...a) => { window.__errs.push(a.map((x) => String(x?.message ?? x)).join(" ").slice(0, 200)); oe(...a); };
  window.addEventListener("error", (e) => window.__errs.push("UNCAUGHT: " + e.message));
})()`;
const errs = (): Promise<string> => evaluate("JSON.stringify(window.__errs ?? [\"收集器未挂\"])");

/** 打开课程目录（若已在目录态则跳过；参考态先返回实验台——顶栏「课程」
 *  只在工作态渲染，参考态只有「返回实验台 + 课程目录」链接）。 */
async function openEntry(): Promise<void> {
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

/** 目录选课 → 单击直接在实验台打开 → 等本课采集完成（epoch 判据，防上一课
 *  残留帧骗过 collecting=false 的空窗）。课程可能不在当前章：逐章扫描。
 *  #222 P2 起课列单击即开课（旧「预览 → .vr-open」两步已退役）。 */
async function pickLesson(id: string, waitMs = 30000): Promise<void> {
  await openEntry();
  await waitFor("!window.__pilot.session.collecting", 30000); // 首访自动采集可能仍在跑
  const chapters = await evaluate<number>("document.querySelectorAll('.vr-chapter').length");
  let found = false;
  for (let i = 0; i < chapters; i++) {
    await evaluate(`document.querySelectorAll('.vr-chapter')[${i}]?.click()`);
    await sleep(120);
    found = await evaluate<boolean>(`!![...document.querySelectorAll('.vr-lesson-row')].find(b => b.querySelector('.vr-id')?.textContent === ${JSON.stringify(id)})`);
    if (found) break;
  }
  if (!found) throw new Error(`找不到课程 ${id}`);
  const e0 = await evaluate<number>("window.__pilot.session.epoch");
  await evaluate(`[...document.querySelectorAll('.vr-lesson-row')].find(b => b.querySelector('.vr-id')?.textContent === ${JSON.stringify(id)})?.click()`);
  await waitFor(`window.__pilot.ui.screen === 'work' && window.__pilot.lessonSession.lesson?.id === ${JSON.stringify(id)} && window.__pilot.session.epoch > ${e0} && !window.__pilot.session.collecting`, waitMs);
}

interface F1 { banner: string; close: boolean }
interface F2 { stdout: string; stats: boolean; frames: number }
interface B0 { beats: number; bands: number; annots: number; sceneNote: boolean; notePage: boolean }
interface F3 { gran: string; view: number; raw: number; same: boolean; status: string; statusLine: string }
interface B1Before { beats: number; bands: number; active: string }
interface B1After { idx: number; active: string; note: string; bandsActive: number }
interface B2 { kicker: string; title: string; prevDisabled?: boolean; compact: boolean; canvas: boolean }
interface B2After { idx: number; kicker: string; title: string }
interface B3 { railLeft: number; stageLeft: number; nowLeft: number; railW: number; nowW: number; dockW: number; benchW: number; codeTop: number; cellsTop: number; dockTop: number }
interface B4 { idx: number; attrs: (string | null)[]; inText: boolean }
interface B5 { card: string; open: boolean | null; fullInDom: boolean }
interface B6 { n: number; beats: number; bands: number; first: string }
interface B6Start { idx: number; stage: string; kicker: string; note: string }
interface B6Free { idx: number; stage: string; kicker: string }
interface B7Last { idx: number; stage: string; kicker: string; note: string; cells: number }
interface B8Mem { mode: string; page: boolean; bench: boolean; tabs: number; tracks: number; stats: number; freed: number; alert: boolean; questions: number; overflow: number }
interface B8Proto { mode: string; groups: number; methods: number; used: number; sideCount: string; facts: string; ledger: number; frame: boolean; overflow: number }
interface B8Back { mode: string; bench: boolean; page: boolean }
interface B9Entry { chapters: number; rows: number; panel: boolean; peek: number; preview: boolean; hero: string }
interface B9Ref { secs: number; three: number; fam: number; side: boolean; discrim: number; back: boolean; h1: string }
interface B10On { focus: boolean; bench: boolean; rail: string; badge: boolean; frame: string; modes: string; url: string }
interface B10Off { focus: boolean; bench: boolean; rail: string; url: string }
interface B10Mem { mode: string; focus: boolean; bench: boolean; url: string }
interface F5 { cells: number; frames: number; view: number; snapAt: number }
interface F6 { screen: string; refCode: string; active: string; h1: string }
interface F8 { readyFrames: number | null; frames: number }
interface B11 { title: string | null; code: string | null; line: string | null; lineText: string; btn: string | null; head: number; arr: number; lineTop: number; dock: number; overflow: number }
interface B11Open { code: string; expanded: string | null }
interface D1Swap {
  idx: number; n: number; evTy: number[]; evPair: number[];
  swapCount: number; swapLabels: string[]; fallback: number;
  dataSwap: string; linkFrom: string; linkTo: string; linkW: number; legend: boolean;
  meta: string; visTy: string; visSwap: number; pulses: number;
  motionOn: boolean; sys: boolean;
}
interface D1Compare { idx: number; ty: string; swapLines: number; link: boolean; swapCells: number }
interface D0Base { attr: string | null; enabled: boolean; sys: boolean; stored: string; pulses: number }
interface D0Static { attr: string | null; enabled: boolean; stored: string; pulses: number; swapCells: number; link: boolean }
interface D0Sys { attr: string | null; enabled: boolean; pulses: number; swapCells: number; link: boolean }
interface D0On { attr: string | null; enabled: boolean; stored: string; pulses: number }
interface D2Vars { idx: number; changed: string[]; rows: string[]; pulses: number; transitions: number }
interface D2Tree {
  nodes: number; edges: number; current: number; visited: number; edgesVisited: number;
  compact: boolean; canvas: boolean; transitions: number;
  idx: number; rawIdx: number; path: string; expected: string; currentNode: string;
  vb: string | null; cameraMoves: number;
}
interface D2Cam { vb: string | null; moves: number }
interface D2ReducedTree { nodes: number; transitions: number }
interface D1Multi { idx: number; secs: Array<{ title: string; swap: string; cells: number; legend: boolean }> }

// P2-1（PR #374 审阅）：声明锚数与实跑对账——waitFor 抛错会中断脚本，
// 不报「实跑 n / 声明 N」时 CI 只能看到一条异常、看不到覆盖静默缺失。
const DECLARED_ANCHORS = 30;
const results: CheckResult[] = [];

async function run() {
  const cdp = await connectCdp();
  ({ send, evaluate, waitFor: cdpWaitFor } = cdp);
  await send("Page.enable");
  // 固定桌面视口（2026-10-18 布局对调后，窗口默认 800×600 会让编辑器落到
  // 视口外，鼠标点击无效——所有 E2E 统一 1440×900，与工作区脚本同口径）
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await send("Runtime.enable");

  const check = (name: string, ok: boolean, detail: string): void => {
    results.push({ name, ok, detail });
    console.log((ok ? "PASS" : "FAIL") + "  " + name + "  — " + detail);
  };
  // 显式双向设置减少动效偏好：headless Chrome 默认可能是 reduce（CI 实测
  // 2026-10-29：D1 脉冲被判预算旁路），`features: []` 也不保证回到
  // no-preference——测试必须自己钉两边，不赌浏览器默认。
  const setReduced = async (on: boolean): Promise<void> => {
    await send("Emulation.setEmulatedMedia", {
      features: [{ name: "prefers-reduced-motion", value: on ? "reduce" : "no-preference" }],
    });
    await waitFor(`window.__pilot.motion.systemReduced === ${on}`, 5000);
  };
  // 用户开关钉位：E2E 套件共享浏览器 profile，前序 workspace 套件可能把动效
  // 留成 off（CI 实测 2026-10-29：D1 motionOn:false、D0 状态全反转）。走真实
  // 设置开关（会同步 data-motion 与 localStorage），已为目标态则 no-op。
  const setUserMotion = async (on: boolean): Promise<void> => {
    if ((await evaluate<boolean>("window.__pilot.motion.enabled")) === on) return;
    await evaluate("document.querySelector('[data-settings]')?.click(); true");
    await sleep(150);
    const pressed = await evaluate<boolean>("document.querySelector('.vr-switch')?.getAttribute('aria-pressed') === 'true'");
    if (pressed !== on) {
      await evaluate("document.querySelector('.vr-switch')?.click(); true");
      await sleep(150);
    }
    await evaluate(`document.querySelector('.vr-popover [aria-label="关闭设置"]')?.click(); true`);
    await sleep(100);
    await waitFor(`window.__pilot.motion.enabled === ${on}`, 5000);
  };

  // ── F1 坏分享 hash → 持久横幅（P1-3）——cache-bust 强制完整导航 ──
  await send("Page.navigate", { url: PAGE + "?cb=" + Date.now() + "#z1.BROKEN" });
  await waitFor("window.__pilot && window.__pilot.session.booted", 30000);
  await waitFor("document.querySelector('.vr-banner b')?.textContent?.includes('无法还原')", 20000);
  const f1 = await evaluate<F1>(`(() => {
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
  const f2 = await evaluate<F2>(`(() => {
    const s = window.__pilot.session;
    return { stdout: s.outputs.stdout.slice(0, 40), stats: !!s.runStats, frames: s.frames.length };
  })()`);
  const f2errs = JSON.parse(await errs()) as string[];
  check("F2 argv 采集成功零克隆崩（P1-2）",
    f2.stdout.includes("hello-arg") && f2.stats && f2.frames > 0 && !f2errs.some((e) => e.includes("could not be cloned")),
    JSON.stringify(f2) + " errs=" + f2errs.length);

  // ── B0 未迁移课无分镜条（#222 P1 第二片：scene 真源 = lesson.md；无元数据
  //    的课 scenes=[] → 分镜条整段不渲染，回退现有长文）──
  const b0 = await evaluate<B0>(`(() => ({
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
  const f3 = await evaluate<F3>(`(() => {
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
  const b1before = await evaluate<B1Before>(`(() => ({
    beats: document.querySelectorAll('.vr-beat').length,
    bands: document.querySelectorAll('.vr-band').length,
    active: document.querySelector('.vr-beat.is-active')?.textContent?.trim() ?? '',
  }))()`);
  await evaluate("document.querySelectorAll('.vr-beat')[0]?.click(); true");
  await sleep(250);
  const b1after = await evaluate<B1After>(`(() => ({
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
  const b2 = await evaluate<B2>(`(() => ({
    kicker: document.querySelector('.vr-stagehead-kicker')?.textContent?.trim() ?? '',
    title: document.querySelector('.vr-stagehead-title')?.textContent?.trim() ?? '',
    prevDisabled: document.querySelectorAll('.vr-stagehead-nav button')[0]?.disabled,
    compact: !!document.querySelector('.vr-tree-compact'),
    canvas: !!document.querySelector('.vr-canvas'),
  }))()`);
  await evaluate("document.querySelectorAll('.vr-stagehead-nav button')[1]?.click(); true");
  await sleep(250);
  const b2after = await evaluate<B2After>(`(() => ({
    idx: window.__pilot.session.idx,
    kicker: document.querySelector('.vr-stagehead-kicker')?.textContent?.trim() ?? '',
    title: document.querySelector('.vr-stagehead-title')?.textContent?.trim() ?? '',
  }))()`);
  check("B2 幕头随帧更新 + 浅树压扁（#222）",
    b2.title.includes("起点") && b2.prevDisabled === true && b2.compact === true && b2.canvas === false &&
      b2after.idx === 3 && b2after.title.includes("交换") && b2after.kicker.includes("帧 3–20"),
    JSON.stringify({ b2, b2after }));

  // ── B3 三栏 + 底栏时间轴（#222 P1 第四片）：1440 下 rail / stage / now 左中右
  //    并排、时间轴横跨三栏；代码/数组/时间轴都落在 900px 首屏内 ──
  const b3 = await evaluate<B3>(`(() => {
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
  const b4 = await evaluate<B4>(`(() => ({
    idx: window.__pilot.session.idx,
    attrs: [...document.querySelectorAll('.cm-line[data-annot]')].map((l) => l.getAttribute('data-annot')),
    inText: (document.querySelector('.cm-content')?.textContent ?? '').includes('←'),
  }))()`);
  check("B4 逐行注记（#222 P1 第五片）",
    b4.idx === 12 && b4.attrs.length === 5 && b4.attrs.includes("t ← 5") && b4.attrs.includes("a[1] ← 1") &&
      b4.attrs.includes("a[2] ← 5") && b4.inText === false,
    JSON.stringify(b4));
  // ── B5 本幕讲解 + 展开全文（#222 P1 第六片）：scene 课默认折叠、本幕卡片随幕更新，
  //    全文在 DOM（折叠不丢内容——W9 锚不受影响）；点 summary 可展开 ──
  const b5 = await evaluate<B5>(`(() => ({
    card: document.querySelector('.vr-scenenote')?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
    open: document.querySelector('details.vr-notefull')?.open ?? null,
    fullInDom: (document.querySelector('.vr-note-page')?.textContent ?? '').includes('这门课在做什么'),
  }))()`);
  await evaluate("document.querySelector('details.vr-notefull > summary')?.click(); true");
  await sleep(200);
  const b5open = await evaluate<boolean>("document.querySelector('details.vr-notefull')?.open === true");
  check("B5 本幕讲解 + 展开全文（#222）",
    b5.card.includes("本幕讲解") && b5.card.includes("交换不是瞬间完成的") && b5.open === false && b5.fullInDom === true && b5open === true,
    JSON.stringify({ b5, b5open }));

  // P2-1：D 段任一锚异常不吞后续锚——记录失败后继续 B6+；覆盖缺口由收尾
  // 「声明/实跑」对账报出，不让一条环境异常静默吃掉十几条锚。
  try {
  // ── D1 交换事件（#122 D1，2026-10-29）：语句级组内事件聚合 + 双格/连线/分色 ──
  // bubble 课首次交换 = 语句帧 7（42 帧口径）。该组组的组尾快照只有 a[0] 变了
  // （半完成中间态：a[0] 已覆盖、a[1] 还是旧值）——修前差分只亮 1 格，且没有
  // 任何事件语义；修后 ty=2 extras 双格、连线、编辑左缘 swap 色。本锚即红→绿锚。
  await setReduced(false); // headless Chrome 可能默认 reduce——先钉回 no-preference
  await setUserMotion(true); // 共享 profile：前序套件可能把用户开关留成 off
  if (await evaluate("window.__pilot.session.playing")) {
    await evaluate(`document.querySelector('[data-act="play"]')?.click()`);
    await sleep(150);
  }
  await evaluate("window.__pilot.seek(7)");
  await sleep(350);
  const d1 = await evaluate<D1Swap>(`(() => {
    const s = window.__pilot.session;
    const cells = [...document.querySelectorAll('.vr-cell')];
    const ev = s.eventsAt(s.idx);
    const link = document.querySelector('.vr-swap-link');
    return {
      idx: s.idx, n: s.viewFrames.length,
      evTy: ev.map((e) => e.ty),
      evPair: ev.filter((e) => e.ty === 2).map((e) => [e.extra0, e.extra1]).flat(),
      swapCount: cells.filter((c) => c.classList.contains('is-swap-event')).length,
      swapLabels: cells.filter((c) => c.classList.contains('is-swap-event')).map((c) => c.getAttribute('aria-label') ?? ''),
      fallback: cells.filter((c) => c.classList.contains('is-swap')).length,
      dataSwap: document.querySelector('.vr-cells')?.getAttribute('data-swap') ?? '',
      linkFrom: link?.getAttribute('data-from') ?? '',
      linkTo: link?.getAttribute('data-to') ?? '',
      linkW: link ? Math.round(link.getBoundingClientRect().width) : 0,
      // P2-2：连线入场是 scaleX(0)→1，动画前段 rect 宽为 0——不断几何宽度，
      // 改断结构语义（data-swap / data-from/to / 图例），宽度只作诊断。
      legend: !!document.querySelector('[data-swap-legend]'),
      meta: document.querySelector('[aria-label="数组可视化"] .vr-meta')?.textContent ?? '',
      visTy: document.querySelector('.cm-line[data-vis]')?.getAttribute('data-vis') ?? '',
      visSwap: document.querySelectorAll('.cm-line.cm-visline-swap').length,
      pulses: window.__pilot.motion.pulseCount,
      motionOn: window.__pilot.motion.enabled,
      sys: window.__pilot.motion.systemReduced,
    };
  })()`);
  check("D1 交换帧：事件双格 + 连线 + 编辑分色（组内聚合；修前只有 1 格差分）",
    d1.idx === 7 && d1.n === 42 && d1.evTy.includes(2) && d1.evPair.join(",") === "0,1" &&
      d1.swapCount === 2 && d1.swapLabels.join("|").includes("a[0] =") && d1.swapLabels.join("|").includes("a[1] =") &&
      d1.fallback === 0 && d1.dataSwap === "0-1" && d1.linkFrom === "0" && d1.linkTo === "1" && d1.legend === true &&
      d1.meta.includes("本帧交换 a[0] ↔ a[1]") && d1.visTy === "swap" && d1.visSwap >= 1 &&
      d1.motionOn === true && d1.sys === false && d1.pulses >= 2,
    JSON.stringify(d1));

  // 比较帧（语句帧 3 = 第 5 行循环条件）：左缘走 compare 色，不画交换面。
  await evaluate("window.__pilot.seek(3)");
  await sleep(200);
  const d1c = await evaluate<D1Compare>(`(() => ({
    idx: window.__pilot.session.idx,
    ty: document.querySelector('.cm-line[data-vis]')?.getAttribute('data-vis') ?? '',
    swapLines: document.querySelectorAll('.cm-line.cm-visline-swap').length,
    link: !!document.querySelector('.vr-swap-link'),
    swapCells: document.querySelectorAll('.vr-cell.is-swap-event').length,
  }))()`);
  check("D1 比较帧：左缘 compare 标记、无交换面（ty 分色不混）",
    d1c.idx === 3 && d1c.ty === "compare" && d1c.swapLines === 0 && d1c.link === false && d1c.swapCells === 0,
    JSON.stringify(d1c));

  // ── D0 动效治理（#122 D0）：开关持久化 + 预算裁决 + reduced-motion 旁路 ──
  // 语义优先级：脉冲可被预算旁路，静态交换高亮/连线不可丢（动效不撒谎）。
  await setUserMotion(true);
  const d0base = await evaluate<D0Base>(`(() => ({
    attr: document.documentElement.getAttribute('data-motion'),
    enabled: window.__pilot.motion.enabled,
    sys: window.__pilot.motion.systemReduced,
    stored: localStorage.getItem('vitro-motion') ?? '',
    pulses: window.__pilot.motion.pulseCount,
  }))()`);
  await evaluate("window.__pilot.seek(11)");
  await sleep(200);
  const d0pulse = await evaluate<number>("window.__pilot.motion.pulseCount");
  // 批量推进（bench/scrub 同类预算）时脉冲让位：帧照走，pulseCount 不动。
  await evaluate("window.__pilot.session.batching = true; window.__pilot.seek(15); true");
  await sleep(200);
  const d0batch = await evaluate<number>("window.__pilot.motion.pulseCount");
  await evaluate("window.__pilot.session.batching = false; true");

  // 用户开关：设置浮层 → 关动效；data-motion 落 html、偏好落 localStorage。
  await evaluate("document.querySelector('[data-settings]')?.click(); true");
  await sleep(150);
  await evaluate("document.querySelector('.vr-switch')?.click(); true");
  await sleep(150);
  await evaluate("window.__pilot.seek(24)");
  await sleep(200);
  const d0off = await evaluate<D0Static>(`(() => ({
    attr: document.documentElement.getAttribute('data-motion'),
    enabled: window.__pilot.motion.enabled,
    stored: localStorage.getItem('vitro-motion') ?? '',
    pulses: window.__pilot.motion.pulseCount,
    swapCells: document.querySelectorAll('.vr-cell.is-swap-event').length,
    link: !!document.querySelector('.vr-swap-link'),
  }))()`);
  // 恢复开关（后续锚还要动效），关浮层。
  await evaluate("document.querySelector('.vr-switch')?.click(); true");
  await sleep(150);
  await evaluate(`document.querySelector('.vr-popover [aria-label="关闭设置"]')?.click(); true`);
  await sleep(100);
  const d0on = await evaluate<D0On>(`(() => ({
    attr: document.documentElement.getAttribute('data-motion'),
    enabled: window.__pilot.motion.enabled,
    stored: localStorage.getItem('vitro-motion') ?? '',
    pulses: window.__pilot.motion.pulseCount,
  }))()`);

  // 系统 reduced-motion：脉冲旁路，静态语义仍在；解除后脉冲恢复。
  const d0sysBefore = await evaluate<number>("window.__pilot.motion.pulseCount");
  await setReduced(true);
  await evaluate("window.__pilot.seek(28)");
  await sleep(200);
  const d0sys = await evaluate<D0Sys>(`(() => ({
    attr: document.documentElement.getAttribute('data-motion'),
    enabled: window.__pilot.motion.enabled,
    pulses: window.__pilot.motion.pulseCount,
    swapCells: document.querySelectorAll('.vr-cell.is-swap-event').length,
    link: !!document.querySelector('.vr-swap-link'),
  }))()`);
  await setReduced(false);
  await evaluate("window.__pilot.seek(33)");
  await sleep(200);
  const d0resume = await evaluate<number>("window.__pilot.motion.pulseCount");
  check("D0 动效治理：开关持久化 + 预算/reduced 旁路（静态语义不丢）",
    d0base.attr === null && d0base.enabled === true && d0base.sys === false &&
      d0pulse >= d0base.pulses + 2 && d0batch === d0pulse &&
      d0off.attr === "off" && d0off.enabled === false && d0off.stored === "off" &&
      d0off.pulses === d0batch && d0off.swapCells === 2 && d0off.link === true &&
      d0on.attr === null && d0on.enabled === true && d0on.stored === "on" &&
      d0sys.attr === null && d0sys.enabled === true && d0sys.pulses === d0sysBefore &&
      d0sys.swapCells === 2 && d0sys.link === true &&
      d0resume >= d0sysBefore + 2,
    JSON.stringify({ d0base, d0pulse, d0batch, d0off, d0on, d0sysBefore, d0sys, d0resume }));

  // ── D2 VarsList（#122 D2）：值变化脉冲 + 行进出过渡 + reduced 旁路 ──
  if (await evaluate("window.__pilot.session.playing")) {
    await evaluate(`document.querySelector('[data-act="play"]')?.click()`);
    await sleep(150);
  }
  const varsSnap = () => evaluate<D2Vars>(`(() => {
    const s = window.__pilot.session;
    return {
      idx: s.idx,
      changed: [...document.querySelectorAll('.vr-vars tbody tr.is-changed')].map((r) => r.children[0]?.textContent ?? ''),
      rows: [...document.querySelectorAll('.vr-vars tbody tr')].map((r) => r.children[0]?.textContent ?? ''),
      pulses: window.__pilot.motion.pulseCount,
      transitions: window.__pilot.motion.transitionCount,
    };
  })()`);
  await evaluate("window.__pilot.seek(7)"); await sleep(300);
  const d2v7 = await varsSnap();
  await evaluate("window.__pilot.seek(8)"); await sleep(300);
  const d2v8 = await varsSnap();
  check("D2 变量值变化：脉冲只给变化行（a/j）；行集不变不演过渡",
    d2v8.idx === 8 && d2v8.changed.join(",") === "a,j" && d2v8.rows.join(",") === "a,i,j,t" &&
      d2v8.pulses === d2v7.pulses + 2 && d2v8.transitions === d2v7.transitions,
    JSON.stringify({ d2v7, d2v8 }));

  await evaluate("window.__pilot.seek(5)"); await sleep(300);
  const d2v5 = await varsSnap();
  await evaluate("window.__pilot.seek(6)"); await sleep(300);
  const d2v6 = await varsSnap();
  check("D2 变量行进出：t 行出现 = 一次过渡（无脉冲）",
    d2v6.rows.includes("t") && !d2v5.rows.includes("t") &&
      d2v6.transitions === d2v5.transitions + 1 && d2v6.pulses === d2v5.pulses,
    JSON.stringify({ d2v5, d2v6 }));

  await setReduced(true);
  await evaluate("window.__pilot.seek(5)"); await sleep(220);
  const d2r5 = await varsSnap();
  await evaluate("window.__pilot.seek(6)"); await sleep(220);
  const d2r6 = await varsSnap();
  await evaluate("window.__pilot.seek(7)"); await sleep(220);
  const d2r7 = await varsSnap();
  await evaluate("window.__pilot.seek(8)"); await sleep(220);
  const d2r8 = await varsSnap();
  check("D2 reduced-motion：行过渡与值脉冲都旁路，静态 is-changed 仍在",
    d2r6.rows.includes("t") && d2r6.transitions === d2r5.transitions &&
      d2r8.changed.join(",") === "a,j" && d2r8.pulses === d2r7.pulses,
    JSON.stringify({ d2r5, d2r6, d2r7, d2r8 }));
  await setReduced(false);

  // ── D2 CallTree（#122 D2）：深树 visited 链 + view→raw 当前节点 + 相机平滑/旁路 ──
  // 修前缺陷：frameNode 按指令帧建，语句级拿 view 下标直查 ⇒ 当前节点/路径/
  // 相机取景错帧（deep 帧 view 10 ↔ raw 56）。本锚用 frameAt 的 call_stack
  // 真值对 DOM 路径全等断言。
  await setUserMotion(true); // D0 收尾应已为 on；防前序套件/异常遗留
  await evaluate("window.__pilot.motion.transitionCount = 0; window.__pilot.motion.cameraAnimations = 0; true");
  await pickLesson("global_struct");
  await sleep(800);
  if (await evaluate("window.__pilot.session.playing")) {
    await evaluate(`document.querySelector('[data-act="play"]')?.click()`);
    await sleep(200);
  }
  const deep = await evaluate<number>("window.__pilot.session.viewFrames.findIndex((f) => (f.call_stack ?? []).length >= 4)");
  await evaluate(`window.__pilot.seek(${deep})`);
  await sleep(500);
  const d2t = await evaluate<D2Tree>(`(() => {
    const s = window.__pilot.session;
    const f = window.__pilot.frameAt(s.idx);
    const names = ["prog", ...((f?.call_stack ?? []).map((x) => x.func_name))];
    return {
      nodes: document.querySelectorAll('.vr-node').length,
      edges: document.querySelectorAll('.vr-edge').length,
      current: document.querySelectorAll('.vr-node.is-current').length,
      visited: document.querySelectorAll('.vr-node.is-visited').length,
      edgesVisited: document.querySelectorAll('.vr-edge.is-visited').length,
      compact: !!document.querySelector('.vr-tree-compact'),
      canvas: !!document.querySelector('.vr-canvas svg'),
      transitions: window.__pilot.motion.transitionCount,
      idx: s.idx,
      rawIdx: s.rawIndexAt(s.idx),
      path: document.querySelector('.vr-treefoot .vr-path')?.textContent?.trim() ?? '',
      expected: names.join(' → '),
      currentNode: document.querySelector('.vr-node.is-current text')?.textContent ?? '',
      vb: document.querySelector('.vr-canvas svg')?.getAttribute('viewBox') ?? null,
      cameraMoves: window.__pilot.motion.cameraAnimations,
    };
  })()`);
  const d2tPath = d2t.path.replace(/\s*×\d+$/, "");
  check("D2 深树：view→raw 映射当前节点/路径全等 + visited 链 + 树进出场",
    deep >= 0 && d2t.idx === deep && d2t.rawIdx !== d2t.idx &&
      d2t.nodes > 10 && d2t.edges > 10 && d2t.current === 1 &&
      d2t.visited >= 4 && d2t.edgesVisited >= 3 && d2t.compact === false && d2t.canvas === true &&
      d2tPath === d2t.expected && d2t.currentNode.includes(d2t.expected.split(" → ").pop() ?? "\u0000") &&
      d2t.transitions >= 100,
    JSON.stringify(d2t));

  // 相机：正常 seek 走 Tween（cameraAnimations 增量 + viewBox 改变）；
  // reduced 下瞬时到同一目标（零动画，viewBox 与正常收敛值一致）。
  await evaluate("window.__pilot.motion.cameraAnimations = 0; window.__pilot.seek(0); true");
  await sleep(400);
  const d2vb0 = await evaluate<string | null>("document.querySelector('.vr-canvas svg')?.getAttribute('viewBox') ?? null");
  await evaluate(`window.__pilot.seek(${deep})`);
  await sleep(300);
  const d2vb1 = await evaluate<string | null>("document.querySelector('.vr-canvas svg')?.getAttribute('viewBox') ?? null");
  const d2camMoves = await evaluate<number>("window.__pilot.motion.cameraAnimations");
  await setReduced(true);
  await evaluate("window.__pilot.motion.cameraAnimations = 0; window.__pilot.seek(0); true");
  await sleep(200);
  await evaluate(`window.__pilot.seek(${deep})`);
  await sleep(200);
  const d2camR = await evaluate<D2Cam>(`(() => ({
    vb: document.querySelector('.vr-canvas svg')?.getAttribute('viewBox') ?? null,
    moves: window.__pilot.motion.cameraAnimations,
  }))()`);
  const vbNum = (s: string | null): number[] => (s ?? "").split(/\s+/).map(Number);
  const nearVb = (a: string | null, b: string | null): boolean => {
    const x = vbNum(a); const y = vbNum(b);
    return x.length === 4 && y.length === 4 && x.every((v, i) => Math.abs(v - (y[i] ?? Number.NaN)) <= 1);
  };

  // reduced 树过渡：换到另一门深树课（hanoi），树照建、JS 过渡零放行。
  await evaluate("window.__pilot.motion.transitionCount = 0; true");
  await pickLesson("hanoi");
  await sleep(800);
  if (await evaluate("window.__pilot.session.playing")) {
    await evaluate(`document.querySelector('[data-act="play"]')?.click()`);
    await sleep(200);
  }
  const d2h = await evaluate<D2ReducedTree>(`(() => ({
    nodes: document.querySelectorAll('.vr-node').length,
    transitions: window.__pilot.motion.transitionCount,
  }))()`);
  check("D2 相机：正常 Tween 平滑、reduced 瞬时；换树过渡 reduced 全旁路",
    d2camMoves >= 1 && d2vb0 !== d2vb1 && d2camR.moves === 0 && nearVb(d2camR.vb, d2vb1) &&
      d2h.nodes > 3 && d2h.transitions === 0,
    JSON.stringify({ d2vb0, d2vb1, d2camMoves, d2camR, d2h }));
  await setReduced(false);
  } catch (err) {
    await setReduced(false).catch(() => undefined);
    await setUserMotion(true).catch(() => undefined);
    const msg = String((err as Error)?.message ?? err).slice(0, 200);
    results.push({ name: "D1/D0/D2 段异常（后续锚继续）", ok: false, detail: msg });
    console.log("FAIL  D1/D0/D2 段异常（后续锚继续）  — " + msg);
  }

  // ── D1b 多数组归属接线（P3-1）：ty=2 的 extras 无数组名，ArrayCells 必须
  //    把 snap.name 传给 swapPairs——去掉第三参时两个数组会同时点亮同号格。
  //    用合成课（a 交换 / b 不动）做接线锚；纯函数锚只能证明函数对，证明不了接上。
  try {
    await setReduced(false);
    await setUserMotion(true);
    await pickLesson("bubble");
    const multiSrc = [
      "int main() {",
      "  int a[3] = {3, 1, 2};",
      "  int b[3] = {9, 8, 7};",
      "  for (int i = 0; i < 1; i++)",
      "    for (int j = 0; j < 2; j++)",
      "      if (a[j] > a[j + 1]) {",
      "        int t = a[j];",
      "        a[j] = a[j + 1];",
      "        a[j + 1] = t;",
      "      }",
      "  return 0;",
      "}",
    ].join("\n");
    await evaluate(`window.__pilot.collect(${JSON.stringify(multiSrc)}, [], { autoplay: false })`);
    await waitFor("!window.__pilot.session.collecting && window.__pilot.session.viewFrames.length > 0", 60000);
    const mi = await evaluate<number>(`(() => {
      const s = window.__pilot.session;
      return s.viewFrames.findIndex((_, i) => s.eventsAt(i).some((e) => e.ty === 2 && e.context.includes('a[')));
    })()`);
    await evaluate(`window.__pilot.seek(${mi})`);
    await sleep(400);
    const d1m = await evaluate<D1Multi>(`(() => ({
      idx: window.__pilot.session.idx,
      secs: [...document.querySelectorAll('[aria-label="数组可视化"]')].map((sec) => ({
        title: sec.querySelector('.vr-label')?.textContent ?? '',
        swap: sec.querySelector('.vr-cells')?.getAttribute('data-swap') ?? '',
        cells: sec.querySelectorAll('.vr-cell.is-swap-event').length,
        legend: !!sec.querySelector('[data-swap-legend]'),
      })),
    }))()`);
    const sa = d1m.secs.find((s) => s.title.includes("数组 a"));
    const sb = d1m.secs.find((s) => s.title.includes("数组 b"));
    check("D1b 多数组归属：只有事件点名的 a 亮交换面，b 不串格（P3-1）",
      mi >= 0 && d1m.idx === mi && d1m.secs.length === 2 &&
        sa !== undefined && sa.swap === "0-1" && sa.cells === 2 && sa.legend === true &&
        sb !== undefined && sb.swap === "" && sb.cells === 0 && sb.legend === false,
      JSON.stringify(d1m));
  } catch (err) {
    const msg = String((err as Error)?.message ?? err).slice(0, 200);
    results.push({ name: "D1b 多数组归属（P3-1）段异常", ok: false, detail: msg });
    console.log("FAIL  D1b 多数组归属（P3-1）段异常  — " + msg);
  }

  // ── B6 第二门旗舰课 uaf（#222 P1 内容扩面）：3 幕（申请写入 / 释放 / 悬垂读），
  //    点幕 → 幕头与分幕带同步；幕首帧 = 0、第 2 幕首帧 = 3（释放帧）──
  await pickLesson("uaf");
  // pickLesson 返回后仍有一段「落地定位」异步（首访中段 / 继续上次）会把 idx 再
  // 挪一次——等落定再点幕，否则点第 1 幕会被随后定位覆盖（实测 idx 0 → 5）。
  await sleep(900);
  const b6 = await evaluate<B6>(`(() => ({
    n: window.__pilot.session.viewFrames.length,
    beats: document.querySelectorAll('.vr-beat').length,
    bands: document.querySelectorAll('.vr-band').length,
    first: document.querySelector('.vr-beat')?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
  }))()`);
  await evaluate("document.querySelectorAll('.vr-beat')[0]?.click(); true");
  await sleep(250);
  const b6start = await evaluate<B6Start>(`(() => ({
    idx: window.__pilot.session.idx,
    stage: document.querySelector('.vr-stagehead-title')?.textContent?.trim() ?? '',
    kicker: document.querySelector('.vr-stagehead-kicker')?.textContent?.trim() ?? '',
    note: document.querySelector('.vr-scenenote-title')?.textContent?.trim() ?? '',
  }))()`);
  await evaluate("document.querySelectorAll('.vr-beat')[1]?.click(); true");
  await sleep(250);
  const b6free = await evaluate<B6Free>(`(() => ({
    idx: window.__pilot.session.idx,
    stage: document.querySelector('.vr-stagehead-title')?.textContent?.trim() ?? '',
    kicker: document.querySelector('.vr-stagehead-kicker')?.textContent?.trim() ?? '',
  }))()`);
  check("B6 uaf 三幕分镜（#222 内容扩面）",
    b6.n === 6 && b6.beats === 3 && b6.bands === 3 && b6.first.includes("01") &&
      b6start.idx === 0 && b6start.stage.includes("申请与写入") && b6start.kicker.includes("帧 0–2") &&
      b6start.note.includes("申请与写入") && b6free.idx === 3 && b6free.stage.includes("释放") && b6free.kicker.includes("帧 3"),
    JSON.stringify({ b6, b6start, b6free }));

  // ── B7 第三门旗舰课 bubble_sort（#222 P1 内容扩面）：65 帧压成 6 幕；
  //    第 5 幕（明界：最后一轮一次比较零交换）是「算法正确 ≠ 算法知道」的
  //    教学锚，点幕必须跳到帧 48（#238 锚点化：幕 5 = @arr_change:17+1..19，与正文表同源）且幕头/本幕卡同步；第 6 幕收尾 51–64 ──
  await pickLesson("bubble_sort");
  await sleep(900);
  // 65 帧 × 8fps 播放要 ~8s：断言前先停播（seek 本身不停播，B6 的 6 帧课
  // 等 900ms 已自然播完，本课不行——不停会读到漂移帧）
  if (await evaluate("window.__pilot.session.playing")) {
    await evaluate(`document.querySelector('[data-act="play"]')?.click()`);
    await sleep(150);
  }
  const b7 = await evaluate<B6>(`(() => ({
    n: window.__pilot.session.viewFrames.length,
    beats: document.querySelectorAll('.vr-beat').length,
    bands: document.querySelectorAll('.vr-band').length,
    first: document.querySelector('.vr-beat')?.textContent?.replace(/\\s+/g, ' ').trim() ?? '',
  }))()`);
  await evaluate("document.querySelectorAll('.vr-beat')[4]?.click(); true");
  await sleep(250);
  const b7last = await evaluate<B7Last>(`(() => ({
    idx: window.__pilot.session.idx,
    stage: document.querySelector('.vr-stagehead-title')?.textContent?.trim() ?? '',
    kicker: document.querySelector('.vr-stagehead-kicker')?.textContent?.trim() ?? '',
    note: document.querySelector('.vr-scenenote-title')?.textContent?.trim() ?? '',
    cells: document.querySelectorAll('.vr-cell').length,
  }))()`);
  await evaluate("document.querySelectorAll('.vr-beat')[5]?.click(); true");
  await sleep(250);
  const b7end = await evaluate<B6Free>(`(() => ({
    idx: window.__pilot.session.idx,
    stage: document.querySelector('.vr-stagehead-title')?.textContent?.trim() ?? '',
    kicker: document.querySelector('.vr-stagehead-kicker')?.textContent?.trim() ?? '',
  }))()`);
  check("B7 bubble_sort 六幕分镜（#222 内容扩面）",
    b7.n === 65 && b7.beats === 6 && b7.bands === 6 && b7.first.includes("01") &&
      b7last.idx === 48 && b7last.stage.includes("最后一轮") && b7last.kicker.includes("帧 48–50") &&
      b7last.note.includes("最后一轮") && b7last.cells > 0 &&
      b7end.idx === 51 && b7end.stage.includes("收尾") && b7end.kicker.includes("帧 51–64"),
    JSON.stringify({ b7, b7last, b7end }));

  // ── B8 内存/协议两模式 P1 全页形态（#222 P1，2026-10-22）：模式切换后
  //    exec 三栏整体退役、页头模式条 + 左证据面 + 右叙事栏接管；内存页四轨 +
  //    隔离区行（共 5 行；未知 kind 另起轨）
  //    六格统计 + freed 块 + E3060 叙事；协议页四组 15 行（展开 22 方法）+
  //    20 方法本页消费 + schema 台账 + 当前帧 JSON；切回执行模式恢复三栏 ──
  await pickLesson("uaf");
  await sleep(900);
  await evaluate("[...document.querySelectorAll('.vr-mode')].find(b => b.textContent.trim() === '内存')?.click(); true");
  await sleep(300);
  const b8mem = await evaluate<B8Mem>(`(() => ({
    mode: window.__pilot.ui.mode,
    page: !!document.querySelector('.vr-modebench'),
    bench: !!document.querySelector('.vr-bench'),
    tabs: document.querySelectorAll('.vr-modebar .vr-mode').length,
    tracks: document.querySelectorAll('.vr-mem-row').length,
    stats: document.querySelectorAll('.vr-mem-stats.is-wide > span').length,
    freed: document.querySelectorAll('.vr-mem-seg.is-freed').length,
    alert: document.querySelector('.vr-side-alert')?.textContent?.includes('E3060') ?? false,
    questions: document.querySelectorAll('.vr-side-q dl > div').length,
    overflow: document.documentElement.scrollWidth - window.innerWidth,
  }))()`);
  await evaluate("[...document.querySelectorAll('.vr-mode')].find(b => b.textContent.trim() === '协议')?.click(); true");
  await sleep(300);
  const b8proto = await evaluate<B8Proto>(`(() => ({
    mode: window.__pilot.ui.mode,
    groups: document.querySelectorAll('.vr-proto-group').length,
    methods: document.querySelectorAll('.vr-proto-method').length,
    used: document.querySelectorAll('.vr-proto-method .m-use.is-yes').length,
    sideCount: document.querySelector('.vr-side-count b')?.textContent?.trim() ?? '',
    facts: document.querySelector('.vr-proto-facts')?.textContent?.replace(/\\s+/g, ' ') ?? '',
    ledger: document.querySelectorAll('.vr-proto-table tbody tr').length,
    frame: (document.querySelector('.vr-proto-frame')?.textContent ?? '').includes('step_index'),
    overflow: document.documentElement.scrollWidth - window.innerWidth,
  }))()`);
  await evaluate("[...document.querySelectorAll('.vr-mode')].find(b => b.textContent.trim() === '执行')?.click(); true");
  await sleep(250);
  const b8back = await evaluate<B8Back>(`(() => ({
    mode: window.__pilot.ui.mode,
    bench: !!document.querySelector('.vr-bench'),
    page: !!document.querySelector('.vr-modebench'),
  }))()`);
  check("B8 内存/协议全页形态（#222 P1）",
    b8mem.mode === "mem" && b8mem.page === true && b8mem.bench === false && b8mem.tabs === 3 &&
      b8mem.tracks === 5 && b8mem.stats === 6 && b8mem.freed >= 1 && b8mem.alert === true &&
      b8mem.questions === 3 && b8mem.overflow <= 1 &&
      b8proto.mode === "proto" && b8proto.groups === 4 && b8proto.methods === 15 && b8proto.used === 13 &&
      b8proto.sideCount === "20" && b8proto.facts.includes("15 行 / 22 方法") &&
      b8proto.ledger > 0 && b8proto.frame === true && b8proto.overflow <= 1 &&
      b8back.mode === "exec" && b8back.bench === true && b8back.page === false,
    JSON.stringify({ b8mem, b8proto, b8back }));

  // ── B9 目录 / 手册 P2 形态（#222 P2，2026-10-22）：目录 = 章路径 + 课列 +
  //    章节面板（旧预览面板退役；课列单击即开课）；手册 = 六段证据链 +
  //    三问并列 + 同族码 + 右栏阅读法 ──
  await openEntry();
  const b9entry = await evaluate<B9Entry>(`(() => ({
    chapters: document.querySelectorAll('.vr-path .vr-chapter').length,
    rows: document.querySelectorAll('.vr-lesson-row').length,
    panel: !!document.querySelector('.vr-chapterpanel'),
    peek: document.querySelectorAll('.vr-peek > li').length,
    preview: !!document.querySelector('.vr-preview'),
    hero: document.querySelector('.vr-entry-hero h1')?.textContent?.replace(/\\s+/g, '') ?? '',
  }))()`);
  await evaluate(`[...document.querySelectorAll('button')].find(b => (b.textContent || '').includes('诊断手册'))?.click(); true`);
  await waitFor("window.__pilot.ui.screen === 'ref'", 20000);
  // 选 E3060：示例 / 常见原因 / 同族 / 关联课齐全，六段证据链都在（E1001 无示例
  // 会按「无示例则隐藏」少一段——那是数据面诚实，不是缺段）
  await evaluate("window.__pilot.ui.refCode = 'E3060'; true");
  await sleep(350);
  const b9ref = await evaluate<B9Ref>(`(() => ({
    secs: document.querySelectorAll('.vr-ref-sec').length,
    three: document.querySelectorAll('.vr-ref-three > .vr-ref-q').length,
    fam: document.querySelectorAll('.vr-ref-famchip').length,
    side: !!document.querySelector('.vr-ref-side'),
    discrim: document.querySelectorAll('.vr-ref-discrim tbody tr').length,
    back: [...document.querySelectorAll('button')].some(b => (b.textContent || '').includes('返回实验台')),
    h1: document.querySelector('.vr-ref-detail h1')?.textContent?.trim() ?? '',
  }))()`);
  check("B9 目录/手册 P2 形态（#222 P2）",
    b9entry.chapters === 9 && b9entry.rows > 0 && b9entry.panel === true && b9entry.peek === 3 &&
      b9entry.preview === false && b9entry.hero.includes("从一行C开始") &&
      b9ref.secs === 6 && b9ref.three === 3 && b9ref.fam > 0 && b9ref.side === true &&
      b9ref.discrim > 0 && b9ref.back === true && b9ref.h1.length > 0,
    JSON.stringify({ b9entry, b9ref }));

  // ── B10 专注模式（#222 P4，2026-10-22）：F 进 / Esc 出，书栏与参数退役、
  //    顶栏换 FOCUS 标签 + 帧号 + 退出；URL ?focus=1 同步（可直达/可分享） ──
  await evaluate(`[...document.querySelectorAll('button')].find(b => (b.textContent || '').includes('返回实验台'))?.click(); true`);
  await waitFor("window.__pilot.ui.screen === 'work'", 20000);
  await sleep(300);
  const pressKey = async (k: string, code: string, vk: number): Promise<void> => {
    await send("Input.dispatchKeyEvent", { type: "keyDown", key: k, code, windowsVirtualKeyCode: vk });
    await send("Input.dispatchKeyEvent", { type: "keyUp", key: k, code, windowsVirtualKeyCode: vk });
  };
  await pressKey("f", "KeyF", 70);
  await waitFor("window.__pilot.ui.focus === true", 10000);
  await sleep(250);
  const b10on = await evaluate<B10On>(`(() => ({
    focus: window.__pilot.ui.focus,
    bench: !!document.querySelector('.vr-bench.is-focus'),
    rail: getComputedStyle(document.querySelector('.vr-colrail')).display,
    badge: !!document.querySelector('.vr-focusbadge'),
    frame: document.querySelector('.vr-focusframe')?.textContent?.trim() ?? '',
    modes: getComputedStyle(document.querySelector('.vr-colnow .vr-modes')).display,
    url: location.search,
  }))()`);
  await pressKey("Escape", "Escape", 27);
  await waitFor("window.__pilot.ui.focus === false", 10000);
  await sleep(250);
  const b10off = await evaluate<B10Off>(`(() => ({
    focus: window.__pilot.ui.focus,
    bench: !!document.querySelector('.vr-bench.is-focus'),
    rail: getComputedStyle(document.querySelector('.vr-colrail')).display,
    url: location.search,
  }))()`);

  // 守卫：mem 模式按 F 不得出专注顶栏（审查 P2-2）
  await evaluate("[...document.querySelectorAll('.vr-mode')].find(b => b.textContent.trim() === '内存')?.click(); true");
  await waitFor("window.__pilot.ui.mode === 'mem'", 10000);
  await sleep(200);
  await pressKey("f", "KeyF", 70);
  await sleep(250);
  const b10mem = await evaluate<B10Mem>(`(() => ({
    mode: window.__pilot.ui.mode,
    focus: window.__pilot.ui.focus,
    bench: !!document.querySelector('.vr-bench.is-focus'),
    url: location.search,
  }))()`);
  await evaluate("[...document.querySelectorAll('.vr-mode')].find(b => b.textContent.trim() === '执行')?.click(); true");
  await waitFor("window.__pilot.ui.mode === 'exec'", 10000);
  await sleep(200);

  // 深链：?focus=1 首帧即专注（审查 P2-3：旧 B10 只走键盘，标题声称的深链没测）
  await send("Page.navigate", { url: PAGE + "?focus=1&r=" + Date.now() });
  await waitFor("window.__pilot?.ui?.ready === true", 40000);
  await waitFor("window.__pilot.ui.focus === true", 15000);
  await sleep(300);
  const b10link = await evaluate<B10On>(`(() => ({
    focus: window.__pilot.ui.focus,
    bench: !!document.querySelector('.vr-bench.is-focus'),
    rail: getComputedStyle(document.querySelector('.vr-colrail')).display,
    badge: !!document.querySelector('.vr-focusbadge'),
    url: location.search,
  }))()`);
  // 回普通页给 F5/B11 用
  await send("Page.navigate", { url: PAGE + "?r=" + Date.now() });
  await waitFor("window.__pilot?.ui?.ready === true", 40000);
  await waitFor("window.__pilot.session.viewFrames.length > 0 && !window.__pilot.session.collecting", 60000);
  await sleep(400);

  check("B10 专注模式 F/Esc + mem 守卫 + ?focus=1 深链（#222 P4）",
    b10on.focus === true && b10on.bench === true && b10on.rail === "none" && b10on.badge === true &&
      b10on.frame.includes("/") && b10on.modes === "none" && b10on.url.includes("focus=1") &&
      b10off.focus === false && b10off.bench === false && b10off.rail !== "none" && !b10off.url.includes("focus=1") &&
      b10mem.mode === "mem" && b10mem.focus === false && b10mem.bench === false && !b10mem.url.includes("focus=1") &&
      b10link.focus === true && b10link.bench === true && b10link.rail === "none" && b10link.badge === true && b10link.url.includes("focus=1"),
    JSON.stringify({ b10on, b10off, b10mem, b10link }));

  // ── F5 char 数组可视化零崩溃（P1-5）──
  // 2026-10-18 加固：逐帧 seek 全量帧（此前只看首个数组帧 + 800ms，晚帧崩溃
  // 会漏抓）。char 课 146 帧 × 每帧一次数组格/变量/树渲染。
  await evaluate("window.__errs = []");
  await pickLesson("string_match_bf");
  if (await evaluate("window.__pilot.session.playing")) {
    await evaluate(`document.querySelector('[data-act="play"]')?.click()`);
    await sleep(120);
  }
  const f5total = await evaluate<number>("window.__pilot.session.viewFrames.length");
  const f5arr = await evaluate<number>(`window.__pilot.session.viewFrames.findIndex((f) => (f.array_snapshots?.length ?? 0) > 0)`);
  for (let i = 0; i < f5total; i++) {
    await evaluate(`window.__pilot.seek(${i})`);
    await sleep(3);
  }
  if (f5arr >= 0) {
    await evaluate(`window.__pilot.seek(${f5arr})`);
    await sleep(200);
  }
  const f5 = await evaluate<F5>(`(() => ({
    cells: document.querySelectorAll(".vr-cell").length,
    frames: window.__pilot.session.frames.length,
    view: window.__pilot.session.viewFrames.length,
    snapAt: window.__pilot.session.viewFrames[window.__pilot.session.idx]?.array_snapshots?.length ?? 0,
  }))()`);
  const f5errs = JSON.parse(await errs()) as string[];
  check("F5 char 数组全帧零 each_key_duplicate（P1-5）",
    f5.frames > 0 && f5.view === f5total && f5arr >= 0 && f5.cells > 0 && f5errs.every((e) => !e.includes("each_key_duplicate")),
    JSON.stringify(f5) + " sweep=" + f5total + " errs=" + JSON.stringify(f5errs.slice(0, 2)));

  // ── F6 trap E 码 → 手册联动（P2-10）──
  await pickLesson("uaf");
  await sleep(600);
  const hasCode = await waitFor("!!document.querySelector('.vr-trap-body .tp-code[data-ecode]')", 10000).catch(() => false);
  if (hasCode) {
    const code = await evaluate<string | null>("document.querySelector('.vr-trap-body .tp-code[data-ecode]').getAttribute('data-ecode')");
    await evaluate("document.querySelector('.vr-trap-body .tp-code[data-ecode]').click()");
    await waitFor("window.__pilot.ui.screen === 'ref'", 10000);
    await sleep(400);
    const f6 = await evaluate<F6>(`(() => ({
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
  const f7chapters = await evaluate<number>("document.querySelectorAll('.vr-chapter').length");
  const f7rows: number[] = [];
  for (let i = 0; i < f7chapters; i++) {
    await evaluate(`document.querySelectorAll('.vr-chapter')[${i}]?.click()`);
    await sleep(160);
    f7rows.push(await evaluate<number>("document.querySelectorAll('.vr-lesson-row').length"));
  }
  const f7errs = JSON.parse(await errs()) as string[];
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
    // 2026-10-22 加固：原先靠 CPU 6x 节流 + 25ms 轮询捕捉 (ready && frames=0)
    // 瞬态窗口——CI 实测轮询首帧时采集已完成，锚假红（sawReady=true 但窗口没抓到）。
    // 改为读 App.svelte 在 ready 翻态瞬间写下的 __readyFrames 快照：采集快慢无关，
    // 「ready 那一刻帧数 = 0」是可复现的事实。
    await send("Page.navigate", { url: PAGE + "?f8=" + Date.now() });
    await waitFor("window.__pilot?.ui?.ready === true", 40000);
    await waitFor("window.__pilot.session.frames.length > 0", 40000);
    const f8 = JSON.parse(await evaluate<string>("JSON.stringify({ readyFrames: window.__readyFrames ?? null, frames: window.__pilot.session.frames.length })")) as F8;
    check("F8 首访 shell 先行（ui.ready 不等首课采集）", f8.readyFrames === 0 && f8.frames > 0, JSON.stringify(f8));
    await sleep(400);
  }

  // ── B11 移动工作台 P3（#222 P3，2026-10-22）：390 下书栏标题/分镜轨退役、
  //    代码默认收起、当前行卡顶到数组之后、时间轴在讲解之前；「代码」按钮
  //    展开/收起整段源码（桌面恢复 1440） ──
  await send("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await sleep(500);
  const b11 = await evaluate<B11>(`(() => {
    const q = (s) => document.querySelector(s);
    const top = (s) => (q(s) ? Math.round(q(s).getBoundingClientRect().top) : null);
    const disp = (s) => (q(s) ? getComputedStyle(q(s)).display : null);
    return {
      title: disp('.vr-colrail .vr-title'),
      code: disp('.vr-codebody'),
      line: disp('.vr-mobileline'),
      lineText: q('.vr-mobileline code')?.textContent?.trim() ?? '',
      btn: disp('.vr-mobilecodebtn'),
      head: top('.vr-stagehead'), arr: top('[aria-label="数组可视化"]'), lineTop: top('.vr-mobileline'), dock: top('.vr-timeline'),
      overflow: document.documentElement.scrollWidth - innerWidth,
    };
  })()`);
  await evaluate("document.querySelector('.vr-mobilecodebtn')?.click(); true");
  await sleep(250);
  const b11open = await evaluate<B11Open>(`(() => ({
    code: getComputedStyle(document.querySelector('.vr-codebody')).display,
    expanded: document.querySelector('.vr-mobilecodebtn')?.getAttribute('aria-expanded'),
  }))()`);
  await evaluate("document.querySelector('.vr-mobilecodebtn')?.click(); true");
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await sleep(300);
  check("B11 移动工作台 P3（390 首屏顺序 + 代码折叠）",
    b11.title === "none" && b11.code === "none" && b11.line === "block" && b11.lineText.length > 0 &&
      b11.btn !== "none" && b11.head !== null && b11.arr !== null && b11.lineTop !== null && b11.dock !== null &&
      b11.head < b11.arr && b11.arr < b11.lineTop && b11.lineTop < b11.dock &&
      b11.overflow <= 1 && b11open.code === "flex" && b11open.expanded === "true",
    JSON.stringify({ b11, b11open }));

  const executed = results.length;
  if (executed !== DECLARED_ANCHORS) {
    results.push({
      name: "锚点覆盖完整（声明/实跑）",
      ok: false,
      detail: `声明 ${DECLARED_ANCHORS} / 实跑 ${executed}`,
    });
    console.log(`FAIL  锚点覆盖完整（声明/实跑）  — 声明 ${DECLARED_ANCHORS} / 实跑 ${executed}`);
  }
  const fails = results.filter((r) => !r.ok);
  console.log(`===== ${results.length - fails.length}/${results.length} 通过 =====`);
  cdp.close();
  process.exit(fails.length ? 1 : 0);
}

run().catch((e) => {
  console.error("E2E 异常:", e.message);
  console.error(`实跑 ${results.length} / 声明 ${DECLARED_ANCHORS}——覆盖静默缺失，按失败处理`);
  process.exit(2);
});
