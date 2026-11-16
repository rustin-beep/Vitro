#!/usr/bin/env node
// timeline_wasm_anchor —— TimelinePlan v0.2 的 wasm 臂内容锚（#470 批四收尾；
// PR #530 审阅「wasm 臂 plan 内容未深度审阅」建议项）。
//
// 目的：plan 内容此前只在 js 臂产物（mcp_smoke）与 gateway js-target 白盒被
// 验证；wasm-gc 产物是浏览器交付同源面。本闸用 Node 宿主（scripts/wasm_load.mts）
// 实例化 wasm gateway，走 step 流后调 timeline.plan，断言 v0.2 内容不变量：
//   pv=2 / steps==payloads / sw 真名且界内 / ch 与 payload 差分一致 /
//   bar 长度与 [0,1] 域（char 不产）/ cam 首帧恒有 + 栈变帧 / enter 值域。
//
// 前置：cd moonbit && moon build --release --target wasm-gc gateway/wasm
// 用法：node scripts/moonbit/timeline_wasm_anchor/main.mts [--wasm <path>]
// 自报：timeline_wasm 锚: N (PASS x / FAIL y)
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { instantiateGateway, type GatewayExports } from "../../wasm_load.mts";

type Json = any;

/// bubble_sort 单行语料（corpus/baseline 同源——与 mcp_smoke/timeline_equiv
/// 同一真名 a ≠ 展示名 arr 的分叉面；80 批 step.next 内确定性覆盖多次交换）。
const SRC =
  'int main() { int a[5] = {5,3,4,1,2}; for (int i = 0; i < 4; i++) for (int j = 0; j < 4-i; j++) if (a[j] > a[j+1]) { int t = a[j]; a[j] = a[j+1]; a[j+1] = t; } printf("%d", a[0]); return 0; }';

export interface AnchorCounts {
  frames: number;
  swFrames: number;
  chFrames: number;
  barFrames: number;
  camFrames: number;
  enterFrames: number;
}

interface SnapInfo {
  els: string[];
  ty: string;
}

/** payload 的数组快照表（同名后写覆盖——与引擎最小视图同口径）。 */
function snapsOf(p: Json): Map<string, SnapInfo> {
  const m = new Map<string, SnapInfo>();
  for (const s of p.array_snapshots ?? []) {
    m.set(String(s.name ?? ""), { els: (s.elements ?? []).map((x: unknown) => String(x)), ty: String(s.element_ty ?? "?") });
  }
  return m;
}

function stackOf(p: Json): string[] {
  return (p.call_stack ?? []).map((f: Json) => String(f.func_name ?? ""));
}

function numList(v: unknown): number[] | null {
  if (!Array.isArray(v)) return null;
  const out: number[] = [];
  for (const x of v) {
    if (typeof x !== "number" || !Number.isFinite(x)) return null;
    out.push(x);
  }
  return out;
}

