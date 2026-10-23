#!/usr/bin/env node
// editorconfig 机判闸（#61 零头；#273 存量 Go 重写批）。
//
// .editorconfig 声明的 charset/end_of_line/insert_final_newline 三硬性项对全仓
// 文本文件机判：UTF-8 可解码、LF 行尾（CRLF 归一后 lone CR 仍红）、末行换行；
// .json / .json.mbt 追加 2 空格缩进项。豁免：@generated 生成物、gitignored 面
// （.gitignore 单源）、tmp/_build/.mooncakes/node_modules/dist*/.workbuddy 等。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const SKIP_SEGS = new Set([
  ".git",
  "_build",
  ".mooncakes",
  "node_modules",
  "tmp",
  ".clang_cache_cd",
  ".shadow_tmp",
  "tmp_vitro_fs_bb_roundtrip",
  ".vscode",
  "build",
  "dist-pilot",
  "dist-e08",
  "dist",
  ".workbuddy",
]);

const JSON_EXEMPT_PREFIXES = [
  "scripts/moonbit/diagnostics_data",
  "scripts/teaching_annotation_diff",
  "scripts/vm_diff",
  "scripts/clang_direct",
  "scripts/lexer_diff",
  "scripts/typeck_diff",
  "scripts/codegen_diff",
  "scripts/protocol_frames",
  "scripts/parser_diff",
];

function loadGitIgnored(): Set<string> | null {
  const r = spawnSync("git", ["ls-files", "--ignored", "--exclude-standard", "--others", "--directory"], {
    encoding: "utf8",
  });
  if (r.status !== 0) {
    process.stderr.write(`editorconfig_check: git 不可用（${r.stderr.trim()}）——gitignored 豁免降级为硬编码清单\n`);
    return null;
  }
  const set = new Set<string>();
  for (const raw of (r.stdout ?? "").split("\n")) {
    const ln = raw.replace(/\/+$/, "");
    if (ln !== "") set.add(ln.split(path.sep).join("/"));
  }
  return set;
}

function makeGitIgnored(set: Set<string> | null): (rel: string) => boolean {
  return (rel: string): boolean => {
    if (set === null) return false;
    const segs = rel.split(path.sep).join("/").split("/");
    for (let i = 0; i < segs.length; i++) {
      if (set.has(segs.slice(0, i + 1).join("/"))) return true;
    }
    return false;
  };
}

function isText(raw: Buffer): boolean {
  return raw.indexOf(0) < 0;
}

function isGenerated(raw: Buffer): boolean {
  return raw.subarray(0, Math.min(400, raw.length)).includes("@generated");
}

function utf8Valid(raw: Buffer): boolean {
  let i = 0;
  while (i < raw.length) {
    const b = raw[i] ?? 0;
    if (b < 0x80) {
      i++;
      continue;
    }
    let n: number;
    if ((b & 0xe0) === 0xc0) n = 2;
    else if ((b & 0xf0) === 0xe0) n = 3;
    else if ((b & 0xf8) === 0xf0) n = 4;
    else return false;
    if (i + n > raw.length) return false;
    for (let j = 1; j < n; j++) {
      if (((raw[i + j] ?? 0) & 0xc0) !== 0x80) return false;
    }
    i += n;
  }
  return true;
}

// jsonIndentCheck：缩进 2 空格（逐行扫行首空白——缩进量非 2 的倍数即红）
export function jsonIndentCheck(raw: Buffer): string {
  const lines = raw.toString("utf8").split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? "";
    if (line.trim() === "") continue;
    let ind = 0;
    while (line[ind] === " ") ind++;
    if (ind % 2 !== 0) return `第 ${i + 1} 行缩进 ${ind}（非 2 的倍数）`;
  }
  return "";
}

export function checkTree(baseArg: string): string[] {
  const base = path.resolve(baseArg);
  const gitIgnored = makeGitIgnored(loadGitIgnored());
  const offenders: string[] = [];

  const walk = (dir: string): void => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (const e of entries) {
      const p = path.join(dir, e.name);
      const rel = path.relative(base, p);
      if (gitIgnored(rel)) continue;
      if (rel === "demo-evidence" || rel.startsWith("demo-evidence" + path.sep)) continue;
      if (rel.startsWith("tools" + path.sep + "cache")) continue;
      if (rel.split(path.sep).some((seg) => SKIP_SEGS.has(seg))) continue;
      if (e.isDirectory()) {
        walk(p);
        continue;
      }
      let raw: Buffer;
      try {
        raw = fs.readFileSync(p);
      } catch {
        continue;
      }
      if (!isText(raw) || isGenerated(raw)) continue;
      const name = path.basename(p);
      const relSlash = rel.split(path.sep).join("/");
      if (name.endsWith(".json") || name.endsWith(".json.mbt")) {
        if (JSON_EXEMPT_PREFIXES.some((pre) => relSlash.startsWith(pre + "/"))) continue;
      }
      if (relSlash.startsWith("docs/current/07-质量与裁定/demo实测样本库") || relSlash.startsWith("reports/")) continue;
      if (!utf8Valid(raw)) {
        offenders.push(rel + "（非 UTF-8 字节）");
        continue;
      }
      if (raw.indexOf(0x0d) >= 0) {
        const norm = Buffer.from(raw.toString("latin1").replace(/\r\n/g, "\n"), "latin1");
        if (norm.indexOf(0x0d) >= 0) offenders.push(rel + "（lone CR——非 CRLF 对形态）");
        raw = norm;
      }
      if (raw.length > 0 && raw[raw.length - 1] !== 0x0a) offenders.push(rel + "（缺末行换行）");
      if (name.endsWith(".json") || name.endsWith(".json.mbt")) {
        const v = jsonIndentCheck(raw);
        if (v !== "") offenders.push(rel + "（" + v + "）");
      }
    }
  };
  walk(base);
  return offenders;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  const args = process.argv.slice(2);
  let root = ".";
  for (let i = 0; i < args.length; i++) {
    const a = args[i] ?? "";
    if (a === "-root" || a === "--root") {
      const v = args[++i];
      if (v === undefined) {
        process.stderr.write("editorconfig_check: -root 缺值\n");
        process.exit(2);
      }
      root = v;
    } else if (a.startsWith("-root=") || a.startsWith("--root=")) {
      root = a.slice(a.indexOf("=") + 1);
    } else {
      process.stderr.write(`editorconfig_check: 未知参数 ${a}\n`);
      process.exit(2);
    }
  }
  const offenders = checkTree(root);
  if (offenders.length > 0) {
    for (const o of offenders) console.log("editorconfig_check: " + o);
    console.log(`editorconfig_check: FAIL——${offenders.length} 处违反（.editorconfig 硬性项）`);
    process.exitCode = 1;
  } else {
    console.log("editorconfig_check: PASS——.editorconfig 硬性项（UTF-8/LF/末行换行/JSON 缩进）全仓合规");
  }
}
