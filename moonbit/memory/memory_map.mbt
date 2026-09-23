///| S6 执行层·内存域：**堆内存元数据（`MemoryMap`）**。
///
/// 与 Rust 的对应关系：本类型合并了 `vitro_runtime::MemoryState`
/// （regions / free_list / quarantine / 堆游标 / 统计，`memory_state.rs`）与
/// `vitro_vm` 侧那些"只操作元数据"的片段（freed_logs 的区间算法原本长在
/// `VitroVM` 上，`core/state.rs:694-755`）。**不碰字节载体**——载体在
/// `carrier.mbt` 的 `Memory`，两边各自可独立测试（勘察 §5.1）。
///
/// **堆模型（2026-09-11 决议 + 堆有界隔离决议 §1/§3，逐条照搬）**：
/// - `allocate_raw`：先按需驱逐隔离区 → `free_list` first-fit 复用 → 否则
///   bump 推进 `heap_offset`；`heap_offset` **单调不减**；
/// - `release`：块进 FIFO 隔离区（地址在隔离期内不复用），超预算时 FIFO
///   驱逐最老块归还 `free_list`；
/// - 分水岭：合法 churn 的隔离占用稳定在预算内（最老块持续被驱逐复用，堆顶
///   不推进，无限可跑）；只分配不释放的 leak 根本不进隔离区，由 bump 推进
///   直至撞 1MB 墙（教学信号）。
///
/// **相对 Rust 的结构性收紧（勘察 §⑤/坑 6）**：区域条目以 **addr 为键**
/// 存在插入序 `Map` 里，"同 addr 两条目""平行索引与 regions 失配"两族缺陷
/// 不可表达；freed_logs 走 `FreedLogs`（有序数组 + 二分），
/// `remove_overlapping` 的降序提前 break 语义逐句照搬。

///|
/// 堆内存元数据。
pub struct MemoryMap {
  /// **addr → 堆区域条目**。core 的 `Map` 即插入序哈希表（`linked_hash_map.mbt`）：
  /// 迭代序 = 插入序（与 Rust `Vec<MemoryRegionData>` 的导出口径一致），
  /// 且既有键 `set` **保持原插入位**（`set_with_hash` 的等键分支只写 value）。
  /// 因此这里既没有 `region_index` 平行索引，也没有 `rebuild_region_index()`
  /// 的恢复义务——坑 6 点名的失配面归零。
  regions : Map[UInt, MemoryRegionData]
  /// 可复用空闲块（来源：隔离区驱逐归还）。`allocate_raw` 在此做 first-fit。
  free_list : Array[FreeBlock]
  /// 隔离区：已 free 但地址暂不复用的块，FIFO（队首最老）。
  quarantine : @deque.Deque[FreeBlock]
  /// 隔离区当前占用字节数（与 `quarantine` 同步维护，避免每次求和）。
  mut quarantine_bytes : Int
  /// 隔离区字节预算，超预算触发 FIFO 驱逐。**会话级配置**（Rust 侧
  /// `vitro_set_quarantine_budget` 直接映射本字段）。
  mut quarantine_budget : Int
  /// 动态堆起点（R1 ①）：由全局数据上界与 argv 占用决定，运行重置时经
  /// `set_heap_base` 落位；统计口径统一以它为基准。
  mut heap_base : UInt
  /// bump 游标（下一个未分配地址）。
  mut heap_offset : UInt
  /// 已登记分配次数（`heap_{n}` 命名用）。
  mut alloc_counter : Int
  /// 已释放块登记（UAF / Double-Free 检测窗口）。
  freed_logs : FreedLogs
}

///|
/// 空堆（`heap_base == heap_offset == HEAP_START`，与 Rust `Default` 一致）。
pub fn MemoryMap::new() -> MemoryMap {
  MemoryMap::{
    regions: Map([]),
    free_list: [],
    quarantine: @deque.Deque([]),
    quarantine_bytes: 0,
    quarantine_budget: DEFAULT_QUARANTINE_BUDGET,
    heap_base: @bytecode.HEAP_START,
    heap_offset: @bytecode.HEAP_START,
    alloc_counter: 0,
    freed_logs: FreedLogs::new(),
  }
}

