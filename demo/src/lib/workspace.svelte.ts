// Vitro 试点 · 本地文件夹工作区（F4 残留②——旧栈 js/workspace.ts 2026-10-05
// 「打开本地文件夹批」的新栈迁移）。形态逐项对齐旧栈：
//   - FSA（showDirectoryPicker）递归枚举 .c/.h（剪枝/上限同旧值）；
//   - 文件 chips 切换编辑（单编辑器缓冲模型——切换即写回内存 buffer）；
//   - 采集/运行时全量打包 compile.files（引擎 vfs 解析集合内 quote-include）；
//   - Ctrl+S / 保存按钮写回磁盘（不自动保存；关页 beforeunload 兜底）；
//   - 点课 = 离开工作区：dirty 时 confirm 后保存并关闭（ensureClosedForLesson）。
//
// 纯函数（toPosix/isSourceFile/shouldSkipDir/orderForCompile/workspaceSupported）
// 物理保留 import 旧模块——pure.test.mts 的 workspace 四锚零改动（F4 既定模式：
// 测试锚不因迁移重写）。
//
// 与旧栈的结构差异（新栈架构决定，非行为差异）：
//   - 编辑器是 CM6（source $bindable）——「同步编辑器」从 DOM 读值改为
//     App $effect 调 syncSource（缓冲/dirty 追踪）；compile 打包显式收
//     liveSource 参数（旧栈 workspaceFilesForCompile 直读 DOM textarea 的新栈
//     等价——active 文件内容 = 编辑器当前内容）。
//   - 反馈走 toast（操作结果分域——session.status 是采集会话态，不得混用）。
"use strict";

import { isSourceFile, orderForCompile, shouldSkipDir, toPosix, workspaceSupported } from "../../js/workspace.ts";
import { toast } from "../toasts.svelte.ts";

// ── FSA 局部类型（duck-typing 最小面——DOM lib 未收录，照旧栈局部声明）────

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

export { workspaceSupported };

export interface WsFile {
  path: string;   // posix 相对路径（vfs key 同形）
  source: string; // 内存缓冲（编辑器当前内容——syncSource 同步）
  saved: string;  // 磁盘内容快照（dirty 判据）
  handle: WsFileHandle;
}

const MAX_FILES = 200;        // 文件数上限（防拖进巨型仓库——同旧栈）
const MAX_FILE_BYTES = 2 * 1024 * 1024; // 单文件 2MB 上限
const MAX_DEPTH = 8;          // 递归深度上限

class WorkspaceState {
  files = $state.raw([] as WsFile[]);
  /** dirty 标记响应面：files 是 raw（大数据不代理——F4 分界纪律），但 chip
   *  圆点/保存按钮态要随键入实时翻。故用一个小集合单独跟踪 dirty 路径——
   *  响应面与数据面分离（raw 对象 mutation 不触发更新，实测过）。 */
  dirtyPaths = $state(new Set<string>());
  activePath = $state<string | null>(null);
  dirName = $state("");
  opening = $state(false); // 授权/枚举进行中（入口按钮 busy 态）

  get activeFile(): WsFile | null {
    return this.files.find((f) => f.path === this.activePath) ?? null;
  }
  get active(): boolean {
    return this.files.length > 0;
  }
  get dirty(): boolean {
    return this.dirtyPaths.size > 0;
  }
}

export const workspace = new WorkspaceState();

/** dirty 集合写入（新集合替换——$state Set 的 add/delete 同款语义）。 */
function markDirty(path: string, on: boolean): void {
  const has = workspace.dirtyPaths.has(path);
  if (on && !has) workspace.dirtyPaths = new Set(workspace.dirtyPaths).add(path);
  else if (!on && has) {
    const next = new Set(workspace.dirtyPaths);
    next.delete(path);
    workspace.dirtyPaths = next;
  }
}

/** 编辑器缓冲同步（App $effect 挂接）：active 文件缓冲跟随编辑器内容，
 *  dirty 追踪 + chip 圆点数据源。非工作区态空操作。 */
export function syncSource(src: string): void {
  if (!workspace.activePath) return;
  const f = workspace.files.find((x) => x.path === workspace.activePath);
  if (!f) return;
  f.source = src;
  markDirty(f.path, f.source !== f.saved);
}

// ── 打开 / 关闭 ────────────────────────────────────────────

/** 打开工作区。成功返回 active 文件源码（调用方写入编辑器——旧栈
 *  openWorkspace 直写 textarea 的新栈等价：store 不直摸编辑器，经 Bar 的
 *  onswitch 回调上交）；取消/无源码文件返回 null。 */
