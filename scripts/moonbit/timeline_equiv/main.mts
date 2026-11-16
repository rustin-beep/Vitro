#!/usr/bin/env node
// timeline_equiv —— TimelinePlan v0.2 等价对拍闸（#470 批一，2026-11-15；批四 v0.2 连坐）。
//
// 目的：证明「动效编排下沉」没有改变可观察行为。同一真实产物逐帧对比
// **旧规则（改造前壳层 swapPair/ctxMentions 的 TS 冻结副本，oracle）** 与
// **plan 路径（产物 doc.timeline + 真实 PLAYER 驱动的 DOM）**：
//   - 交换帧集合（旧规则有交换 cells 的帧 == plan 生效 sw 的帧 == DOM swap 帧）
//   - 字幕文本（#cap innerHTML 与旧公式逐字节相等；cap.t 与 semantic_label 同源）
//   - stage 关键类名（cell swap / cell changed 逐帧计数相等——changed 已换读
//     plan.ch（v0.2），旧规则差分是冻结 oracle 的对拍面）
// 两案例：bubble（数组真名 == 展示名 arr）与 bubble_sort（真名 a ≠ 字幕展示名
// arr 的 #469 分叉面；含 2 帧 a[4]↔a[5] 越界事件——旧规则靠 `hi >= len` 丢，
// plan 必须同样丢，否则 56 vs 54 即红）。
//
// 旧规则副本是**冻结 oracle**：不得随实现演进修改（改了就不是对拍）；plan
// 生成器在 moonbit/timeline。静态壳层只读 plan（旧 swapPair 已删）；interactive
// 路径页内 planStep 镜像按 live 帧实时产 plan（批二，壳层旧 legacySwapPair/
// ctxMentions 已删——其 TS 冻结副本仅存于本闸作等价 oracle）。
// 前置：moon build --release --target js cmd/mcp_js（CI 上一步已建）。
// 用法：node scripts/moonbit/timeline_equiv/main.mts
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  CheckRun,
  checkTimelinePlan,
  contextMentionsArray,
  driveScript,
  extractScript,
  makeLineAcc,
  toolTextOf,
  type FrameProbe,
  type MiniFrame,
  type TimelineStep,
  type VitroData,
} from "../mcp_smoke/main.mts";

/// bubble.c（v1 samples / mcp_smoke 同源——锚值依据，改语料须连坐）。
const BUBBLE_C = `#include <stdio.h>

void bubble_sort(int arr[], int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - 1 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                int tmp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
        }
    }
}

int main(void) {
    int arr[6] = {5, 2, 8, 1, 9, 3};
    bubble_sort(arr, 6);
    for (int i = 0; i < 6; i++) printf("%d ", arr[i]);
    printf("\\n");
    return 0;
}
`;

/// bubble_sort.c（corpus/baseline 逐字同源；真名 a ≠ 字幕展示名 arr）。
const BUBBLE_SORT_A = `// @category: baseline
int main() { int a[5] = {5,3,4,1,2}; for (int i = 0; i < 4; i++) for (int j = 0; j < 4-i; j++) if (a[j] > a[j+1]) { int t = a[j]; a[j] = a[j+1]; a[j+1] = t; } printf("%d", a[0]); return 0; }
`;

/// 同名快照语料（PR #530 审阅 P1-1）：全局 `arr` + 数组形参 `arr` 双发
/// （vm/observe 不去重）——plan 必须按 name 折叠后照常归属。
const SAME_NAME_C = "int arr[4] = {4,3,2,1}; void sort(int arr[], int n) { for (int i = 0; i < n - 1; i++) for (int j = 0; j < n - 1 - i; j++) if (arr[j] > arr[j + 1]) { int t = arr[j]; arr[j] = arr[j + 1]; arr[j + 1] = t; } } int main(void) { sort(arr, 4); return arr[0]; }";

