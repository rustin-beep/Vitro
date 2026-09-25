///| S6 执行层·宿主函数域：**可变状态的快照通道**（vm 片批一号）。
///
/// `VMSnapshot` 定形（总计划 §10 S6 行）需要把 runtime 三态（输出 / 输入 /
/// VFS）随快照往返。Rust 侧这三者散在 `RuntimeSnapshot` 的 `Arc` 字段里
/// （快照持引用、写入时 COW——勘察 §1.9 的「每快照窗口一次全量克隆」）；
/// MoonBit 无 `Arc`，struct 是引用语义 ⇒ 快照 = **显式深拷贝**，语义与
/// Rust 的 `Arc::make_mut` 克隆点等价，且无「引用意外共享导致快照后写入
/// 泄漏进历史」的坑（拷贝即快照，时点明确）。
///
/// 三条通道的共同纪律：**Bytes 载体不可变 ⇒ 数组拷贝时字节共享**（零拷贝
/// 的部分只发生在不可变数据上，可变结构一律复制）。

///|
/// 输出日志快照：深拷贝全部记账字段与 chunks 数组（`Bytes` 不可变，共享）。
///
/// 恢复侧 = 直接替换 `VitroVM.output` 引用；`budget` 是运行配置，随快照
/// 往返（与 Rust `OutputLog` 整体克隆同口径）。
pub fn OutputLog::snapshot(self : OutputLog) -> OutputLog {
  let chunks_copy : Array[OutputChunk] = Array(capacity=self.chunks.length())
  for c in self.chunks {
    chunks_copy.push(OutputChunk::{ kind: c.kind, bytes: c.bytes, })
  }
  let kind_copy = FixedArray::make(3, 0)
  for i = 0; i < 3; i = i + 1 {
    kind_copy[i] = self.kind_bytes[i]
  }
  let pending_copy : Array[Byte] = Array(capacity=self.pending.length())
  for b in self.pending {
    pending_copy.push(b)
  }
  OutputLog::{
    chunks: chunks_copy,
    total_bytes: self.total_bytes,
    kind_bytes: kind_copy,
    dropped_bytes: self.dropped_bytes,
    truncation_noted: self.truncation_noted,
    budget: self.budget,
    pending: pending_copy,
    pending_kind: self.pending_kind,
    has_pending: self.has_pending,
  }
}

///|
/// 输入状态快照：游标 / EOF 粘滞 / ungetc 缓存全量拷贝；`lines` 数组
/// 浅拷一层（元素 `Bytes` 不可变共享；数组本身可被 Interactive 喂入
/// 追加，故容器必须复制）。
pub fn InputState::snapshot(self : InputState) -> InputState {
  let lines_copy : Array[Bytes] = Array(capacity=self.lines.length())
  for l in self.lines {
    lines_copy.push(l)
  }
  InputState::{
    lines: lines_copy,
    index: self.index,
    char_offset: self.char_offset,
    eof: self.eof,
    ungetc: self.ungetc,
    batch: self.batch,
  }
}

///|
/// VFS 文件元数据快照（文件**数据在 VM 堆内**，随 `MemoryImage` 自然往返；
/// 这里只快照元数据——勘察 §4.2-7「VFS 纳入快照」的口径，修复 Rust 侧
/// 「时间旅行回退后文件状态来自未来」的 P1 缺陷）。
pub(all) struct VfsFileSnapshot {
  mut heap_addr : UInt
  mut size : Int
  mut capacity : Int
} derive(Eq, Debug)

///|
/// VFS 描述符快照。`mode` 为 `VfsMode`（priv）的编号投影：
/// 0=Read / 1=Write / 2=Append——restore 穷尽 match，越界 fail loud。
pub(all) struct VfsDescSnapshot {
  mut file_name : String
  mode : Int
  mut cursor : Int
  mut eof : Bool
  mut error : Bool
  is_text_mode : Bool
} derive(Eq, Debug)

///|
/// VFS 快照整体（文件表 + 描述符表 + fd 计数——「fd 元数据进快照」的落点）。
pub(all) struct VfsSnapshot {
  files : Array[(String, VfsFileSnapshot)]
  descriptors : Array[(UInt, VfsDescSnapshot)]
  next_fd : UInt
} derive(Eq, Debug)

///|
/// VFS 快照（插入序保持——core `Map` 迭代序即插入序，与运行态一致）。
pub fn VirtualFileSystem::snapshot(self : VirtualFileSystem) -> VfsSnapshot {
  let files : Array[(String, VfsFileSnapshot)] = []
  for name, meta in self.files {
    files.push(
      (
        name,
        VfsFileSnapshot::{
          heap_addr: meta.heap_addr,
          size: meta.size,
          capacity: meta.capacity,
        },
      ),
    )
  }
  let descriptors : Array[(UInt, VfsDescSnapshot)] = []
  for fd, desc in self.descriptors {
    descriptors.push(
      (
        fd,
        VfsDescSnapshot::{
          file_name: desc.file_name,
          mode: vfs_mode_code(desc.mode),
          cursor: desc.cursor,
          eof: desc.eof,
          error: desc.error,
          is_text_mode: desc.is_text_mode,
        },
      ),
    )
  }
  VfsSnapshot::{ files, descriptors, next_fd: self.next_fd, }
}

///|
/// 快照恢复：**整体替换**文件表 / 描述符表 / fd 计数。
///
/// `mode` 编号越界即 abort（fail loud——快照数据损坏不得静默吞）。
/// 文件数据本体不在此通道（在 VM 堆，随 `MemoryImage` 往返）；恢复后
/// `heap_addr` 指向的堆区内容必须已由内存快照同步恢复——两个通道由
/// vm 侧 `restore` 统一调度，先后不敏感（元数据与字节互不依赖）。
pub fn VirtualFileSystem::restore(
  self : VirtualFileSystem,
  snap : VfsSnapshot,
) -> Unit {
  self.files.clear()
  for pair in snap.files {
    self.files.set(pair.0, VfsFileMeta::{
      heap_addr: pair.1.heap_addr,
      size: pair.1.size,
      capacity: pair.1.capacity,
    })
  }
  self.descriptors.clear()
  for pair in snap.descriptors {
    self.descriptors.set(pair.0, VfsDesc::{
      file_name: pair.1.file_name,
      mode: vfs_mode_from_code(pair.1.mode),
      cursor: pair.1.cursor,
      eof: pair.1.eof,
      error: pair.1.error,
      is_text_mode: pair.1.is_text_mode,
    })
  }
  self.next_fd = snap.next_fd
}

///|
fn vfs_mode_code(mode : VfsMode) -> Int {
  match mode {
    Read => 0
    Write => 1
    Append => 2
  }
}

///|
fn vfs_mode_from_code(code : Int) -> VfsMode {
  match code {
    0 => Read
    1 => Write
    2 => Append
    _ =>
      abort(
        "VfsSnapshot.restore: mode 编号越界（\{code}）——快照数据损坏",
      )
  }
}
