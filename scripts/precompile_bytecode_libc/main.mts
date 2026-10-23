#!/usr/bin/env node
// precompile_bytecode_libc —— Bytecode Libc 预编译产物的冻结完整性闸
// （#273 存量 Go 重写批；生成模式已随 Rust oracle 退役——现役仅 --check）。
//
// 校验：scripts/moonbit/libc_src/ 的 C 源（行尾归一）↔
// scripts/moonbit/libc_data/bytecode_libc_data.json 的 source_digest。
//
//   node scripts/precompile_bytecode_libc/main.mts --check
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

const DIGEST_SCHEMA = 1;

function srcDirs(root: string): string[] {
  return [
    path.join(root, "scripts/moonbit/libc_src/src"),
    path.join(root, "scripts/moonbit/libc_src/vitro"),
  ];
}

export function artifactPath(root: string): string {
  return path.join(root, "scripts/moonbit/libc_data/bytecode_libc_data.json");
}

// sourceFiles 返回参与预编译的源文件（按完整路径排序——确定性）。
export function sourceFiles(root: string, includeHeaders: boolean): string[] {
  const exts = new Set([".c", ".cpp"]);
  if (includeHeaders) exts.add(".h");
  const files: string[] = [];
  for (const dir of srcDirs(root)) {
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of ents) {
      if (e.isDirectory()) continue;
      if (exts.has(path.extname(e.name))) files.push(path.join(dir, e.name));
    }
  }
  return files.sort();
}

// computeSourceDigest：源内容（CRLF→LF）+ schema 联合摘要（与删区前生成器逐位同源）。
export function computeSourceDigest(root: string): string {
  const h = crypto.createHash("sha256");
  h.update(Buffer.from(`schema=${DIGEST_SCHEMA}\n`, "utf8"));
  for (const f of sourceFiles(root, true)) {
    const rel = path.relative(root, f).split(path.sep).join("/");
    h.update(Buffer.from(rel, "utf8"));
    h.update(Buffer.from([0]));
    let b: Buffer;
    try {
      b = fs.readFileSync(f);
    } catch (e) {
      process.stderr.write(`读源文件失败: ${f} ${String(e)}（digest 拒绝静默缺文件）\n`);
      process.exit(2);
    }
    h.update(Buffer.from(b.toString("latin1").replace(/\r\n/g, "\n"), "latin1"));
    h.update(Buffer.from([0]));
  }
  return "sha256:" + h.digest("hex");
}

export interface VerifyResult {
  ok: boolean;
  message: string;
}

export function verify(root: string, artifact = artifactPath(root)): VerifyResult {
  let raw: string;
  try {
    raw = fs.readFileSync(artifact, "utf8");
  } catch (e) {
    return { ok: false, message: `  missing artifact: ${artifact}: ${e instanceof Error ? e.message : String(e)}` };
  }
  let recorded = "";
  try {
    const probe = JSON.parse(raw) as { source_digest?: unknown };
    if (typeof probe.source_digest === "string") recorded = probe.source_digest;
  } catch {
    // 落到统一错误
  }
  if (recorded === "") return { ok: false, message: "  artifact unreadable or no source_digest" };
  const current = computeSourceDigest(root);
  if (recorded !== current) {
    return {
      ok: false,
      message:
        `  recorded digest: ${recorded}\n` +
        `  current  digest: ${current}\n` +
        `  source files: ${sourceFiles(root, true).length} under scripts/moonbit/libc_src\n` +
        "ERROR: libc 源已变更而冻结产物未更新（重生成走 rust-oracle-freeze 历史路径）",
    };
  }
  return { ok: true, message: "Precompiled artifact integrity OK（libc 源 ↔ 冻结产物 digest 一致）" };
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  const args = process.argv.slice(2);
  let check = false;
  for (const a of args) {
    if (a === "-check" || a === "--check") check = true;
    else if (a === "-h" || a === "--help") {
      process.stdout.write("用法: precompile_bytecode_libc --check\n");
      process.exitCode = 0;
      process.exit(0);
    } else {
      process.stderr.write(`precompile_bytecode_libc: 未知参数 ${a}\n`);
      process.exit(2);
    }
  }
  if (!check) {
    process.stderr.write(
      "生成模式已随 Rust oracle 退役（工序④ 2026-10-05）——产物为冻结终态；重生成须 checkout tag rust-oracle-freeze 重建 oracle 后用 git 历史版生成模式。现役仅 --check。\n"
    );
    process.exit(2);
  }
  const r = verify(projectRoot());
  if (!r.ok) {
    process.stderr.write(r.message + "\n");
    process.exitCode = 1;
  } else {
    console.log(r.message);
  }
}