///|
/// 设置本次运行的堆起点（R1 ①）。
///
/// `heap_base` 与 `heap_offset` **必须同步落位**：Rust `set_heap_base`
/// （`memory_state.rs:187-190`）是唯一入口，禁止各自直接写字段造成口径分裂
/// （统计用 base、bump 用 offset，两者一旦分叉，`total_heap` 会算成负值）。
pub fn MemoryMap::set_heap_base(self : MemoryMap, base : UInt) -> Unit {
  self.heap_base = base
  self.heap_offset = base
}

///|
/// 本次运行的堆起点。
pub fn MemoryMap::heap_base(self : MemoryMap) -> UInt {
  self.heap_base
}

///|
/// bump 游标（统计通道的口径基准之一）。
pub fn MemoryMap::heap_offset(self : MemoryMap) -> UInt {
  self.heap_offset
}

///|
/// 已登记分配次数。
pub fn MemoryMap::alloc_counter(self : MemoryMap) -> Int {
  self.alloc_counter
}

///|
/// 隔离区当前占用字节数。
pub fn MemoryMap::quarantine_bytes(self : MemoryMap) -> Int {
  self.quarantine_bytes
}

///|
/// 隔离区字节预算。
pub fn MemoryMap::quarantine_budget(self : MemoryMap) -> Int {
  self.quarantine_budget
}

///|
/// 设置隔离预算（会话级配置；0 = free 后立即可复用）。
///
/// **不变量**：改小预算时**不立即驱逐**——驱逐只在 `allocate_raw` 入口按需
/// 发生（Rust 同款）。这保证了"设预算"这个纯配置动作没有副作用顺序依赖。
pub fn MemoryMap::set_quarantine_budget(self : MemoryMap, budget : Int) -> Unit {
  self.quarantine_budget = budget
}

///|
/// 隔离区块数。
pub fn MemoryMap::quarantine_len(self : MemoryMap) -> Int {
  self.quarantine.length()
}

///|
/// 隔离区第 `i` 个块（`0` = 队首 = 最老）。
pub fn MemoryMap::quarantine_at(self : MemoryMap, i : Int) -> FreeBlock {
  self.quarantine[i]
}

///|
/// 空闲块数。
pub fn MemoryMap::free_list_len(self : MemoryMap) -> Int {
  self.free_list.length()
}

///|
/// 空闲块第 `i` 个（顺序 = first-fit 扫描序，不保证 addr 有序）。
pub fn MemoryMap::free_list_at(self : MemoryMap, i : Int) -> FreeBlock {
  self.free_list[i]
}

///|
/// 已登记区域条目数。
pub fn MemoryMap::regions_len(self : MemoryMap) -> Int {
  self.regions.length()
}

///|
/// 按 addr 取区域条目（O(1)）。**只看 addr，不看 `is_freed`**——语义判定
/// （复用要求 freed、释放要求 live）在调用方做（Rust `find_region_mut`
/// 的注释同款口径，`memory_state.rs:204-206`）。
pub fn MemoryMap::region(self : MemoryMap, addr : UInt) -> MemoryRegionData? {
  self.regions.get(addr)
}

///|
/// 是否存在该 addr 的条目。
pub fn MemoryMap::has_region(self : MemoryMap, addr : UInt) -> Bool {
  self.regions.contains(addr)
}

///|
/// 区域条目列表（**插入序**，与 Rust `regions` Vec 的导出口径一致）。
pub fn MemoryMap::regions_to_array(
  self : MemoryMap,
) -> Array[(UInt, MemoryRegionData)] {
  let out : Array[(UInt, MemoryRegionData)] = Array(
    capacity=self.regions.length(),
  )
  for addr, r in self.regions {
    out.push((addr, r))
  }
  out
}

///|
/// 区域条目的唯一写入入口（追加或覆写；既有键**保持原插入位**）。
///
/// **为什么只有一个入口就够**：条目以 addr 为键，同一 addr 只有一个槽位，
/// "复用走了 push 分支"这类错误（坑 6 的根因）在结构上无法写出。
/// Rust 侧需要 `push_region` / `find_region_mut` / `rebuild_region_index`
/// 三件套 + 不变量注释 + `verify_region_index()` 的原因，正是因为它是
/// `Vec` + 平行索引。
pub fn MemoryMap::set_region(
  self : MemoryMap,
  addr : UInt,
  data : MemoryRegionData,
) -> Unit {
  self.regions.set(addr, data)
}