export async function openWorkspace(): Promise<string | null> {
  const w = window as PickerWindow;
  if (!w.showDirectoryPicker) return null;
  let root: WsDirHandle;
  try {
    root = await w.showDirectoryPicker({ mode: "readwrite" });
  } catch {
    return null; // 用户取消授权——非错误路径（旧栈同语义：静默）
  }
  workspace.opening = true;
  try {
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
          } catch { /* 读取失败的单文件跳过（权限/占用）——旧栈同语义 */ }
        }
      }
    };
    await walk(root, "", 0);
    if (collected.length === 0) {
      toast("err", "该文件夹没有 .c/.h 文件");
      return null;
    }
    if (collected.length >= MAX_FILES) {
      toast("info", `文件数超 ${MAX_FILES} 上限，只载入前 ${MAX_FILES} 个`);
    }
    workspace.files = collected;
    workspace.dirName = root.name;
    // 首选 main.c 为 active，否则首个 .c，否则首个 .h（旧栈同规则）
    const main = collected.find((f) => /(^|\/)main\.c$/i.test(f.path));
    const firstC = collected.find((f) => /\.c$/i.test(f.path));
    const target = main || firstC || collected[0];
    workspace.activePath = target.path;
    toast("ok", `工作区：${workspace.dirName}（${collected.length} 文件）——active：${target.path}`);
    return target.source;
  } finally {
    workspace.opening = false;
  }
}

/** 关闭工作区（dirty 处置由调用方负责——ensureClosedForLesson / 关闭按钮 confirm）。 */
export function closeWorkspace(): void {
  workspace.files = [];
  workspace.activePath = null;
  workspace.dirName = "";
  workspace.dirtyPaths = new Set();
}

/** 点课 guard（课程载入 = 离开工作区）：dirty 时 confirm 保存；
 *  返回 false = 用户取消，调用方不得继续切换。 */
export async function ensureClosedForLesson(): Promise<boolean> {
  if (!workspace.active) return true;
  if (workspace.dirty) {
    if (!window.confirm(`工作区「${workspace.dirName}」有未保存修改——保存后切换课程？`)) return false;
    await saveAllDirty();
  }
  closeWorkspace();
  return true;
}

// ── 文件切换 / 保存 ────────────────────────────────────────

/** 切换 active 文件。返回新文件源码——调用方（App）写入编辑器 source
 *  （$bindable 直通 CM6；store 不直摸编辑器实例）。 */
export function switchTo(path: string): string | null {
  const f = workspace.files.find((x) => x.path === path);
  if (!f) return null;
  workspace.activePath = path;
  return f.source;
}

function hasDirty(): boolean {
  return workspace.dirty;
}

async function writeBack(f: WsFile): Promise<void> {
  const w = await f.handle.createWritable();
  await w.write(f.source);
  await w.close();
  f.saved = f.source;
  markDirty(f.path, false);
}

export async function saveActiveFile(): Promise<void> {
  const f = workspace.activeFile;
  if (!f || f.source === f.saved) return;
  try {
    await writeBack(f);
    toast("ok", `已保存 ${f.path}`);
  } catch (e) {
    toast("err", `保存失败 ${f.path}（${e instanceof Error ? e.message : String(e)}）`);
    return;
  }
}

async function saveAllDirty(): Promise<void> {
  for (const f of workspace.files) {
    if (f.source === f.saved) continue;
    try { await writeBack(f); } catch { /* 尽力保存——失败态经 dirty 标记可见 */ }
  }
}

/** 关闭按钮 guard：dirty 时 confirm 丢弃（旧栈 ws-close 语义）。 */
export function confirmCloseWorkspace(): boolean {
  if (hasDirty() && !window.confirm(`工作区「${workspace.dirName}」有未保存修改——直接丢弃并关闭？`)) return false;
  closeWorkspace();
  return true;
}

// ── 采集通道参数（session.collect 工作区分支消费——旧栈 buildCompileParams
//    单一源语义的新栈等价：active 文件 = 编辑器当前内容，显式收 liveSource）──

export function workspaceFilesForCompile(liveSource: string): Array<{ filename: string; source: string }> {
  const ordered = orderForCompile(workspace.files.map((f) => f.path), workspace.activePath || "");
  return ordered.map((p) => {
    const f = workspace.files.find((x) => x.path === p)!;
    return { filename: p, source: p === workspace.activePath ? liveSource : f.source };
  });
}
