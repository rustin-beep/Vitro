// 样式契约闸（#222 P0 第二批，2026-10-21）：computed-style 基线对账。
//
// 为什么不是像素闸：像素基线依赖字体栅格化，Windows/macOS 与 CI Ubuntu 会
// 假红（拍板稿明确基线必须在 CI Ubuntu + Chrome 生成）。本闸取的是**跨 OS
// 确定**的 computed 值——颜色（rgb 串）、字体族声明、连字开关、letter-spacing
// ——它们由 CSS/token 决定，不经过栅格化。像素闸仍待建（DESIGN.md §7 已标）。
//
// 覆盖面：五主题 × 固定选择器集 × 固定属性集——抓「组件没用上主题 token /
// 某主题漏定义 / 连字没关」这类 163 变量 + 61 处主题覆盖最容易漏的形态。
//
// 用法：
//   node demo/tests/style_contract.mjs http://127.0.0.1:8931/            # 比对（红即 exit 1）
//   node demo/tests/style_contract.mjs http://127.0.0.1:8931/ --update   # 人工令：重写基线
// 前提：demo dist 已构建 + 静态服在跑 + headless Chrome 的 CDP 9222。
//
// 基线：demo/tests/style_contract.json（入库，逐主题）。
// 判定：深比较；任一路径不同即红并列期望/实际；--update 才写盘（与 E2E
// golden 同款「快照不得测试内动态刷新」纪律）。

import http from "node:http";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const UPDATE = process.argv.includes("--update");
const HERE = dirname(fileURLToPath(import.meta.url));
const BASELINE = resolve(HERE, "style_contract.json");

const THEMES = ["ice", "rose", "soft", "paper", "blueprint"];

// 选择器集：覆盖外壳 / 课头 / 代码 / 幕头 / 分镜 / 索引格 / 时间轴 / 课文 /
// 等宽面 / 浮层。只在工作态取（首课已采集）。
const SELECTORS = [
  ".vr-masthead",
  ".vr-title",
  ".vr-status",
  ".vr-stagehead",
  ".vr-code",
  ".vr-codehead",
  ".cm-line",
  ".vr-beat.is-active",
  ".vr-beat.is-active .vr-beat-note",
  ".vr-cell",
  ".vr-colnow",
  ".vr-coldock",
  ".vr-transport",
  ".vr-label",
  ".vr-note p",
  ".vr-notefull > summary",
  ".vr-chip",
  ".vr-btn.vr-primary",
  ".vr-blockhead .vr-meta",
];

// 属性集：会算成确定字符串的那些（宽高/位置不入基线——字体无关但滚动条有
// 系统差异；本闸只守样式契约）。
const PROPS = [
  "background-color",
  "color",
  "border-top-color",
  "border-left-color",
  "border-bottom-color",
  "font-family",
  "font-variant-ligatures",
  "letter-spacing",
  "text-transform",
];

// 关键 token 的解析值（documentElement computed）——主题色板被换掉即红。
const VARS = ["--vr-bg", "--vr-panel", "--vr-ink", "--vr-ink-3", "--vr-amber", "--vr-rule", "--vr-mono"];

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
  if (r.exceptionDetails) throw new Error("eval 异常: " + JSON.stringify(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text));
  return r.result.value;
}

async function waitFor(expr, timeout = 60000) {
  const t0 = Date.now();
  for (;;) {
    if (await evaluate(expr)) return;
    if (Date.now() - t0 > timeout) throw new Error("waitFor 超时: " + expr.slice(0, 100));
    await sleep(250);
  }
}

async function connect(port = 9222) {
  const targets = await new Promise((res, rej) => {
    http
      .get({ host: "127.0.0.1", port, path: "/json/list" }, (r) => {
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

const COLLECT = `(() => {
  const out = {};
  for (const sel of ${JSON.stringify(SELECTORS)}) {
    const el = document.querySelector(sel);
    if (!el) { out[sel] = null; continue; }
    const cs = getComputedStyle(el);
    const rec = {};
    for (const prop of ${JSON.stringify(PROPS)}) rec[prop] = cs.getPropertyValue(prop);
    out[sel] = rec;
  }
  const root = getComputedStyle(document.documentElement);
  const vars = {};
  for (const v of ${JSON.stringify(VARS)}) vars[v] = root.getPropertyValue(v).trim();
  return { vars, styles: out };
})()`;

function walkDiff(expected, actual, path, diffs) {
  if (typeof expected === "object" && expected !== null && typeof actual === "object" && actual !== null) {
    const keys = new Set([...Object.keys(expected), ...Object.keys(actual)]);
    for (const k of keys) walkDiff(expected[k], actual[k], path ? path + "." + k : k, diffs);
    return;
  }
  if (expected !== actual) diffs.push({ path, expected, actual });
}

async function main() {
  await connect();
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url: BASE + "index.html" });
  await waitFor("window.__pilot && window.__pilot.session.booted", 60000);
  await waitFor("window.__pilot.ui.ready && window.__pilot.session.viewFrames.length > 0", 90000);
  await sleep(500);

  // 字号档固定 14：em→px 的 computed 值随档位变（CI 新 profile 默认 14，本地
  // 持久化可能是 16）——不固定就会在「同一份代码」上出现假红。
  await evaluate('document.documentElement.setAttribute("data-size", "14"); true');
  const actual = {};
  for (const theme of THEMES) {
    await evaluate(`document.documentElement.setAttribute("data-theme", ${JSON.stringify(theme)}); true`);
    await sleep(200);
    actual[theme] = await evaluate(COLLECT);
  }
  ws.close();

  if (UPDATE) {
    writeFileSync(BASELINE, JSON.stringify(actual, null, 2) + "\n");
    console.log(`style_contract: 基线已重写 ${BASELINE}（${THEMES.length} 主题 × ${SELECTORS.length} 选择器）`);
    return;
  }
  if (!existsSync(BASELINE)) {
    console.error(`style_contract: 缺基线 ${BASELINE}——先在 CI Ubuntu + Chrome 跑 --update 生成`);
    process.exit(1);
  }
  const expected = JSON.parse(readFileSync(BASELINE, "utf8"));
  const diffs = [];
  walkDiff(expected, actual, "", diffs);
  if (diffs.length) {
    console.error(`style_contract: FAIL——${diffs.length} 处样式契约漂移`);
    for (const d of diffs.slice(0, 20)) console.error(`  ${d.path}\n    基线: ${JSON.stringify(d.expected)}\n    实际: ${JSON.stringify(d.actual)}`);
    if (diffs.length > 20) console.error(`  ...另有 ${diffs.length - 20} 处`);
    process.exit(1);
  }
  console.log(`style_contract: PASS（${THEMES.length} 主题 × ${SELECTORS.length} 选择器 × ${PROPS.length} 属性）`);
}

main().catch((e) => {
  console.error("style_contract 异常:", e?.message ?? e);
  process.exit(1);
});