///|
/// 登记一次分配（`malloc` / `calloc` / `realloc` 三路共用的条目写入）。
///
/// 语义照搬 Rust（`host/memory.rs:31-56` malloc / `:284-308` realloc /
/// `:339-364` calloc 三处同构代码）：
/// - 该 addr 已有条目且 **`is_freed`** → 复用：复位 `is_freed`、`size` 更新为
///   本次请求大小，再刷新 `alloc_line` / `alloc_by`；
/// - 已有条目且**未释放** → 只刷新 `alloc_line` / `alloc_by`（`size` 不动）；
/// - 无条目 → 追加，`alloc_counter` 自增；`auto_name` 决定是否取
///   `heap_{n}` / `ty="int"`（`malloc`/`calloc` 取，`realloc` 的新块不取）。
pub fn MemoryMap::register_alloc(
  self : MemoryMap,
  addr : UInt,
  size : Int,
  alloc_line : Int,
  alloc_by : String,
  auto_name : Bool,
) -> Unit {
  match self.regions.get(addr) {
    Some(r) => {
      if r.is_freed {
        r.is_freed = false
        r.size = size
      }
      r.alloc_line = alloc_line
      r.alloc_by = alloc_by
      self.regions.set(addr, r)
    }
    None => {
      let n = self.alloc_counter + 1
      self.alloc_counter = n
      let name = if auto_name { "heap_\{n}" } else { "" }
      let ty = if auto_name { "int" } else { "" }
      self.regions.set(
        addr,
        MemoryRegionData::heap_block(size, name, ty, alloc_line, alloc_by),
      )
    }
  }
}

///|
/// 释放 `addr` 对应的已分配堆区域——**三条释放路径的唯一出口**。
///
/// Rust 侧同一语义在三处各写一遍（`host_free` `:74-96`、`realloc(ptr,0)`
/// `:166-192`、`VitroVM::free_memory` `:637-671`），"堆有界隔离决议 §3 统一
/// 进 FIFO 隔离区"要收掉的正是这种发散。本函数把三步原子完成：
/// 1. 条目 `is_freed` 置位（找不到或已释放 → `None`，由调用方走无效 free 诊断）；
/// 2. 登记 freed_logs（`size` 按 4 字节向上对齐——UAF 检测窗口的物理范围）；
/// 3. 块进 FIFO 隔离区。
///
/// 成功返回**对齐后的块大小**（调用方据此记账），失败返回 `None`。
/// `freed_line` / `freed_step` 由调用方给（它们来自 VM 执行状态，不在本包）。
pub fn MemoryMap::release(
  self : MemoryMap,
  addr : UInt,
  freed_line : Int,
  freed_step : Int,
) -> Int? {
  match self.regions.get(addr) {
    Some(r) => {
      if r.is_freed {
        return None
      }
      r.is_freed = true
      self.regions.set(addr, r)
      let aligned = @bytecode.align4(r.size.reinterpret_as_uint()).reinterpret_as_int()
      self.freed_logs.insert(FreedRegionInfo::{
        addr,
        size: aligned,
        alloc_line: r.alloc_line,
        freed_line,
        alloc_step: 0,
        freed_step,
      })
      self.release_to_quarantine(FreeBlock::{ addr, size: aligned, })
      Some(aligned)
    }
    None => None
  }
}

///|
/// 块进入 FIFO 隔离区（free 路径的私有出口，地址在隔离期内不复用）。
fn MemoryMap::release_to_quarantine(
  self : MemoryMap,
  block : FreeBlock,
) -> Unit {
  self.quarantine_bytes = self.quarantine_bytes + block.size
  self.quarantine.push_back(block)
}

///|
/// 隔离区超预算时按 FIFO 驱逐最老块至 `free_list`，直至回到预算内。
fn MemoryMap::evict_quarantine(self : MemoryMap) -> Unit {
  if self.quarantine_bytes <= self.quarantine_budget {
    return
  }
  while self.quarantine_bytes > self.quarantine_budget {
    match self.quarantine.pop_front() {
      Some(block) => {
        self.quarantine_bytes = self.quarantine_bytes - block.size
        self.free_list.push(block)
      }
      None => break
    }
  }
  // 合并相邻块，提升后续 first-fit 命中率（仅驱逐路径的代价）
  self.merge_free_list()
}

