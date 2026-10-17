// Vitro demo · 工作区纯函数面（2026-10-17 F4 收尾：FSA 胶水随旧栈退役）。
//
// 历史：本模块原为「打开本地文件夹」整件（FSA 授权枚举 → 编辑器 chips →
// 全量打包 compile.files → 写回磁盘），胶水层直接操作旧栈 #editor 文本域
// （经 editor.ts 的 renderEditorDecor），与旧栈同生共死。F4 收尾时旧栈删除，
// 新栈的 FSA 胶水在 src/lib/workspace.svelte.ts（Svelte 状态面），本文件
// 只保留**两侧共用的纯函数**（toPosix/isSourceFile/shouldSkipDir/
// orderForCompile + 能力探测 workspaceSupported）——node --test 锚定面不变。
"use strict";



// ── FSA 局部类型（duck-typing 最小面）────────────────────────

interface WsFileHandle {
  kind: "file";
  name: string;
  getFile(): Promise<File>;
  createWritable(opts?: { keepExistingData?: boolean }): Promise<WsWritable>;
}
interface WsWritable {
  write(data: string): Promise<void>;
  close(): Promise<void>;
}
interface WsDirHandle {
  kind: "directory";
  name: string;
  values(): AsyncIterableIterator<WsFileHandle | WsDirHandle>;
}
type PickerWindow = Window & {
  showDirectoryPicker?(opts?: { mode?: "read" | "readwrite" }): Promise<WsDirHandle>;
};

/** 桌面 Chromium 才有目录选择器（能力探测——不满足时入口不渲染行为兜底）。 */
export function workspaceSupported(): boolean {
  return typeof (window as PickerWindow).showDirectoryPicker === "function";
}

// ── 纯函数（node --test 锚定面）──────────────────────────────

/** 路径归一为 posix 相对形态（引擎 vfs key 与 base_dir 候选链口径）。 */
export function toPosix(p: string): string {
  return p.replace(/\\/g, "/").replace(/^\.\//, "");
}

/** 编译面文件判定：.c / .h（大小写不敏感）。 */
export function isSourceFile(name: string): boolean {
  return /\.(c|h)$/i.test(name);
}

/** 目录剪枝：隐藏目录与常见非源码大目录（拖进 node_modules 防护的上半段）。 */
export function shouldSkipDir(name: string): boolean {
  return name.startsWith(".") ||
    /^(node_modules|_build|target|build|dist|__pycache__|out|bin|obj)$/i.test(name);
}

/** 编译单元排序：active 文件居首（引擎 base_dir 取首个 unit 的目录段——
 *  include 候选链锚在 active 文件所在目录），其余 posix 字典序稳定排。 */
export function orderForCompile(paths: string[], active: string): string[] {
  const rest = paths.filter((p) => p !== active).sort();
  return active && paths.includes(active) ? [active, ...rest] : rest;
}