/** 旧壳层 swapPair 的冻结副本（逐行照搬改造前 `cmd/mcp_js` PLAYER 函数）。 */
export function oldSwapPair(fr: MiniFrame, name: string): { i: number; j: number } | null {
  for (const ev of fr.e ?? []) {
    if (ev[0] !== 2) continue;
    const ctx = typeof ev[5] === "string" ? ev[5] : "";
    if (!contextMentionsArray(ctx, name)) continue;
    const x = Number(ev[2]);
    const y = Number(ev[3]);
    if (!Number.isInteger(x) || !Number.isInteger(y) || x < 0 || y < 0 || x === y) continue;
    const lo = Math.min(x, y);
    const hi = Math.max(x, y);
    const len = (fr.r?.[name] ?? []).length;
    if (hi >= len) continue;
    return { i: lo, j: hi };
  }
  return null;
}

/** 旧壳层 esc（字幕 HTML 转义）的冻结副本。 */
export function escHtml(s: string): string {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** 旧壳层 #cap innerHTML 公式的冻结副本（fr.s + 算法步 as + 根因 hint）。 */
export function oldCaption(fr: MiniFrame): string {
  let cap = fr.s || "";
  if (fr.a && fr.a.d) cap += ` <span class="as">\u2014 ${escHtml(fr.a.d)}</span>`;
  if (fr.h) cap += ` <span class="as" style="color:var(--err)">\u26a0 ${escHtml(fr.h.o ?? "")}</span>`;
  return cap;
}

/** 旧壳层 renderFrame 的显示数组选择（D.focus 真值优先，缺省全量键）。 */
export function displayedNames(data: VitroData, fr: MiniFrame): string[] {
  return data.focus || Object.keys(fr.r ?? {});
}

export interface FrameExpect {
  /** 旧规则点亮的 swap cell 数（每对 2 格）。 */
  swapCells: number;
  /** 旧规则点亮的 changed cell 数。 */
  changedCells: number;
  /** 旧规则归属的交换对（按显示数组序，最多一个/数组）。 */
  pairs: Array<{ name: string; i: number; j: number }>;
}

/** 逐帧重算旧规则路径的 stage 关键类名预期。 */
export function expectedOld(
  frames: MiniFrame[],
  k: number,
  focus: string[] | undefined,
): FrameExpect {
  const fr = frames[k] ?? {};
  const pv = k > 0 ? frames[k - 1] : undefined;
  const names = focus || Object.keys(fr.r ?? {});
  let swapCells = 0;
  let changedCells = 0;
  const pairs: Array<{ name: string; i: number; j: number }> = [];
  for (const nm of names) {
    const els = fr.r?.[nm] ?? [];
    if (!els.length) continue;
    const pels = pv?.r?.[nm] ?? [];
    const sp = oldSwapPair(fr, nm);
    if (sp !== null) pairs.push({ name: nm, i: sp.i, j: sp.j });
    for (let i2 = 0; i2 < els.length; i2++) {
      if (sp !== null && (i2 === sp.i || i2 === sp.j)) {
        swapCells += 1;
      } else if (pels.length && pels[i2] !== els[i2]) {
        changedCells += 1;
      }
    }
  }
  return { swapCells, changedCells, pairs };
}

export interface CaseStats {
  frames: number;
  oldSwapFrames: number;
  planSwapFrames: number;
  domSwapFrames: number;
  oldSwapCells: number;
  planSwapCells: number;
  domSwapCells: number;
  changedCells: number;
}

/** 单案例逐帧等价判定（纯函数：输入 = 产物数据 + DOM 探针）。 */
export function compareCase(
  data: VitroData,
  probes: FrameProbe[],
  realName: string,
): { mismatches: string[]; stats: CaseStats } {
  const mismatches: string[] = [];
  const frames = data.frames ?? [];
  const steps: TimelineStep[] = data.doc?.timeline?.steps ?? [];
  const planCheck = checkTimelinePlan(data, realName);
  for (const e of planCheck.errors) mismatches.push(`plan 不变量：${e}`);
  const stats: CaseStats = {
    frames: frames.length,
    oldSwapFrames: 0,
    planSwapFrames: 0,
    domSwapFrames: 0,
    oldSwapCells: 0,
    planSwapCells: 0,
    domSwapCells: 0,
    changedCells: 0,
  };
  if (probes.length !== frames.length) {
    mismatches.push(`DOM 探针数 ${probes.length} ≠ 帧数 ${frames.length}`);
  }
  for (let k = 0; k < Math.min(frames.length, probes.length); k++) {
    const fr = frames[k] ?? {};
    const probe = probes[k] ?? { swap: 0, changed: 0, cap: "" };
    const exp = expectedOld(frames, k, data.focus);
    const names = displayedNames(data, fr);
    const sw = steps[k]?.sw;
    const planApplicable = sw !== undefined && names.includes(sw.name) && (fr.r?.[sw.name] ?? []).length > 0;
    const planSwapCells = planApplicable ? 2 : 0;
    // ① stage 关键类名：旧规则 == plan 生效 == 真实 DOM
    if (exp.swapCells !== planSwapCells) {
      mismatches.push(`帧 ${k}: swap cells 旧规则=${exp.swapCells} plan=${planSwapCells}`);
    }
    if (exp.swapCells !== probe.swap) {
      mismatches.push(`帧 ${k}: swap cells 旧规则=${exp.swapCells} DOM=${probe.swap}`);
    }
    if (exp.changedCells !== probe.changed) {
      mismatches.push(`帧 ${k}: changed cells 旧规则=${exp.changedCells} DOM=${probe.changed}`);
    }
    // ② 交换对归属：旧规则点名的数组/下标 == plan.sw
    if (exp.pairs.length > 0) {
      if (exp.pairs.length > 1) {
        mismatches.push(`帧 ${k}: 旧规则多数组交换对 ${exp.pairs.length}（v0.1 单 sw 装不下）`);
      }
      const p0 = exp.pairs[0];
      if (p0 === undefined || sw === undefined || sw.name !== p0.name || sw.i !== p0.i || sw.j !== p0.j) {
        mismatches.push(
          `帧 ${k}: 交换归属 旧=${JSON.stringify(p0)} plan=${JSON.stringify(sw)}`,
        );
      }
    } else if (planApplicable) {
      mismatches.push(`帧 ${k}: plan sw 无旧规则来源 ${JSON.stringify(sw)}`);
    }
    // ③ 字幕文本：旧公式 == 真实 #cap；plan cap.t 与 semantic_label 同源
    const capOld = oldCaption(fr);
    if (capOld !== probe.cap) {
      mismatches.push(`帧 ${k}: 字幕 HTML 旧公式 ≠ DOM（${JSON.stringify(capOld.slice(0, 60))} vs ${JSON.stringify(probe.cap.slice(0, 60))}）`);
    }
    if ((sw !== undefined) !== (planSwapCells > 0)) {
      mismatches.push(`帧 ${k}: plan sw 未映射到显示数组（${String(sw?.name)} ∉ ${names.join(",")}）`);
    }
    if (exp.swapCells > 0) stats.oldSwapFrames += 1;
    if (planSwapCells > 0) stats.planSwapFrames += 1;
    if (probe.swap > 0) stats.domSwapFrames += 1;
    stats.oldSwapCells += exp.swapCells;
    stats.planSwapCells += planSwapCells;
    stats.domSwapCells += probe.swap;
    stats.changedCells += probe.changed;
  }
  return { mismatches, stats };
}

/** 产物脚本里替换 `window.__VITRO__=<json>` 的数据段（只替换第一个赋值；
 *  字符串/转义感知的括号扫描——JSON 内出现 `};` 不会截断）。 */
export function replaceVitroData(script: string, data: unknown): string {
  const prefix = "window.__VITRO__=";
  const at = script.indexOf(prefix);
  if (at < 0) throw new Error("replaceVitroData: 产物脚本无 window.__VITRO__= 赋值");
  const start = at + prefix.length;
  if (script[start] !== "{") throw new Error("replaceVitroData: 赋值不是 JSON 对象");
  let depth = 0;
  let inStr = false;
  let esc = false;
  let end = -1;
  for (let i = start; i < script.length; i++) {
    const ch = script[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === "{") depth += 1;
    else if (ch === "}") {
      depth -= 1;
      if (depth === 0) {
        end = i + 1;
        break;
      }
    }
  }
  if (end < 0) throw new Error("replaceVitroData: 数据 JSON 未闭合");
  return script.slice(0, start) + JSON.stringify(data) + script.slice(end);
}

export interface DivergencePlan {
  data: VitroData;
  on: number;
  off: number;
  onCap: string;
  offCap: string;
}

/** P2-1 人造分叉（PR #530 审阅）：把一帧顺手改成「有 sw+哨兵字幕」、另一帧
 *  sw 删掉——DOM 必须跟 plan 走；若壳层仍读 frames/旧规则，本锚必红。 */
export function mutatePlanForDivergence(data: VitroData, realName: string): DivergencePlan {
  const clone = JSON.parse(JSON.stringify(data)) as VitroData;
  const frames = clone.frames ?? [];
  const steps = clone.doc?.timeline?.steps;
  if (!Array.isArray(steps)) throw new Error("mutatePlanForDivergence: 缺 doc.timeline.steps");
  let on = -1;
  let off = -1;
  for (let k = 0; k < frames.length; k++) {
    const len = (frames[k]?.r?.[realName] ?? []).length;
    const sw = steps[k]?.sw;
    if (off < 0 && sw !== undefined && sw.name === realName) off = k;
    if (on < 0 && sw === undefined && len >= 2) on = k;
  }
  if (on < 0 || off < 0) throw new Error("mutatePlanForDivergence: 找不到可注入/可移除帧");
  const onCap = "MUT-PLAN-ON";
  const offCap = "MUT-PLAN-OFF";
  steps[on] = { sw: { name: realName, i: 0, j: 1 }, cap: { t: onCap, w: 2, dur: 1 } };
  const offStep = steps[off] ?? {};
  delete offStep.sw;
  offStep.cap = { t: offCap, w: 1, dur: 0 };
  steps[off] = offStep;
  return { data: clone, on, off, onCap, offCap };
}

interface FrameOut {
  id?: number | null;
  result?: unknown;
}

async function drive(): Promise<number> {
  const product = process.env.VITRO_MCP_JS ?? "moonbit/_build/js/release/build/cmd/mcp_js/mcp_js.js";
  if (!existsSync(product)) {
    console.error(`timeline_equiv: 产物不存在 ${product}——前置 moon build --release --target js cmd/mcp_js`);
    return 2;
  }
  const outDir = mkdtempSync(path.join(tmpdir(), "tl-equiv-"));
  const srv = spawn(process.execPath, [product], { stdio: ["pipe", "pipe", "pipe"] });
  srv.stderr.on("data", () => {});
  const acc = makeLineAcc();
  const results = new Map<number, FrameOut>();
  srv.stdout.on("data", (d: Buffer) => {
    for (const line of acc.feed(d.toString("utf8"))) {
      const f = JSON.parse(line) as FrameOut;
      if (f.id !== undefined && f.id !== null) results.set(f.id, f);
    }
  });
  let seq = 0;
  const send = (method: string, params?: Record<string, unknown>): number => {
    const id = ++seq;
    void srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, ...(params === undefined ? {} : { params }) }) + "\n");
    return id;
  };
  const wait = (id: number, ms = 90_000): Promise<FrameOut> =>
    new Promise((resolve, reject) => {
      const t0 = Date.now();
      const iv = setInterval(() => {
        const got = results.get(id);
        if (got !== undefined) { clearInterval(iv); resolve(got); }
        else if (Date.now() - t0 > ms) { clearInterval(iv); reject(new Error(`timeout id=${id}`)); }
      }, 25);
    });
  const call = async (name: string, args: Record<string, unknown>): Promise<{ text: string }> =>
    wait(send("tools/call", { name, arguments: args })).then((frame) => toolTextOf(frame));

  const chk = new CheckRun();
  try {
    void await wait(send("initialize", { protocolVersion: "2025-03-05" }));
    srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    const cases: Array<[string, string, Record<string, unknown>, string, number, boolean]> = [
      ["bubble（真名=展示名 arr）", BUBBLE_C, { budget: 300 }, "arr", 3, true],
      ["bubble_sort（真名 a ≠ 展示名 arr）", BUBBLE_SORT_A, {}, "a", 54, false],
      ["same-name（全局 arr + 形参 arr 双快照）", SAME_NAME_C, {}, "arr", 37, false],
    ];
    for (const [label, source, extra, realName, expectSwFrames, divergence] of cases) {
      const r = JSON.parse((await call("animate", { source, preview_png: false, out_dir: outDir, ...extra })).text) as {
        ok: boolean;
        html_path: string;
      };
      chk.check(`${label}: animate 产物落盘`, r.ok === true, r.html_path ?? "");
      const d = driveScript(extractScript(readFileSync(r.html_path, "utf8")));
      const { mismatches, stats } = compareCase(d.data as VitroData, d.probes, realName);
      const detail =
        `frames=${stats.frames} swapFrames 旧=${stats.oldSwapFrames}/plan=${stats.planSwapFrames}/DOM=${stats.domSwapFrames} ` +
        `swapCells 旧=${stats.oldSwapCells}/plan=${stats.planSwapCells}/DOM=${stats.domSwapCells} changed=${stats.changedCells}`;
      chk.check(`${label}: 逐帧等价（交换帧集合/字幕/stage 类名）`, mismatches.length === 0,
        mismatches.length === 0 ? detail : `${detail}；${mismatches.slice(0, 5).join(" | ")}`);
      chk.check(`${label}: 交换帧集合锚 ${expectSwFrames}`, stats.domSwapFrames === expectSwFrames && stats.oldSwapFrames === expectSwFrames,
        `旧=${stats.oldSwapFrames} DOM=${stats.domSwapFrames}`);
      if (mismatches.length === 0) console.log(`timeline_equiv: ${label} OK——${detail}`);
      if (divergence) {
        // 人造分叉：plan 与 frames 故意不一致 → DOM 必须跟 plan 走。
        // 若壳层静默回退旧规则（如 LIVE 反写成 true），本锚必红。
        const mut = mutatePlanForDivergence(d.data as VitroData, realName);
        const mutScript = replaceVitroData(extractScript(readFileSync(r.html_path, "utf8")), mut.data);
        const mdrv = driveScript(mutScript);
        const onP = mdrv.probes[mut.on];
        const offP = mdrv.probes[mut.off];
        chk.check(
          `${label}: 人造分叉——DOM 跟 plan 走（静态路径真消费）`,
          onP !== undefined && offP !== undefined &&
            onP.swap === 2 && onP.cap.startsWith(mut.onCap) &&
            offP.swap === 0 && offP.cap.startsWith(mut.offCap),
          `on 帧 ${mut.on}: swap=${onP?.swap} cap=${JSON.stringify(onP?.cap.slice(0, 32))}; off 帧 ${mut.off}: swap=${offP?.swap} cap=${JSON.stringify(offP?.cap.slice(0, 32))}`,
        );
      }
    }
  } catch (e) {
    chk.check("驱动异常（超时/畸形帧）", false, e instanceof Error ? e.message : String(e));
    srv.kill();
  } finally {
    rmSync(outDir, { recursive: true, force: true });
  }
  if (chk.failures.length === 0) {
    console.log(`timeline_equiv: PASS——${chk.total} 项断言全绿`);
    return 0;
  }
  console.error(`timeline_equiv: FAIL——${chk.failures.length}/${chk.total} 项红：`);
  for (const f of chk.failures) console.error(`  ✗ ${f}`);
  return 1;
}

if (process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  void drive().then((rc) => { process.exit(rc); });
}
