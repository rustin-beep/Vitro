// capi.mts —— 防线脚本共享基础工具单源（#273 存量 Go 重写批）。
//
// 口径与 Go 版一致：仓库根 = 含 corpus/ 与 scripts/ 的目录（从 cwd 向上最多
// 5 层）；失败 exit 2；Fatal 前缀 "FATAL: "；TruncateRunes 按字符（码点）截断。
import fs from "node:fs";
import path from "node:path";
import { byteCompare } from "./text.mts";

let cachedRoot: string | null = null;

function isProjectRoot(dir: string): boolean {
  for (const marker of ["corpus", "scripts"]) {
    try {
      if (!fs.statSync(path.join(dir, marker)).isDirectory()) return false;
    } catch {
      return false;
    }
  }
  return true;
}

export function projectRoot(): string {
  if (cachedRoot !== null) return cachedRoot;
  let dir = process.cwd();
  for (let i = 0; i < 5; i++) {
    if (isProjectRoot(dir)) {
      cachedRoot = dir;
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  process.stderr.write("请在仓库内运行：找不到包含 corpus/ 与 scripts/ 的项目根\n");
  process.exit(2);
}

export function fatal(msg: string): never {
  process.stderr.write("FATAL: " + msg + "\n");
  process.exit(2);
}

// TruncateRunes 按字符数截断（非字节；与 Go []rune 切片一致）。
export function truncateRunes(s: string, n: number): string {
  const runes = Array.from(s);
  return runes.length <= n ? s : runes.slice(0, n).join("");
}

/**
 * filepath.WalkDir 等价：**同层按文件名字节序**遍历（Go 的 ReadDir 内部对
 * 目录项排序，字节序——用 `.sort()` 的 UTF-16 序在 astral 文件名上会漂移）。
 *
 * visit 收 (全路径, 文件名, 是否目录)；返回 "skip" 表示「这是目录且不下钻」
 * （对应 Go 回调里 `return filepath.SkipDir`）。root 本身不回调（Go 会回调
 * root，但存量消费面全都 `IsDir() → return nil`，故省略——真需要时再加）。
 *
 * 错误（目录不存在 / 不可读）直接抛出，调用方负责 fail loud 文案。
 */
export function walkDirSorted(
  root: string,
  visit: (full: string, name: string, isDir: boolean) => "skip" | void,
): void {
  const entries = fs.readdirSync(root, { withFileTypes: true });
  entries.sort((a, b) => byteCompare(a.name, b.name));
  for (const e of entries) {
    const full = path.join(root, e.name);
    if (e.isDirectory()) {
      if (visit(full, e.name, true) === "skip") continue;
      walkDirSorted(full, visit);
    } else {
      visit(full, e.name, false);
    }
  }
}
