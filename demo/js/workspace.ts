// Vitro demo · 本地文件夹工作区（2026-10-05 打开本地文件夹批）。
// File System Access API（showDirectoryPicker）授权读写本地目录：
// 递归枚举 .c/.h → 文件 chips 切换编辑（单编辑器缓冲模型——切换即写回
// 内存 buffer）→ 运行时全量打包 compile.files（引擎 vfs 解析集合内
// quote-include，见 gateway files-vfs 批）→ Ctrl+S / 保存按钮写回磁盘
// 原文件（不自动保存；关页靠 beforeunload 浏览器原生提示兜底——用户
// 拍板）。移动端（≤960px）入口整体隐藏（无降级——Chromium 桌面能力）。
// 点课 = 离开工作区：dirty 时 confirm 后保存并关闭（ensureClosedForLesson）。
// 纯函数（toPosix/isSourceFile/shouldSkipDir/orderForCompile）经 node --test
// 锚定；FSA 句柄面 DOM lib 未收录（TS 5.9 无 showDirectoryPicker/目录
// 枚举），本文件局部声明。
"use strict";

import { $, esc, setStatus } from "./util.ts";
import { renderEditorDecor } from "./editor.ts";

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

// ── 工作区状态 ─────────────────────────────────────────────

interface WsFile {
  path: string;       // posix 相对路径（vfs key 同形）
  source: string;     // 内存缓冲（编辑器当前内容——input 事件同步）
  saved: string;      // 磁盘内容快照（dirty 判据）
  handle: WsFileHandle;
}

const MAX_FILES = 200;        // 文件数上限（防拖进巨型仓库）
const MAX_FILE_BYTES = 2 * 1024 * 1024; // 单文件 2MB 上限
const MAX_DEPTH = 8;          // 递归深度上限

let files: WsFile[] = [];
let activePath: string | null = null;
let dirName = "";

export function workspaceActive(): boolean { return files.length > 0; }
export function activeFilePath(): string | null { return activePath; }

/** 编辑器 input 同步（app 挂接）：active 文件缓冲跟随，dirty 点亮 chip。 */
export function syncFromEditor(): void {
  if (!activePath) return;
  const f = files.find((x) => x.path === activePath);
  if (!f) return;
  f.source = $<HTMLTextAreaElement>("editor").value;
  renderWsBar();
}

// ── 打开 / 关闭 ────────────────────────────────────────────

export async function openWorkspace(): Promise<void> {
  const w = window as PickerWindow;
  if (!w.showDirectoryPicker) return;
  let root: WsDirHandle;
  try {
    root = await w.showDirectoryPicker({ mode: "readwrite" });
  } catch {
    return; // 用户取消授权——非错误路径
  }
  const collected: WsFile[] = [];
  const walk = async (dir: WsDirHandle, prefix: string, depth: number): Promise<void> => {
    if (depth > MAX_DEPTH || collected.length >= MAX_FILES) return;
    for await (const ent of dir.values()) {
      if (collected.length >= MAX_FILES) return;
      if (ent.kind === "directory") {
        if (!shouldSkipDir(ent.name)) await walk(ent, prefix + ent.name + "/", depth + 1);
      } else if (isSourceFile(ent.name)) {
        try {
          const f = await ent.getFile();
          if (f.size > MAX_FILE_BYTES) continue;
          const text = await f.text();
          collected.push({ path: toPosix(prefix + ent.name), source: text, saved: text, handle: ent });
        } catch { /* 读取失败的单文件跳过（权限/占用）*/ }
      }
    }
  };
  await walk(root, "", 0);
  if (collected.length === 0) {
    setStatus("err", "该文件夹没有 .c/.h 文件");
    return;
  }
  if (collected.length >= MAX_FILES) {
    setStatus("busy", `文件数超 ${MAX_FILES} 上限，只载入前 ${MAX_FILES} 个`);
  }
  files = collected;
  dirName = root.name;
  // 首选 main.c 为 active，否则首个 .c，否则首个 .h
  const main = files.find((f) => /(^|\/)main\.c$/i.test(f.path));
  const firstC = files.find((f) => /\.c$/i.test(f.path));
  const target = main || firstC || files[0];
  activePath = target.path;
  $<HTMLTextAreaElement>("editor").value = target.source;
  renderEditorDecor();
  renderWsBar();
  $("ws-bar").classList.remove("hidden");
  setStatus("idle", `工作区：${dirName}（${files.length} 文件）`);
}

export function closeWorkspace(): void {
  files = [];
  activePath = null;
  $("ws-bar").classList.add("hidden");
}