///|
/// 合并 `free_list` 中地址相邻的空闲块。
///
/// 用"累加器 + 游标"而非 Rust 的 `last_mut().size += ...`：后者依赖"取到的
/// 元素句柄可原地改动"，逐字段复制语义下会静默丢累计值。这里把待定块拆成
/// `(addr, size)` 两个标量游标，合并结果显式 push，与语言语义无关。
fn MemoryMap::merge_free_list(self : MemoryMap) -> Unit {
  self.free_list.sort_by(fn(a, b) { a.addr.compare(b.addr) })
  let merged : Array[FreeBlock] = []
  let mut has_last = false
  let mut last_addr : UInt = 0U
  let mut last_size : Int = 0
  for block in self.free_list {
    if has_last &&
      last_addr.to_uint64() + last_size.to_uint64() == block.addr.to_uint64() {
      last_size = last_size + block.size
    } else {
      if has_last {
        merged.push(FreeBlock::{ addr: last_addr, size: last_size, })
      }
      has_last = true
      last_addr = block.addr
      last_size = block.size
    }
  }
  if has_last {
    merged.push(FreeBlock::{ addr: last_addr, size: last_size, })
  }
  self.free_list.clear()
  for b in merged {
    self.free_list.push(b)
  }
}

///|
/// `free_list` first-fit 取块；块大于请求时**切分**，余量留在表中。
fn MemoryMap::take_from_free_list(
  self : MemoryMap,
  aligned_size : UInt,
) -> UInt? {
  let mut idx = -1
  for i = 0; i < self.free_list.length(); i = i + 1 {
    if self.free_list[i].size.reinterpret_as_uint() >= aligned_size {
      idx = i
      break
    }
  }
  if idx < 0 {
    return None
  }
  let b = self.free_list[idx]
  if b.size.reinterpret_as_uint() > aligned_size {
    self.free_list[idx] = FreeBlock::{
      addr: b.addr + aligned_size,
      size: b.size - aligned_size.reinterpret_as_int(),
    }
  } else {
    ignore(self.free_list.remove(idx))
  }
  Some(b.addr)
}

///|
/// 分配 `aligned_size` 字节（决议 §1/§3 的 bump + 有界隔离）。
///
/// 顺序与 Rust `allocate_raw`（`memory_state.rs:257-272`）逐句一致：
/// 1. 隔离区超预算 → FIFO 驱逐最老块归还 `free_list`；
/// 2. `free_list` first-fit 复用（来源见 1）；
/// 3. 否则 bump 推进 `heap_offset`——leak 路径由此单调推进直至撞内存墙。
///
/// 成功返回地址；越过 `mem_limit` 返回 `None`（调用方据此报堆耗尽并返回
/// NULL——**不 trap**，C 标准要求分配失败返回 NULL，Clang 同）。
pub fn MemoryMap::allocate_raw(
  self : MemoryMap,
  aligned_size : UInt,
  mem_limit : UInt,
) -> UInt? {
  if aligned_size == 0U {
    return Some(0U)
  }
  self.evict_quarantine()
  match self.take_from_free_list(aligned_size) {
    Some(addr) => return Some(addr)
    None => ()
  }
  let addr = self.heap_offset
  let new_offset = addr.to_uint64() + aligned_size.to_uint64()
  if new_offset > mem_limit.to_uint64() || new_offset > 0xFFFFFFFFUL {
    return None
  }
  self.heap_offset = new_offset.to_uint()
  Some(addr)
}

// ── freed_logs 查询面（host / vm 的诊断输入）────────────────────────────────

///|
/// 已释放登记条目数。
pub fn MemoryMap::freed_logs_len(self : MemoryMap) -> Int {
  self.freed_logs.length()
}

///|
/// 第 `i` 条已释放登记（升序）。
pub fn MemoryMap::freed_logs_at(self : MemoryMap, i : Int) -> FreedRegionInfo {
  self.freed_logs.at(i)
}

///|
/// 该 addr **精确**是某条已释放登记的起点（Double-Free 拦截输入，E3061）。

///|
/// 按 addr 精确取已释放登记（E3061 文案需要 `freed_line` / `alloc_line`）。
pub fn MemoryMap::freed_logs_get(
  self : MemoryMap,
  addr : UInt,
) -> FreedRegionInfo? {
  self.freed_logs.get(addr)
}

///|
/// 查找**存活**区域中严格包含 `addr` 的条目（`addr` 不等于块起点）——
/// host 的无效 free 诊断（E3027「内部地址」）的输入。
///
/// 返回 `(块起始, 条目)`；顺序 = 插入序（与 Rust `regions.iter().find` 同序），
/// O(n) 线性扫（诊断路径，非热路径）。
pub fn MemoryMap::find_live_region_containing(
  self : MemoryMap,
  addr : UInt,
) -> (UInt, MemoryRegionData)? {
  for pa in self.regions_to_array() {
    let a = pa.0
    let r = pa.1
    if !r.is_freed && addr > a && addr < a + r.size.reinterpret_as_uint() {
      return Some((a, r))
    }
  }
  None
}

