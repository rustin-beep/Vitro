#!/usr/bin/env node
// backend_triage —— #349 三面编译语义对拍臂驱动（判定型闸）。
//
// 同一份 MoonBit 源（moonbit/cmd/backend_triage runner——gateway 四导出
// 帧的源级形态：ping / 非法 JSON 错误帧 / protocol_version /
// engine_version，全确定性输出）在三个编译后端下执行，stdout 逐字节
// 比对 + rc=0：
//
//   native   moon run --target native   （MOON_CC=clang——AGENTS 纪律 11）
//   js       moon run --target js       （node）
//   wasm-gc  moon run --target wasm-gc  （moonrun——moon 工具链自带）
//
// 任两臂输出分叉 ⇒ 直接归因编译后端（现役 js/wasm 两臂同宿主 node，
// 宿主层 bug 两臂同报不可分——本臂 wasm 侧走 moonrun 宿主异构）。
// 断言口径与 vitro_cli_smoke 多臂对拍同款（逐字节一致，零归一）。
//
// 新增不替换（#349 落地形态）：现役 gates-wasm 各 slice 不动。
//
// J9 证红留痕（2026-10-28 本地）：compareTriad 对「js 臂丢一行」注入
// 分叉即红（main.test.mts 三态锚）。
//
// 前置：moon 在 PATH（含 moonrun）；node 由本进程自身承担（moon run
// --target js 内部调 node——用 process.execPath 注入 PATH 兜底，防
// CI runner 的 node 与 moon 子进程 PATH 不一致）。
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** 三臂输出（驱动内部流转 + 测试注入判定的载体）。 */
export interface ArmResult {
  label: string;
  out: string;
  rc: number;
}

/** compareTriad 判定结果：ok=false 时 msg 指首个分歧面。 */
export interface TriadVerdict {
  ok: boolean;
  msg: string;
}

/**
 * CRLF→LF 归一（比对前置）：Windows native 臂的 println 走 CRT 文本模式
 * （\n→\r\n——#315 同族形态；runner 是防线件无 stdout stub，不在 CLI 壳
 * 治本面）。Linux CI 上本归一是恒等变换（零损失）；归一后内容仍逐字节
 * 比对——仅剥 \r，不动其它任何字节。
 */
export function normalizeLineEndings(s: string): string {
  return s.split("\r\n").join("\n");
}

/**
 * 三面比对（纯函数——驱动主流程与 node:test 共用）：
 *   ① 三臂 rc 全 0；② 三臂 stdout（行尾归一后）逐字节一致。
 * 任一不满足即红，msg 指首个分歧（rc 优先——崩了比输出差更上游）。
 */
export function compareTriad(arms: readonly ArmResult[]): TriadVerdict {
  if (arms.length !== 3) {
    return { ok: false, msg: `臂数=${arms.length}（应为 3——驱动装配破损）` };
  }
  const [a = { label: "?", out: "", rc: -1 }, b = { label: "?", out: "", rc: -1 }, c = { label: "?", out: "", rc: -1 }] = arms;
  for (const r of arms) {
    if (r.rc !== 0) {
      return { ok: false, msg: `${r.label} 臂 rc=${r.rc}（应为 0——runner 编译/执行失败，先看 stderr）` };
    }
  }
  const na = normalizeLineEndings(a.out);
  const nb = normalizeLineEndings(b.out);
  const nc = normalizeLineEndings(c.out);
  if (na !== nb) {
    return { ok: false, msg: firstDiffMsg(a.label, na, b.label, nb) };
  }
  if (nb !== nc) {
    return { ok: false, msg: firstDiffMsg(b.label, nb, c.label, nc) };
  }
  return { ok: true, msg: `三臂逐字节一致（行尾归一后 ${na.length}B）` };
}

/** 首个字节差异定位（等长与不等长统一：min 长度内找，越界即长度差）。 */
function firstDiffMsg(lx: string, x: string, ly: string, y: string): string {
  const n = Math.min(x.length, y.length);
  for (let i = 0; i < n; i++) {
    if (x[i] !== y[i]) {
      return `${lx} vs ${ly}: 首差 offset=${i}（${showAt(x, i)} vs ${showAt(y, i)}）`;
    }
  }
  return `${lx} vs ${ly}: 长度差 ${x.length}B vs ${y.length}B（前 ${n}B 一致——单侧尾部增删）`;
}

function showAt(s: string, i: number): string {
  return JSON.stringify(s.slice(Math.max(0, i - 12), i + 12));
}

/** moon run 单臂执行（cwd=moonbit/；MOON_CC=clang 按臂注入）。 */
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
    encoding: "utf8",
  });
  if (r.error !== undefined) {
    return { label: target, out: "", rc: -1 };
  }
  if (r.stderr !== undefined && r.stderr.length > 0 && process.env.BACKEND_TRIAGE_VERBOSE === "1") {
    process.stdout.write(`[${target} stderr] ${r.stderr.slice(0, 2000)}\n`);
  }
  return { label: target, out: r.stdout ?? "", rc: r.status ?? -1 };
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
      process.stdout.write(`--- ${a.label} (rc=${a.rc}, ${a.out.length}B) 首 200B: ${JSON.stringify(a.out.slice(0, 200))}\n`);
    }
    return 1;
  }
  process.stdout.write(`ok  backend_triage ${verdict.msg}（native-clang / js-node / wasm-gc-moonrun，#349）\n`);
  return 0;
}

if (process.argv[1] !== undefined && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main());
}
