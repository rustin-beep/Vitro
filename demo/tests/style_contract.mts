// 样式契约闸（#222 P0 第二批，2026-10-21）：computed-style 基线对账。
//
// 为什么不是像素闸：像素基线依赖字体栅格化，跨 OS 假红成本高；本闸取**跨 OS
// 确定**的 computed 值——颜色（rgb 串）、字体族声明、连字开关、letter-spacing
// ——由 CSS/token 决定，不经过栅格化。像素闸已于 2026-10-22 按用户裁定退役
// （PNG 基线入库为噪声），本闸是画面样式的主力机判面。
//
// 覆盖面：五主题（清单读 moonbit/style/tokens.json `themeOrder`，不在脚本里手抄）×
// 固定选择器集 × 固定属性集——抓「组件没用上主题 token / 某主题漏定义 /
// 连字没关」。边界（显式登记）：只在工作态 exec 首课 DOM 取样；目录/手册/
// 内存/协议/专注页不在选择器集内，由 E2E 结构锚 + ui_lint 守（审查 P3 项）。
//
// 用法：
//   node demo/tests/style_contract.mts http://127.0.0.1:8931/            # 比对（红即 exit 1）
//   node demo/tests/style_contract.mts http://127.0.0.1:8931/ --update   # 人工令：重写基线
// 前提：demo dist 已构建 + 静态服在跑 + headless Chrome 的 CDP 9222（CI 为
// windows-latest + Chrome/Edge）。
//
// --update 写盘前强制完整性断言（审查 P2-5）：每个选择器必须命中、每个 token
// 必须非空——否则 null / 空串会被冻进基线，下一次比较自然全等（D8 更新侧
// 塌缩）。比对路径也校验基线本身完整，坏基线 fail loud。
//
// 基线：demo/tests/style_contract.json（入库，逐主题）。
// 判定：深比较；任一路径不同即红并列期望/实际；--update 才写盘（与 E2E
// golden 同款「快照不得测试内动态刷新」纪律）。

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { connectCdp, sleep, type CdpClient } from "./cdp.mts";

const BASE = process.argv[2] ?? "http://127.0.0.1:8931/";
const UPDATE = process.argv.includes("--update");
const HERE = dirname(fileURLToPath(import.meta.url));
const BASELINE = resolve(HERE, "style_contract.json");
// 主题清单单源 = tokens.json（审查 P3：旧脚本硬编码五主题，新增主题会漏测）
const TOKENS = JSON.parse(readFileSync(new URL("../../moonbit/style/tokens.json", import.meta.url), "utf8")) as {
  themeOrder?: unknown;
  themes?: Record<string, unknown>;
};
const THEMES: string[] = Array.isArray(TOKENS.themeOrder)
  ? TOKENS.themeOrder.filter((x): x is string => typeof x === "string")
  : Object.keys(TOKENS.themes ?? {});
if (!THEMES.length) {
  console.error("style_contract: moonbit/style/tokens.json 无 themeOrder/themes，拒绝空转");
  process.exit(2);
}

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

interface ThemeStyle {
  styles: Record<string, Record<string, string> | null>;
  vars: Record<string, string>;
}
type StyleDoc = Record<string, ThemeStyle>;
interface Diff {
  path: string;
  expected: unknown;
  actual: unknown;
}

let send: CdpClient["send"] = () => Promise.reject(new Error("CDP 未连接"));
let cdpEvaluate: CdpClient["evaluate"] = () => Promise.reject(new Error("CDP 未连接"));
let cdpWaitFor: CdpClient["waitFor"] = () => Promise.reject(new Error("CDP 未连接"));
let closeCdp: () => void = () => {};

const evaluate = <T = unknown,>(expr: string): Promise<T> => cdpEvaluate<T>(expr);
const waitFor = (expr: string, timeout = 60000): Promise<boolean> => cdpWaitFor(expr, timeout, 250);