///|
pub fn MemoryMap::freed_logs_contains(self : MemoryMap, addr : UInt) -> Bool {
  self.freed_logs.contains(addr)
}

///|
/// 区间重叠查询（UAF 检测输入，E3060）。
pub fn MemoryMap::freed_logs_find_overlapping(
  self : MemoryMap,
  addr : UInt,
  size : UInt,
) -> FreedRegionInfo? {
  self.freed_logs.find_overlapping(addr, size)
}

///|
/// 删除与 `[start, end)` 重叠的已释放登记（新分配合法覆盖该区间时调用）。
///
/// 调用时机是硬约束：**必须在写入新分配的内存之前**，否则紧随的写入会
/// 误报 Use-After-Free（Rust `host/memory.rs:229-232` 有明文注释）。
pub fn MemoryMap::freed_logs_remove_overlapping(
  self : MemoryMap,
  start : UInt,
  end : UInt,
) -> Unit {
  self.freed_logs.remove_overlapping(start, end)
}

// ── 统计与自检 ──────────────────────────────────────────────────────────────

///|
/// 当前已分配但未释放的堆内存总量（字节）。
pub fn MemoryMap::total_allocated(self : MemoryMap) -> Int {
  let mut sum = 0
  for _, r in self.regions {
    if !r.is_freed {
      sum = sum + r.size
    }
  }
  sum
}

///|
/// 外部碎片（`free_list` 总和，字节）。
pub fn MemoryMap::total_fragmented(self : MemoryMap) -> Int {
  let mut sum = 0
  for b in self.free_list {
    sum = sum + b.size
  }
  sum
}

///|
/// 碎片率（0~100）。`heap_total == 0` 时为 0（Rust 同）。
pub fn MemoryMap::fragmentation_rate(self : MemoryMap) -> Int {
  let heap_total = self.heap_offset.to_uint64() - self.heap_base.to_uint64()
  if heap_total == 0UL {
    return 0
  }
  let rate = self.total_fragmented().to_uint64() * 100UL / heap_total
  if rate > 100UL {
    100
  } else {
    rate.to_int()
  }
}

///|
/// 构建教学用堆统计快照（`HeapStatsData` 口径照搬 Rust `build_heap_stats`）。
pub fn MemoryMap::build_heap_stats(self : MemoryMap) -> HeapStatsData {
  HeapStatsData::{
    heap_base: self.heap_base.reinterpret_as_int(),
    total_heap: (self.heap_offset.to_uint64() - self.heap_base.to_uint64()).to_int(),
    allocated: self.total_allocated(),
    fragmented: self.total_fragmented(),
    fragmentation_rate: self.fragmentation_rate(),
  }
}

