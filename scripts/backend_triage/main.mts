#!/usr/bin/env node
// backend_triage —— #349 三面编译语义对拍臂驱动（判定型闸）。
//
// 同一份 MoonBit 源（moonbit/cmd/backend_triage runner）在三个编译后端
// 下执行，stdout 逐字节比对 + rc=0 + **形状门量**（PR #367 审阅 P2-1：
// 空输出/缺行恒绿突变实锤后补——恰好 10 行、ping 帧、版本行、compile+run
// 帧全须在位）：
//
//   native   moon run --target native   （MOON_CC=clang——AGENTS 纪律 11）
//   js       moon run --target js       （node）
//   wasm-gc  moon run --target wasm-gc  （moonrun——moon 工具链自带）
//
// 任两臂输出分叉 ⇒ 直接归因编译后端（现役 js/wasm 两臂同宿主 node，
// 宿主层 bug 两臂同报不可分——本臂 wasm 侧走 moonrun 宿主异构）。
//
// 口径（PR #367 审阅 P3-2/P3-3）：**字节域**——spawnSync encoding
// "buffer"、逐字节比对、长度/偏移均按字节计（纪律 8：偏移/长度类字段
// 一律字节口径，UTF-16 code unit 不入报告）。**CRLF 归一仅对 native 臂
// 且显式介入**：Windows native 的 println 走 CRT 文本模式（\n→\r\n，
// #315 同族；runner 是防线件无 stdout stub）——js/wasm 臂的 CRLF 是真
// 红（不经归一），native 归一介入在 ok 行显式标注（Linux CI 上恒不
// 介入）。
//
// 新增不替换（#349 落地形态）：现役 gates-wasm 各 slice 不动。
//
// J9 证红留痕：compareTriad/validateShape 的红态锚在 main.test.mts
//（空输出/缺行/内容差/长度差/rc 差/臂数破损/js 臂 CRLF）。
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** 三臂输出（驱动内部流转 + 测试注入判定的载体；out = 原始字节）。 */
export interface ArmResult {
  label: string;
  out: Buffer;
  rc: number;
}

/** 比对判定结果：ok=false 时 msg 指首个分歧面。 */
export interface TriadVerdict {
  ok: boolean;
  msg: string;
}

/** runner 期望行数（cmd/backend_triage/main.mbt 的 println 计数——形状门量）。 */
export const EXPECTED_LINES = 10;

/** CRLF→LF 归一（字节域：仅剥 0d 0a 对中的 0d）。 */
export function normalizeCrlf(b: Buffer): Buffer {
  const out = Buffer.alloc(b.length);
  let n = 0;
  for (let i = 0; i < b.length; i++) {
    if (b[i] === 0x0d && i + 1 < b.length && b[i + 1] === 0x0a) continue;
    out[n++] = b[i] ?? 0;
  }
  return out.subarray(0, n);
}

/**
 * 形状门量（PR #367 审阅 P2-1）：恰好 EXPECTED_LINES 行 + 关键帧在位。
 * 空输出/静默突变（ignore 化）在此即红——比对之前先过形状。
 */
export function validateShape(out: Buffer): string | null {
  const text = out.toString("utf8");
  const lines = text.split("\n").filter((l) => l.length > 0);
  if (lines.length !== EXPECTED_LINES) {
    return `行数 ${lines.length} ≠ ${EXPECTED_LINES}（空输出/缺行/多行——runner 静默或输出面变更未连坐驱动）`;
  }
  if (!lines[0]?.includes('"pong":true')) {
    return `首行缺 ping 帧断言：${JSON.stringify(lines[0]?.slice(0, 80) ?? "")}`;
  }
  if (!lines[2]?.startsWith("v")) {
    return `第 3 行非协议版本形态（应 v 前缀）：${JSON.stringify(lines[2] ?? "")}`;
  }
  if (!/^\d+\.\d+\.\d+$/.test(lines[3] ?? "")) {
    return `第 4 行非语义版本（x.y.z）：${JSON.stringify(lines[3] ?? "")}`;
  }
  if (!lines[8]?.includes('"ok":true')) {
    return `第 9 行 compile 帧非 ok:true：${JSON.stringify((lines[8] ?? "").slice(0, 80))}`;
  }
  if (!lines[9]?.includes('"return_value":7')) {
    return `第 10 行 run 帧非 return_value:7：${JSON.stringify((lines[9] ?? "").slice(0, 80))}`;
  }
  return null;
}