/** plan 内容不变量（纯函数，判定器单测自证）：返回错误清单 + 计数。 */
export function checkPlanContent(
  plan: Json,
  payloads: Json[],
): { errors: string[]; counts: AnchorCounts } {
  const errors: string[] = [];
  const counts: AnchorCounts = { frames: payloads.length, swFrames: 0, chFrames: 0, barFrames: 0, camFrames: 0, enterFrames: 0 };
  if (plan?.pv !== 2) errors.push(`pv 非 2（${String(plan?.pv)}）`);
  const steps = plan?.steps;
  if (!Array.isArray(steps)) return { errors: [...errors, "steps 缺失"], counts };
  if (steps.length !== payloads.length) errors.push(`steps=${steps.length} ≠ payloads=${payloads.length}（错位）`);
  for (let k = 0; k < Math.min(steps.length, payloads.length); k += 1) {
    const p = payloads[k] ?? {};
    const prev = k > 0 ? (payloads[k - 1] ?? {}) : undefined;
    const st = steps[k] ?? {};
    const snaps = snapsOf(p);
    const prevSnaps = prev === undefined ? undefined : snapsOf(prev);
    // sw：真名 + 界内
    if (st.sw !== undefined) {
      counts.swFrames += 1;
      const info = snaps.get(String(st.sw.name));
      if (info === undefined) errors.push(`帧 ${k}: sw.name=${String(st.sw.name)} 不在快照名集`);
      else if (!(Number.isInteger(st.sw.i) && Number.isInteger(st.sw.j) && st.sw.i >= 0 && st.sw.i < st.sw.j && st.sw.j < info.els.length)) {
        errors.push(`帧 ${k}: sw 下标非法 ${String(st.sw.i)}/${String(st.sw.j)}`);
      }
    }
    // ch：与 payload 逐元素差分一致（全量快照——wasm 面不经 focus 过滤）
    const ch = st.ch;
    if (ch !== undefined) counts.chFrames += 1;
    for (const [name, info] of snaps) {
      const expected: number[] = [];
      const ps = prevSnaps?.get(name);
      if (ps !== undefined && ps.els.length === info.els.length) {
        for (let i = 0; i < info.els.length; i += 1) if (info.els[i] !== ps.els[i]) expected.push(i);
      }
      const actual = ch?.[name] ?? [];
      if (JSON.stringify(expected) !== JSON.stringify(actual)) {
        errors.push(`帧 ${k}: ch[${name}] 期望 ${JSON.stringify(expected)} 实得 ${JSON.stringify(actual)}`);
      }
    }
    // bar：数值非 char 数组逐元素比例；char/非数值不产
    const bar = st.bar;
    if (bar !== undefined) counts.barFrames += 1;
    for (const [name, info] of snaps) {
      const vals = info.els.map(Number);
      const numeric = info.ty !== "char" && info.els.length > 0 && vals.every((v) => Number.isFinite(v));
      const ratios = bar?.[name];
      if (!numeric) {
        if (ratios !== undefined) errors.push(`帧 ${k}: 非数值/char 数组 ${name} 仍产 bar`);
        continue;
      }
      const list = numList(ratios);
      if (list === null) {
        errors.push(`帧 ${k}: 数值数组 ${name} 缺 bar 或形态非法`);
        continue;
      }
      if (list.length !== vals.length) {
        errors.push(`帧 ${k}: bar[${name}] 长度 ${list.length} ≠ ${vals.length}`);
        continue;
      }
      const mx = Math.max(1, ...vals.map((v) => Math.abs(v)));
      for (let i = 0; i < vals.length; i += 1) {
        const want = Math.abs(vals[i] ?? 0) / mx;
        if (!(list[i] !== undefined && list[i]! >= 0 && list[i]! <= 1 && Math.abs(list[i]! - want) <= 1e-9)) {
          errors.push(`帧 ${k}: bar[${name}][${i}] ${String(list[i])} ≠ ${want}`);
          break;
        }
      }
    }
    // cam：首帧恒有；栈顶/深度变化帧必须有；不变帧不得有
    const stack = stackOf(p);
    const top = stack[stack.length - 1] ?? "";
    const pstack = prev === undefined ? [] : stackOf(prev);
    const ptop = pstack[pstack.length - 1] ?? "";
    const changed = prev !== undefined && (top !== ptop || stack.length !== pstack.length);
    if (st.cam !== undefined) counts.camFrames += 1;
    if (prev === undefined || changed) {
      if (st.cam === undefined) errors.push(`帧 ${k}: 首帧/栈变帧缺 cam`);
      else if (st.cam.fit !== "calltree" || st.cam.func !== top || st.cam.depth !== stack.length) {
        errors.push(`帧 ${k}: cam 不符 ${JSON.stringify(st.cam)}`);
      }
    } else if (st.cam !== undefined) {
      errors.push(`帧 ${k}: 栈不变仍产 cam`);
    }
    // enter：值域
    if (st.enter !== undefined) {
      counts.enterFrames += 1;
      if (!/^(func:|diag:)/.test(String(st.enter))) errors.push(`帧 ${k}: enter 值域非法 ${String(st.enter)}`);
    }
  }
  return { errors, counts };
}