///|
/// 内存不变量自检（调试 / 测试用；勘察 §⑤ 5.5「把内存不变量自检作为
/// debug 断言」——迁移期最高风险正是"元数据内部失配"）。
///
/// 检查项：
/// 1. `freed_logs` 严格升序、互不重叠、`size > 0`；
/// 2. `quarantine_bytes` == 队列内块大小之和（且非负）；
/// 3. `free_list` 内块 `size > 0` 且两两不重叠；
/// 4. `heap_offset ∈ [heap_base, MEM_SIZE]`；
/// 5. `regions` 的键唯一（`Map` 结构保证，此处只做下界健全性确认）。
pub fn MemoryMap::verify(self : MemoryMap) -> Result[Unit, String] {
  let n = self.freed_logs.length()
  let mut prev_end : UInt64 = 0UL
  for i = 0; i < n; i = i + 1 {
    let e = self.freed_logs.at(i)
    if e.size <= 0 {
      return Err("freed_logs[\{i}] size 非正：\{e.size}")
    }
    let addr = e.addr.to_uint64()
    if i > 0 && addr < prev_end {
      return Err("freed_logs 失序或重叠（下标 \{i}）")
    }
    prev_end = addr + e.size.to_uint64()
  }
  let mut qsum = 0
  for i = 0; i < self.quarantine.length(); i = i + 1 {
    let b = self.quarantine[i]
    if b.size <= 0 {
      return Err("quarantine[\{i}] size 非正：\{b.size}")
    }
    qsum = qsum + b.size
  }
  if qsum != self.quarantine_bytes {
    return Err("quarantine_bytes \{self.quarantine_bytes} != 队列和 \{qsum}")
  }
  let fl : Array[FreeBlock] = Array(capacity=self.free_list.length())
  for b in self.free_list {
    fl.push(b)
  }
  fl.sort_by(fn(a, b) { a.addr.compare(b.addr) })
  let mut fl_end : UInt64 = 0UL
  for i = 0; i < fl.length(); i = i + 1 {
    let b = fl[i]
    if b.size <= 0 {
      return Err("free_list[\{i}] size 非正：\{b.size}")
    }
    if i > 0 && b.addr.to_uint64() < fl_end {
      return Err("free_list 块重叠（下标 \{i}）")
    }
    fl_end = b.addr.to_uint64() + b.size.to_uint64()
  }
  if self.heap_offset < self.heap_base {
    return Err("heap_offset < heap_base（口径分裂）")
  }
  if self.heap_offset.to_uint64() > @bytecode.MEM_SIZE.to_uint64() {
    return Err("heap_offset 越过 MEM_SIZE")
  }
  if self.heap_base < @bytecode.HEAP_START {
    return Err("heap_base 低于静态堆起点 HEAP_START")
  }
  // 区域条目的有效性：地址必须落在 NULL 陷阱区之上、size 必须为正。
  //
  // **这条检查是有来历的**：S6 host 批实测发现 `calloc` 的尺寸链溢出会让
  // `align4` 回绕成 0，`allocate_raw(0)` 短路成功，于是登记一条 `addr = 0`、
  // `size = -1` 的垃圾条目（Rust 侧同形，见 host 包 `host_calloc` 的缺陷登记）。
  // 自检吃这条，把"元数据被静默写坏"变成可断言事实。
  for pa in self.regions_to_array() {
    let a = pa.0
    let r = pa.1
    if a < @bytecode.NULL_TRAP_SIZE {
      return Err("区域条目落在 NULL 陷阱区（addr \{a}）")
    }
    if r.size <= 0 {
      return Err("区域条目 size 非正（addr \{a}，size \{r.size}）")
    }
  }
  Ok(())
}

// ── 受检访问的判定侧（四步链的 1–3 级）──────────────────────────────────────

///|
/// 受检访问的**唯一判定入口**：NULL 陷阱区 → 上界 → UAF。
///
/// 现版 Rust 把这三步复制在 9 个访问器里（`core/memory.rs:83-165`），
/// `check_mem_access` 与 `check_uaf` 两段各自被调；勘察 §5.1 建议"合并为
/// 单一入口"，§9.2 约束 #1 把结论钉成结构要求（"`vitro_host` 不得直接访问
/// 字节载体"）。本函数 + `Memory` 的 priv 字节字段共同实现该约束：**包外
/// 拿不到裸字节，也没有第二条判定路径**。
///
/// 第 4 级（脏页标记）在 `Memory` 的写路径上紧跟本函数之后——它是"记账"而非
/// "判定"，失败时不该发生，故不放进本函数。
///
/// **与 Rust 的两处有意差异（加固，非偏好）**：
/// 1. 上界判定用 `UInt64` 提升比较（Rust 同：`addr as u64 + size as u64`），
///    避免 32 位回绕把越界判成合法；
/// 2. 现版 `read_memory_to`（`core/memory.rs:54-61`）**只查 NULL 与上界、
///    不查 UAF**，是"同名访问器检查强度不一致"的存量漏网（§1.6 表格已列出）。
///    本实现所有读写走同一链，该漏网结构性关闭——行为差异是"该 trap 的现在
///    会 trap"，登记在案。
pub fn MemoryMap::check_access(
  self : MemoryMap,
  addr : UInt,
  size : UInt,
  kind : AccessKind,
) -> Result[Unit, MemFault] {
  if addr < @bytecode.NULL_TRAP_SIZE {
    return Err(MemFault::NullDeref(addr, kind))
  }
  if addr.to_uint64() + size.to_uint64() > @bytecode.MEM_SIZE.to_uint64() {
    return Err(MemFault::OutOfBounds(addr, size))
  }
  match self.freed_logs.find_overlapping(addr, size) {
    Some(info) => Err(MemFault::UseAfterFree(info, kind))
    None => Ok(())
  }
}
