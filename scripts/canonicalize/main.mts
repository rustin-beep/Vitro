#!/usr/bin/env node
// canonicalize：差分锚的 JSON 归一器 CLI（#273 存量 Go 重写批）。
//
// 归一规则与实现单源在 scripts/internal/canonicalize.mts——本文件只是 CLI 壳：
// stdin 进 stdout 出，--check 为锚定模式（输入已是规范形则 exit 0）。
//
// 契约（与 Go 壳逐条对齐）：
//   - 归一路径：规范形写 stdout、stderr 静默、exit 0；非法 JSON exit 1 且零 stdout；
//   - --check：规范形 exit 0；键序/缩进/转义不符 exit 1；首尾空白容忍；
//   - 参数解析错 exit 2；-h/--help exit 0。
//
// 用法：
//   node scripts/canonicalize/main.mts < in.json
//   node scripts/canonicalize/main.mts --check < in.json
import fs from "node:fs";
import { pathToFileURL } from "node:url";
import { canonicalize } from "../internal/canonicalize.mts";

export interface RunResult {
  code: number;
  out: string;
  err: string;
}

const USAGE = "用法: canonicalize [-check] < in.json\n";

export function run(args: string[], stdin: Uint8Array): RunResult {
  let check = false;
  for (const a of args) {
    if (a === "-check" || a === "--check") {
      check = true;
      continue;
    }
    if (a === "-h" || a === "--help") return { code: 0, out: "", err: USAGE };
    return { code: 2, out: "", err: `canonicalize: 未知参数 ${a}\n` };
  }

  const raw = Buffer.from(stdin);
  let canonical: Buffer;
  try {
    canonical = canonicalize(raw);
  } catch (e) {
    return {
      code: 1,
      out: "",
      err: `canonicalize: JSON 归一失败（拒绝输出，不猜不兜底）: ${e instanceof Error ? e.message : String(e)}\n`,
    };
  }

  if (check) {
    // 首尾空白容忍（判定面只有键序/缩进/转义三项——Go 壳实测口径）
    if (raw.toString("utf8").trim() !== canonical.toString("utf8").trim()) {
      return { code: 1, out: "", err: "输入不是规范形（键序/缩进/转义之一不匹配；首尾空白容忍）\n" };
    }
    return { code: 0, out: "", err: "" };
  }
  return { code: 0, out: canonical.toString("utf8"), err: "" };
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(process.argv[1]).href === import.meta.url;
if (invokedDirectly) {
  const r = run(process.argv.slice(2), fs.readFileSync(0));
  if (r.err !== "") process.stderr.write(r.err);
  if (r.out !== "") process.stdout.write(r.out);
  // Windows 管道 + 立即 process.exit() 会触发 libuv async 断言（实测 127）；
  // 置 exitCode 让 stdio 自然排空。
  process.exitCode = r.code;
}