/** 点课 guard（课程载入 = 离开工作区）：dirty 时 confirm 保存；
 *  返回 false = 用户取消，调用方不得继续切换。 */
export async function ensureClosedForLesson(): Promise<boolean> {
  if (!workspaceActive()) return true;
  if (hasDirty()) {
    if (!window.confirm(`工作区「${dirName}」有未保存修改——保存后切换课程？`)) return false;
    await saveAllDirty();
  }
  closeWorkspace();
  return true;
}

// ── 文件切换 / 保存 ────────────────────────────────────────

export function switchTo(path: string): void {
  syncFromEditor(); // 当前缓冲先行落位（切换不丢编辑内容）
  const f = files.find((x) => x.path === path);
  if (!f) return;
  activePath = path;
  $<HTMLTextAreaElement>("editor").value = f.source;
  renderEditorDecor();
  renderWsBar();
}

function hasDirty(): boolean {
  return files.some((f) => f.source !== f.saved);
}

async function writeBack(f: WsFile): Promise<void> {
  const w = await f.handle.createWritable();
  await w.write(f.source);
  await w.close();
  f.saved = f.source;
}

export async function saveActiveFile(): Promise<void> {
  if (!activePath) return;
  syncFromEditor();
  const f = files.find((x) => x.path === activePath);
  if (!f || f.source === f.saved) return;
  try {
    await writeBack(f);
    setStatus("ok", `已保存 ${f.path}`);
  } catch (e) {
    setStatus("err", `保存失败 ${f.path}（${e instanceof Error ? e.message : String(e)}）`);
    return;
  }
  renderWsBar();
}

async function saveAllDirty(): Promise<void> {
  syncFromEditor();
  for (const f of files) {
    if (f.source === f.saved) continue;
    try { await writeBack(f); } catch { /* 尽力保存——失败态经 dirty 标记可见 */ }
  }
}

// ── 运行通道参数（run.ts buildCompileParams 工作区分支消费）────

export function workspaceFilesForCompile(): Array<{ filename: string; source: string }> {
  syncFromEditor();
  const ordered = orderForCompile(files.map((f) => f.path), activePath || "");
  return ordered.map((p) => {
    const f = files.find((x) => x.path === p)!;
    return { filename: p, source: p === activePath ? $<HTMLTextAreaElement>("editor").value : f.source };
  });
}

// ── UI（文件 chips 条）─────────────────────────────────────

function renderWsBar(): void {
  $("ws-name").textContent = dirName;
  $("ws-name").setAttribute("title", dirName);
  const box = $("ws-files");
  box.innerHTML = files
    .map((f) => {
      const dirty = f.source !== f.saved;
      return (
        `<button type="button" class="ws-chip${f.path === activePath ? " on" : ""}${dirty ? " dirty" : ""}"` +
        ` data-path="${esc(f.path)}" title="${esc(f.path)}${dirty ? "（未保存）" : ""}">` +
        `${esc(f.path.split("/").pop() || f.path)}<i class="ws-dot"></i></button>`
      );
    })
    .join("");
  box.querySelectorAll<HTMLElement>(".ws-chip").forEach((chip) => {
    chip.onclick = () => switchTo(chip.dataset.path || "");
  });
}

// ── 挂接（app boot 调用一次）────────────────────────────────

export function initWorkspace(): void {
  if (!workspaceSupported()) return; // 不支持的浏览器不渲染入口（不降级）
  const openBtn = $("ws-open");
  openBtn.classList.remove("hidden");
  openBtn.onclick = () => void openWorkspace();
  $("ws-close").onclick = () => {
    if (hasDirty() && !window.confirm(`工作区「${dirName}」有未保存修改——直接丢弃并关闭？`)) return;
    closeWorkspace();
  };
  $("ws-save").onclick = () => void saveActiveFile();
  // 编辑器输入同步缓冲（dirty 追踪；装饰重渲染由 editor 模块自己的 input 钩子负责）
  $("editor").addEventListener("input", syncFromEditor);
  // Ctrl+S 保存当前文件（工作区开时才劫持）
  document.addEventListener("keydown", (e: KeyboardEvent) => {
    if (!workspaceActive()) return;
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
      e.preventDefault();
      void saveActiveFile();
    }
  });
  // 关页兜底：dirty 时浏览器原生「离开页面？」提示（用户拍板的退出防护形态）
  window.addEventListener("beforeunload", (e: BeforeUnloadEvent) => {
    if (hasDirty()) { e.preventDefault(); e.returnValue = ""; }
  });
}
