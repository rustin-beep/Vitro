// capi.mts —— 防线脚本共享基础工具单源（#273 存量 Go 重写批）。
//
// 口径与 Go 版一致：仓库根 = 含 corpus/ 与 scripts/ 的目录（从 cwd 向上最多
// 5 层）；失败 exit 2；Fatal 前缀 "FATAL: "；TruncateRunes 按字符（码点）截断。
import fs from "node:fs";
import path from "node:path";

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
