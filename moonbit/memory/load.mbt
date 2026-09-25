///| S6 执行层·内存域：**堆元数据快照（`MemorySnapshot` + `dump`/`load` 对偶）**
/// ——`VMSnapshot.restore` 的 memory 侧单点（S6 开工批登记未落地项，形状随
/// vm 片 `VMSnapshot`/`MemoryImage` 定形后落此）。
///
/// 设计对齐总计划 §5「Trap 回退改检查点+正向重放」与勘察 §5.2 的快照纪律：
/// - **单一出口**：restore 不走散装 setter（`set_region`/`set_heap_base`/
///   `set_quarantine_budget` 各自半装会留下中间态），一个 `load` 整体替换
///   全部元数据——与 `release` 单出口同款理由；
/// - **无索引重建义务**：regions 以 addr 为键的插入序 `Map`，回灌走 `set`
///   （快照侧 `dump` 吐出插入序，等键分支保持原位），没有 Rust 侧
///   `rebuild_region_index()` 的恢复调用义务（坑 6 的结构性消除）；
/// - **不碰载体**：本入口只装元数据；1MB 字节本体的快照往返在
///   `Memory::restore_raw`（与元数据装载各自独立，勘察 §5.1 分离纪律）。
///
/// `quarantine` 的序约定：**数组下标 0 = 队首（最老块）**，与 `@deque.Deque`
/// 的 FIFO 语义一致（`quarantine_at(0)` 同口径）。`quarantine_budget` 随快照
/// 往返（隔离区三件套口径——门 3 验收锚，Rust 现状照搬；「会话配置是否应
/// 随快照」的口径争议见勘察附录 A-5，未裁前不动）。

///|
/// 堆元数据快照（全字段；region 的 `refcount`〔CS 批 ARC 预留〕随条目自动随行）。
pub(all) struct MemorySnapshot {
  regions : Array[(UInt, MemoryRegionData)]
  free_list : Array[FreeBlock]
  quarantine : Array[FreeBlock]
  quarantine_bytes : Int
  quarantine_budget : Int
  heap_base : UInt
  heap_offset : UInt
  alloc_counter : Int
  freed : Array[FreedRegionInfo]
} derive(Eq, Debug)

///|
/// 抓快照（`dump`）：导出全部元数据的**深拷贝**（条目 struct 逐一复制，
/// 不与运行态共享可变结构——拷贝即快照，时点明确）。
pub fn MemoryMap::dump(self : MemoryMap) -> MemorySnapshot {
  let regions : Array[(UInt, MemoryRegionData)] = Array(
    capacity=self.regions.size(),
  )
  for addr, r in self.regions {
    regions.push(
      (
        addr,
        MemoryRegionData::{
          size: r.size,
          name: r.name,
          ty: r.ty,
          is_heap: r.is_heap,
          is_freed: r.is_freed,
          alloc_line: r.alloc_line,
          alloc_by: r.alloc_by,
          kind: r.kind,
          refcount: r.refcount,
        },
      ),
    )
  }
  let free_list : Array[FreeBlock] = Array(capacity=self.free_list.length())
  for b in self.free_list {
    free_list.push(FreeBlock::{ addr: b.addr, size: b.size, })
  }
  let quarantine : Array[FreeBlock] = Array(capacity=self.quarantine.length())
  for i = 0; i < self.quarantine.length(); i = i + 1 {
    let b = self.quarantine[i]
    quarantine.push(FreeBlock::{ addr: b.addr, size: b.size, })
  }
  let freed : Array[FreedRegionInfo] = Array(capacity=self.freed_logs.length())
  for i = 0; i < self.freed_logs.length(); i = i + 1 {
    let e = self.freed_logs.at(i)
    freed.push(FreedRegionInfo::{
      addr: e.addr,
      size: e.size,
      alloc_line: e.alloc_line,
      freed_line: e.freed_line,
      alloc_step: e.alloc_step,
      freed_step: e.freed_step,
    })
  }
  MemorySnapshot::{
    regions,
    free_list,
    quarantine,
    quarantine_bytes: self.quarantine_bytes,
    quarantine_budget: self.quarantine_budget,
    heap_base: self.heap_base,
    heap_offset: self.heap_offset,
    alloc_counter: self.alloc_counter,
    freed,
  }
}

///|
/// 快照整装（`load`）：以快照**整体替换**堆元数据。
///
/// 先清空再回灌——`regions.clear()` 后按快照插入序逐条 `set`，等键覆盖
/// 语义与运行时 `register_alloc` 一致。装后即检（fail loud）：`verify` 的
/// 不变量（freed_logs 升序不重叠 / quarantine_bytes 与队列和一致 /
/// free_list 不重叠）在合法快照上恒过，`Err` 只可能来自损坏输入——当场
/// 炸，不带病运行。
pub fn MemoryMap::load(self : MemoryMap, snap : MemorySnapshot) -> Unit {
  self.regions.clear()
  for pair in snap.regions {
    self.regions.set(pair.0, pair.1)
  }
  self.free_list.clear()
  for block in snap.free_list {
    self.free_list.push(FreeBlock::{ addr: block.addr, size: block.size, })
  }
  self.quarantine.clear()
  for block in snap.quarantine {
    self.quarantine.push_back(FreeBlock::{ addr: block.addr, size: block.size, })
  }
  self.quarantine_bytes = snap.quarantine_bytes
  self.quarantine_budget = snap.quarantine_budget
  self.heap_base = snap.heap_base
  self.heap_offset = snap.heap_offset
  self.alloc_counter = snap.alloc_counter
  self.freed_logs.load_entries(snap.freed)
  match self.verify() {
    Ok(_) => ()
    Err(msg) => abort("MemoryMap::load: 快照不变量违例——\{msg}")
  }
}

///|
/// freed_logs 批量装载：以升序数组**整体替换**登记表（快照恢复单点）。
///
/// 要求 `items` 按 `addr` 严格升序且互不重叠（快照侧保证；violation 是
/// 调用方 bug）——灌入后直接是二分查找的合法形态，无需重排。
pub fn FreedLogs::load_entries(
  self : FreedLogs,
  items : Array[FreedRegionInfo],
) -> Unit {
  let mut prev_addr : UInt = 0
  let mut first = true
  for item in items {
    // fail loud：升序契约违反即中止（乱序灌入会让二分静默漏检 UAF）
    if first {
      first = false
    } else if item.addr <= prev_addr {
      abort(
        "FreedLogs::load_entries: 乱序或重复 addr（\{item.addr} <= \{prev_addr}）——快照数据损坏",
      )
    }
    prev_addr = item.addr
  }
  self.entries.clear()
  for item in items {
    self.entries.push(FreedRegionInfo::{
      addr: item.addr,
      size: item.size,
      alloc_line: item.alloc_line,
      freed_line: item.freed_line,
      alloc_step: item.alloc_step,
      freed_step: item.freed_step,
    })
  }
}