/**
 * 三面比对（纯函数——驱动主流程与 node:test 共用）：
 *   ① 三臂 rc 全 0；② 各臂形状门量；③ 三臂 stdout 逐字节一致
 *   （native 臂 CRLF 归一可介入且标注；js/wasm 臂零归一）。
 */
export function compareTriad(arms: readonly ArmResult[]): TriadVerdict {
  if (arms.length !== 3) {
    return { ok: false, msg: `臂数=${arms.length}（应为 3——驱动装配破损）` };
  }
  const [a, b, c] = arms as [ArmResult, ArmResult, ArmResult];
  const norm = (r: ArmResult): Buffer => (r.label === "native" ? normalizeCrlf(r.out) : r.out);
  for (const r of arms) {
    if (r.rc !== 0) {
      return { ok: false, msg: `${r.label} 臂 rc=${r.rc}（应为 0——runner 编译/执行失败，先看 stderr）` };
    }
    const shapeErr = validateShape(norm(r));
    if (shapeErr !== null) {
      return { ok: false, msg: `${r.label} 臂形状门量：${shapeErr}` };
    }
  }
  const na = norm(a);
  const nb = norm(b);
  const nc = norm(c);
  const crlfUsed = !na.equals(a.out) || !nb.equals(b.out) || !nc.equals(c.out);
  if (!na.equals(nb)) {
    return { ok: false, msg: firstDiffMsg(a.label, na, b.label, nb) };
  }
  if (!nb.equals(nc)) {
    return { ok: false, msg: firstDiffMsg(b.label, nb, c.label, nc) };
  }
  const note = crlfUsed ? "，native CRT 行尾归一介入〔Windows 本地形态，Linux CI 恒等〕" : "";
  return { ok: true, msg: `三臂逐字节一致（${na.length}B${note}）` };
}

/** 首个字节差异定位（等长与不等长统一：min 长度内找，越界即长度差）。 */
function firstDiffMsg(lx: string, x: Buffer, ly: string, y: Buffer): string {
  const n = Math.min(x.length, y.length);
  for (let i = 0; i < n; i++) {
    if (x[i] !== y[i]) {
      return `${lx} vs ${ly}: 首差 offset=${i}（0x${(x[i] ?? 0).toString(16)} vs 0x${(y[i] ?? 0).toString(16)}）`;
    }
  }
  return `${lx} vs ${ly}: 长度差 ${x.length}B vs ${y.length}B（前 ${n}B 一致——单侧尾部增删）`;
}

/** moon run 单臂执行（cwd=moonbit/；MOON_CC=clang 按臂注入；字节域捕获）。 */
function runArm(target: string, moonbitDir: string): ArmResult {
  const env = { ...process.env };
  // moon run --target js 内部起 node：显式用本进程的 node，防 PATH 抖动
  const nodeDir = path.dirname(process.execPath);
  env.PATH = `${nodeDir}${path.delimiter}${env.PATH ?? ""}`;
  if (target === "native") {
    env.MOON_CC = "clang";
  }
  const r = spawnSync("moon", ["run", "--target", target, "cmd/backend_triage"], {
    cwd: moonbitDir,
    env,
    maxBuffer: 64 * 1024 * 1024,
    encoding: "buffer",
  });
  if (r.error !== undefined) {
    return { label: target, out: Buffer.alloc(0), rc: -1 };
  }
  if (r.stderr !== undefined && r.stderr.length > 0 && process.env.BACKEND_TRIAGE_VERBOSE === "1") {
    process.stdout.write(`[${target} stderr] ${r.stderr.toString("utf8").slice(0, 2000)}\n`);
  }
  return { label: target, out: r.stdout ?? Buffer.alloc(0), rc: r.status ?? -1 };
}

function main(): number {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const moonbitDir = path.resolve(here, "..", "..", "moonbit");
  const arms: ArmResult[] = [
    runArm("native", moonbitDir),
    runArm("js", moonbitDir),
    runArm("wasm-gc", moonbitDir),
  ];
  const verdict = compareTriad(arms);
  if (!verdict.ok) {
    process.stdout.write(`FAIL: backend_triage ${verdict.msg}\n`);
    for (const a of arms) {
      process.stdout.write(`--- ${a.label} (rc=${a.rc}, ${a.out.length}B) 首 200B: ${JSON.stringify(a.out.toString("utf8", 0, 200))}\n`);
    }
    return 1;
  }
  process.stdout.write(`ok  backend_triage ${verdict.msg}（native-clang / js-node / wasm-gc-moonrun，#349）\n`);
  return 0;
}

if (process.argv[1] !== undefined && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main());
}