async function connect(port = 9222): Promise<void> {
  const cdp = await connectCdp({ port });
  closeCdp = () => cdp.close();
  ({ send, evaluate: cdpEvaluate, waitFor: cdpWaitFor } = cdp);
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

// 就绪探测（#541 审阅处置，2026-11-17）：主题切换原为固定 sleep(200)，在
// CI 冷启动慢的 runner 上是竞态源——run 44094142934 attempt 1 实测：E2E
// setup 45s（正常 12s）时本步 10s 且 exit 2（完整性断言），同代码 attempt 2
// 4s 通过。改为轮询「本主题下全选择器可查 + 全 token 非空」，超时带清单判红。
const READY = `(() => {
  const missing = [];
  for (const sel of ${JSON.stringify(SELECTORS)}) if (!document.querySelector(sel)) missing.push(sel);
  const root = getComputedStyle(document.documentElement);
  const emptyVars = ${JSON.stringify(VARS)}.filter((v) => !root.getPropertyValue(v).trim());
  return { ok: missing.length === 0 && emptyVars.length === 0, missing, emptyVars };
})()`;

interface ReadyState {
  ok: boolean;
  missing: string[];
  emptyVars: string[];
}

/** 等本主题就绪（选择器齐全 + token 非空）。超时返回最后状态，由调用方判红
 *  （不在此处 exit——要把每个主题的缺失面聚齐再一次性报，便于定位）。 */
async function waitThemeReady(timeoutMs: number): Promise<ReadyState> {
  const t0 = Date.now();
  let last: ReadyState = { ok: false, missing: [], emptyVars: [] };
  for (;;) {
    last = await evaluate<ReadyState>(READY);
    if (last.ok) return last;
    if (Date.now() - t0 >= timeoutMs) return last;
    await sleep(100);
  }
}

/** 等本主题的采集结果**稳定**（连续两次全等）后再返回。
 *  必需：主题切换有 CSS transition（颜色/border-color），「就绪」只表示选择器
 *  与 token 在位，不表示过渡已收敛——直接采集会拿到中间色，在基线比对里表现
 *  为一整片 border 与 color 漂移（2026-11-17 本地实测：soft 主题 border 三色
 *  采到 rgb(191,174,145) 过渡值）。原实现用 sleep(200) 硬等，慢 runner 上不够
 *  （竞态源），此处改为稳定判定 + 上限，两边都覆盖。
 *  上限（settleMs）只兜底动画循环，不参与就绪超时。 */
async function waitThemeStable(timeoutMs: number, settleMs = 3000): Promise<{ ready: ReadyState; styles: ThemeStyle }> {
  const ready = await waitThemeReady(timeoutMs);
  let prev = await evaluate<ThemeStyle>(COLLECT);
  const t0 = Date.now();
  for (;;) {
    await sleep(120);
    const cur = await evaluate<ThemeStyle>(COLLECT);
    if (JSON.stringify(cur) === JSON.stringify(prev) || Date.now() - t0 >= settleMs) {
      return { ready, styles: cur };
    }
    prev = cur;
  }
}

function walkDiff(expected: unknown, actual: unknown, path: string, diffs: Diff[]): void {
  if (typeof expected === "object" && expected !== null && typeof actual === "object" && actual !== null) {
    const e = expected as Record<string, unknown>;
    const a = actual as Record<string, unknown>;
    const keys = new Set([...Object.keys(e), ...Object.keys(a)]);
    for (const k of keys) walkDiff(e[k], a[k], path ? path + "." + k : k, diffs);
    return;
  }
  if (expected !== actual) diffs.push({ path, expected, actual });
}

/** 完整性判定（审查 P2-5）：返回缺失清单；空数组 = 完整。--selftest 直接
 *  调它证红，--update / 比对路径共用同一判定。 */
function completenessProblems(doc: StyleDoc | undefined): string[] {
  const problems: string[] = [];
  for (const theme of THEMES) {
    const t = doc?.[theme];
    if (!t) {
      problems.push(`${theme}: 整主题缺失`);
      continue;
    }
    for (const sel of SELECTORS) if (!t.styles?.[sel]) problems.push(`${theme}: 选择器未命中 ${sel}`);
    for (const v of VARS) if (!t.vars?.[v]) problems.push(`${theme}: token 为空 ${v}`);
  }
  return problems;
}

/**
 * GitHub Actions 注解（#541 审阅处置，2026-11-17）：把失败细节写成 workflow
 * command，run 页面直接可见。此前完整性断言的缺失清单只进 stderr，而 GitHub
 * 的 annotation 只保留 exit code——CI 上出现过「只看到 exit code 2、不知道缺
 * 什么」的诊断盲区（run 44094142934 attempt 1：E2E 冷启动 45s，采集时页面未
 * 就绪，重跑 12s 即绿）。非 Actions 环境（本地跑）不输出，避免噪声。
 */
function ghAnnotate(level: "error" | "warning", title: string, detail: string): void {
  if (process.env["GITHUB_ACTIONS"] !== "true") return;
  const esc = (s: string): string => s.replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");
  console.log(`::${level} title=${esc(title)}::${esc(detail)}`);
}

/** 完整性断言：--update 写盘前 / 比对读基线后都必须通过——缺失选择器在
 *  COLLECT 里是 null、未定义 token 是空串，直接写进基线会让下一次比较自然
 *  全等（D8 更新侧塌缩）。任一缺失 fail loud。 */
function assertComplete(doc: StyleDoc | undefined, label: string): void {
  const problems = completenessProblems(doc);
  if (problems.length) {
    console.error(`style_contract: ${label}完整性断言失败（${problems.length} 处）——拒绝冻结/比对残缺基线：`);
    for (const p of problems.slice(0, 20)) console.error("  " + p);
    if (problems.length > 20) console.error(`  ...另有 ${problems.length - 20} 处`);
    ghAnnotate("error", `style_contract: ${label}完整性断言失败（${problems.length} 处）`,
      "拒绝冻结/比对残缺基线。前 10 处：\n" + problems.slice(0, 10).join("\n"));
    process.exit(2);
  }
}

// -selftest（J9）：完整 doc 必须 0 问题、残缺 doc 必须判红——证完整性判定
// 不是恒绿空转。纯内存，不连浏览器。
if (process.argv.includes("--selftest")) {
  const okStyles = Object.fromEntries(SELECTORS.map((s) => [s, { color: "rgb(0, 0, 0)" }]));
  const okVars = Object.fromEntries(VARS.map((v) => [v, "#000000"]));
  const good: StyleDoc = Object.fromEntries(THEMES.map((t) => [t, { styles: okStyles, vars: okVars }]));
  const bad: StyleDoc = { [THEMES[0] as string]: { styles: {}, vars: {} } };
  if (completenessProblems(good).length !== 0) {
    console.error("style_contract: -selftest 失败——完整 doc 被判残缺");
    process.exit(2);
  }
  if (completenessProblems(bad).length === 0) {
    console.error("style_contract: -selftest 失败——残缺 doc 未判红（完整性判定空转）");
    process.exit(2);
  }
  console.log("style_contract: -selftest 通过（完整 doc 0 问题 / 残缺 doc 判红）");
  process.exit(0);
}


/** CDP 就绪重试：CI 上 chrome 开端口可能晚于固定 sleep（实测 ECONNREFUSED）。
 *  只重试连接阶段，最多 30s；超时把最后一条错误带出来（fail loud 可诊断）。 */
async function connectWithRetry(port = 9222, timeoutMs = 30000) {
  const t0 = Date.now();
  for (;;) {
    try {
      return await connect(port);
    } catch (e) {
      if (Date.now() - t0 > timeoutMs) {
        const msg = e instanceof Error ? e.message : String(e);
        throw new Error("CDP " + port + " 在 " + timeoutMs + "ms 内未就绪：" + msg);
      }
      await new Promise((r) => setTimeout(r, 500));
    }
  }
}

async function main() {
  await connectWithRetry();
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url: BASE + "index.html?style=" + Date.now() });
  await waitFor("window.__pilot && window.__pilot.session.booted", 60000);
  // 先清持久化再重载：上次课/主题/字号会留在 localStorage 里（E2E/视觉闸跑完
  // 常停在别的课）——不清就会拿「另一门课的 DOM」去比基线，红得莫名其妙。
  await evaluate("localStorage.clear(); true");
  await send("Page.reload", { ignoreCache: true });
  await waitFor("window.__pilot && window.__pilot.ui.ready", 60000);
  await waitFor("window.__pilot && window.__pilot.session.viewFrames.length > 0", 90000);
  await sleep(500);

  // 字号档固定 14：em→px 的 computed 值随档位变（CI 新 profile 默认 14，本地
  // 持久化可能是 16）——不固定就会在「同一份代码」上出现假红。
  await evaluate('document.documentElement.setAttribute("data-size", "14"); true');
  const actual: StyleDoc = {};
  // 每主题就绪预算：CI 冷启动慢的 runner 上，主题切换后的样式/组件晚到是实测
  // 形态（见 READY 注释）。20s 远大于正常 <100ms，只在异常慢时才等待。
  const READY_TIMEOUT_MS = 20000;
  const notReady: string[] = [];
  for (const theme of THEMES) {
    await evaluate(`document.documentElement.setAttribute("data-theme", ${JSON.stringify(theme)}); true`);
    const { ready, styles } = await waitThemeStable(READY_TIMEOUT_MS);
    if (!ready.ok) {
      notReady.push(
        `${theme}: 缺选择器 [${ready.missing.join(", ") || "无"}]；空 token [${ready.emptyVars.join(", ") || "无"}]`,
      );
    }
    actual[theme] = styles;
  }
  closeCdp();
  if (notReady.length) {
    console.error(`style_contract: ${notReady.length} 个主题在 ${READY_TIMEOUT_MS}ms 内未就绪（渲染/加载慢或组件缺失）：`);
    for (const l of notReady) console.error("  " + l);
    ghAnnotate("error", `style_contract: ${notReady.length} 个主题 ${READY_TIMEOUT_MS}ms 内未就绪`,
      "采集前就绪等待超时（渲染慢/组件缺失）。未就绪明细：\n" + notReady.join("\n"));
    process.exit(2);
  }
  assertComplete(actual, "采集");

  if (UPDATE) {
    writeFileSync(BASELINE, JSON.stringify(actual, null, 2) + "\n");
    console.log(`style_contract: 基线已重写 ${BASELINE}（${THEMES.length} 主题 × ${SELECTORS.length} 选择器）`);
    return;
  }
  if (!existsSync(BASELINE)) {
    console.error(`style_contract: 缺基线 ${BASELINE}——先在 CI（windows-latest + Chrome/Edge）跑 --update 生成`);
    process.exit(1);
  }
  const expected = JSON.parse(readFileSync(BASELINE, "utf8")) as StyleDoc;
  assertComplete(expected, "基线");
  const diffs: Diff[] = [];
  walkDiff(expected, actual, "", diffs);
  if (diffs.length) {
    console.error(`style_contract: FAIL——${diffs.length} 处样式契约漂移`);
    for (const d of diffs.slice(0, 20)) console.error(`  ${d.path}\n    基线: ${JSON.stringify(d.expected)}\n    实际: ${JSON.stringify(d.actual)}`);
    if (diffs.length > 20) console.error(`  ...另有 ${diffs.length - 20} 处`);
    ghAnnotate("error", `style_contract: ${diffs.length} 处样式契约漂移`,
      "前 10 处：\n" + diffs.slice(0, 10).map((d) => `${d.path}（基线 ${JSON.stringify(d.expected)} / 实际 ${JSON.stringify(d.actual)}）`).join("\n"));
    process.exit(1);
  }
  console.log(`style_contract: PASS（${THEMES.length} 主题 × ${SELECTORS.length} 选择器 × ${PROPS.length} 属性）`);
}

main().catch((e) => {
  console.error("style_contract 异常:", e?.message ?? e);
  process.exit(1);
});
