#!/usr/bin/env node
// source_hygiene：源码卫生扫描（① NUL 字节 / i/-text 事故族；② 包外散 .mbt——
// #273 存量 Go 重写批；② 为 2026-11-01 审阅 v2 S13b-P10 新增）。
//
// 用法（仓库根）：
//   node scripts/moonbit/source_hygiene/main.mts          # 扫描并列出命中
//   node scripts/moonbit/source_hygiene/main.mts -check   # 同（与兄弟闸调用形态一致）
//
// ① 事故族：含真 NUL 的文件被 git 判二进制（w/-text）⇒ .gitattributes 的
// text eol=lf 失效 + diff/PR 审阅不可见。扫描集 = git 跟踪的全部文件
// （fail-safe：新文件类型自动进闸）；确需入库含 NUL 的产物在
// scripts/moonbit/source_hygiene_allowlist.txt 显式登记。
// ② 包外散 .mbt：git 跟踪的 moonbit/**/*.mbt 从所在目录向上找 moon.pkg（moon
// 的包发现以包为单位），走到 moon.mod（workspace 根）仍未遇到即红——包外文件
// 对 moon fmt 全量形态不可见（pre-commit 钩子与 CI hygiene 的 fmt 闸同机制同
// 盲；AGENTS 13.5 此前只有人肉纪律，探针 E 实锤烂格式包外 .mbt 全链零检出，
// 无人 import 即静默裸奔入库）。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../../internal/capi.mts";

export interface NulHit {
  offset: number;
  count: number;
}

export function findNul(data: Buffer): NulHit | null {
  const offset = data.indexOf(0);
  if (offset < 0) return null;
  let count = 0;
  for (let i = offset; i < data.length; i++) if (data[i] === 0) count++;
  return { offset, count };
}

export function readAllowlist(root: string): Set<string> {
  const allow = new Set<string>();
  const p = path.join(root, "scripts/moonbit/source_hygiene_allowlist.txt");
  if (!fs.existsSync(p)) return allow;
  for (const raw of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const line = raw.trim();
    if (line !== "" && !line.startsWith("#")) allow.add(line);
  }
  return allow;
}

export function listTracked(root: string): string[] {
  const r = spawnSync("git", ["ls-files", "-z"], { cwd: root });
  if (r.status !== 0) fatal("git ls-files 失败（须在 git 仓库内运行）");
  const raw = r.stdout;
  const out: string[] = [];
  let start = 0;
  for (let i = 0; i < raw.length; i++) {
    if (raw[i] === 0) {
      if (i > start) out.push(raw.subarray(start, i).toString("utf8"));
      start = i + 1;
    }
  }
  if (start < raw.length) out.push(raw.subarray(start).toString("utf8"));
  if (out.length === 0) fatal("git ls-files 为空——fail loud（空集不得绿）");
  return out;
}

export function scanRepo(root: string): { files: number; hits: Array<{ p: string; offset: number; count: number }> } {
  const allow = readAllowlist(root);
  const files = listTracked(root);
  const hits: Array<{ p: string; offset: number; count: number }> = [];
  for (const p of files) {
    if (allow.has(p)) continue;
    let data: Buffer;
    try {
      data = fs.readFileSync(path.join(root, p));
    } catch {
      continue; // 工作区缺文件（子模块/稀疏检出）不属本闸职责
    }
    const hit = findNul(data);
    if (hit) hits.push({ p, offset: hit.offset, count: hit.count });
  }
  return { files: files.length, hits };
}

/**
 * 检查面 ②：包外散 .mbt（S13b-P10）。返回 git 跟踪、位于 moonbit/ 下、向上
 * 直到 moon.mod 都找不到 moon.pkg 的 .mbt 路径（正斜杠形态）。
 */
export function findOrphanMbt(root: string, tracked: string[] = listTracked(root)): string[] {
  const out: string[] = [];
  for (const p of tracked) {
    const norm = p.split("\\").join("/");
    if (!norm.startsWith("moonbit/") || !norm.endsWith(".mbt")) continue;
    let dir = path.dirname(path.join(root, norm));
    for (;;) {
      if (fs.existsSync(path.join(dir, "moon.pkg"))) break; // 包内
      if (fs.existsSync(path.join(dir, "moon.mod"))) {
        out.push(norm); // 到 workspace 根仍未遇 moon.pkg
        break;
      }
      const parent = path.dirname(dir);
      if (parent === dir) {
        out.push(norm); // 越过文件系统根（防御）
        break;
      }
      dir = parent;
    }
  }
  return out;
}

function fatal(msg: string): never {
  process.stderr.write("source_hygiene: " + msg + "\n");
  process.exit(2);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  const root = projectRoot();
  const { files, hits } = scanRepo(root);
  for (const h of hits) {
    console.log(`含真 NUL: ${h.p}（首个偏移 ${h.offset}，共 ${h.count} 个）——改转义写法（如 \\x00）或登记 allowlist`);
  }
  const orphans = findOrphanMbt(root);
  for (const o of orphans) {
    console.log(`包外散 .mbt: ${o}——向上无 moon.pkg，moon fmt/构建/测试全链不可见（落进有 moon.pkg 的包，AGENTS 13.5）`);
  }
  if (hits.length > 0 || orphans.length > 0) {
    fatal(`source_hygiene: ${hits.length} 个被跟踪文件含真 NUL（git 将判二进制，diff 不可见）；${orphans.length} 个包外散 .mbt`);
  }
  console.log(`source_hygiene: OK（${files} 个被跟踪文件零真 NUL；moonbit/ 下 .mbt 零包外散件）`);
}
