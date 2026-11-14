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
  // 顶层 tmp_* 探针工作区族走 .gitignore 单源（/tmp_*/ 通配，2026-11-13）——
  // gitignored 面豁免自动覆盖,不再逐名登记
  ".vscode",
  "build",
  "dist-pilot",
  "dist-e08",
  "dist",
  ".workbuddy",
  // #292 批：corpus_fuzz 的运行期缓存（gitignored，KEY/变体程序写出物常缺末行
  // 换行）——不剪枝则「本地跑过一次 fuzz」后本闸恒红，属与提交内容无关的环境
  // 盲区（同 .build/.workbuddy 一族）。
  ".corpus_fuzz_cache",
  // Stryker sandbox（mutation gate 复制 scripts/ 整树 + instrument 注入）——
  // 跑突变期间/FATAL 残留时本闸不得扫副本（2026-11-02 PR #416 同族）
  ".stryker-tmp",
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

// cwd 必须锚定 base（PR #518 追加批实锤修复）：git ls-files 输出相对 cwd 的
// 路径——无 cwd 锚定时继承进程 cwd（CI 的 npm test 在 scripts/ 下跑），输出
// `wasmtime_arm/rs/target/` 而 walk 的 rel 是 `scripts/wasmtime_arm/rs/target`
// ——前缀失配 → gitignored 豁免静默失效。CI 干净检出无 cargo target 故未
// 暴露；本地跑过 W4 前置 cargo build（生成 rs/target/）即 node:test 红。
function loadGitIgnored(cwd: string): Set<string> | null {
  const r = spawnSync("git", ["ls-files", "--ignored", "--exclude-standard", "--others", "--directory"], {
    encoding: "utf8",
    cwd,
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
  const gitIgnored = makeGitIgnored(loadGitIgnored(base));
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
      // tools/cache = 外部工具下载缓存（binaryen 等）：原根下形态 + wasmopt .mts 化后
      // 的 moonbit/tools/cache 形态（2026-11-01 审阅 v2 批 A1 实锤：后者的
      // package/LICENSE 缺末行换行，「本地跑过一次 wasmopt」即本闸与 npm test 恒红；
      // git ls-files --ignored 面实测未列出该目录故须硬编码——按路径前缀精确剪，
      // 不按段名「tools」剪：moonbit/teaching/tools 是 content_parser.c 真源树）
      if (rel.startsWith("tools" + path.sep + "cache") || rel.startsWith(path.join("moonbit", "tools", "cache"))) continue;
      if (rel.split(path.sep).some((seg) => SKIP_SEGS.has(seg))) continue;
      if (e.isDirectory()) {
        // 嵌套 git worktree / submodule：独立仓库，不属于本仓内容（根下审阅
        // worktree 曾被当普通目录扫入，导致本地 pre-commit 恒红）。
        if (fs.existsSync(path.join(p, ".git"))) continue;
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