/** wasm 产物定位（--wasm 显式 > release > debug）；缺产物 fail loud（rc 2）。 */
export function locateWasm(argv: string[], repoRoot: string): string {
  const at = argv.indexOf("--wasm");
  if (at >= 0 && argv[at + 1] !== undefined) return argv[at + 1] as string;
  const release = path.join(repoRoot, "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm");
  const debug = path.join(repoRoot, "moonbit/_build/wasm-gc/debug/build/gateway/wasm/wasm.wasm");
  return fs.existsSync(release) ? release : debug;
}

async function drive(): Promise<number> {
  const repoRoot = path.resolve(import.meta.dirname, "../../..");
  const wasmPath = locateWasm(process.argv.slice(2), repoRoot);
  if (!fs.existsSync(wasmPath)) {
    console.error(`timeline_wasm_anchor: 找不到产物 ${wasmPath}——先 cd moonbit && moon build --release --target wasm-gc gateway/wasm`);
    return 2;
  }
  const buf = fs.readFileSync(wasmPath);
  const inst = await instantiateGateway(buf);
  const g = inst.exports as unknown as GatewayExports;
  const invoke = (line: string): Json => JSON.parse(g.invoke(line));

  let pass = 0;
  let fail = 0;
  const failures: string[] = [];
  const check = (cond: boolean, label: string, detail = ""): void => {
    if (cond) {
      pass += 1;
      console.log(`  PASS  ${label}`);
    } else {
      fail += 1;
      failures.push(label);
      console.log(`  FAIL  ${label}  ${detail}`);
    }
  };

  const comp = invoke(`{"id":1,"method":"compile","params":{"source":${JSON.stringify(SRC)}}}`);
  check(comp.ok === true && comp.result?.ok === true, "wasm 臂 compile 成功", JSON.stringify(comp).slice(0, 160));
  const run = invoke(`{"id":2,"method":"run"}`);
  check(run.result?.status === "finished", "wasm 臂 run finished", JSON.stringify(run).slice(0, 120));
  invoke(`{"id":3,"method":"step.begin"}`);
  for (let i = 0; i < 80; i += 1) invoke(`{"id":10,"method":"step.next"}`);
  const pg = invoke(`{"id":20,"method":"payload.get","params":{"start":0}}`);
  const tp = invoke(`{"id":21,"method":"timeline.plan","params":{"start":0}}`);
  check(tp.ok === true, "timeline.plan 成功帧（wasm 臂）", JSON.stringify(tp).slice(0, 160));
  const payloads: Json[] = Array.isArray(pg.result?.payloads) ? pg.result.payloads : [];
  check(payloads.length > 0, "payload 窗非空", `n=${payloads.length}`);
  const { errors, counts } = checkPlanContent(tp.result, payloads);
  check(counts.frames === payloads.length && counts.frames > 0, "steps==payloads（内容锚口径）", `${counts.frames}/${payloads.length}`);
  check(errors.length === 0, "v0.2 内容不变量（sw/ch/bar/cam/enter）", errors.slice(0, 4).join(" | "));
  check(
    counts.swFrames > 0 && counts.chFrames > 0 && counts.barFrames > 0 && counts.camFrames >= 1,
    "非空转（sw/ch/bar/cam 均在窗口内出现）",
    JSON.stringify(counts),
  );
  console.log(
    `timeline_wasm 锚: ${pass + fail} (PASS ${pass} / FAIL ${fail}) — frames=${counts.frames} sw=${counts.swFrames} ch=${counts.chFrames} bar=${counts.barFrames} cam=${counts.camFrames} enter=${counts.enterFrames}`,
  );
  if (fail > 0) {
    console.error(`timeline_wasm_anchor: FAIL——${fail} 项红：`);
    for (const f of failures) console.error(`  ✗ ${f}`);
    return 1;
  }
  return 0;
}

if (process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  void drive().then((rc) => process.exit(rc));
}
