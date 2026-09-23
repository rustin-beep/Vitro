///| freed_logs：**有序数组 + 二分**。
///
/// 总计划 §「直接按目标架构实现（要点）」原文即"freed_logs 有序数组+二分"；
/// 勘察 §⑤ 5.5 给出同一结论并附了前提。
///
/// **为什么必须有序——这是正确性，不是性能偏好**（勘察 §1.6 原文）：
/// Rust 现版用 `BTreeMap<addr, info>` + `range(..end)` 的**降序探测**实现区间
/// 查询与裁剪（`core/state.rs:694-755`），算法依赖不变量「**块互不重叠 ⟹
/// addr 序即 end 序**」：
/// - `find_overlapping`：降序首个 `addr < end` 的条目，其 `end` 在全体中最大
///   ——`end ≤ 查询起点` 即无重叠，否则它就是重叠块（单次探测）；
/// - `remove_overlapping`：同向降序扫，遇 `l_end ≤ start` **提前 break**
///   （更小 addr 的条目 end 只会更小）。
///
/// 换成哈希容器不是"变慢"，而是**静默漏检 UAF**。因此本实现把"有序 + 不重叠"
/// 写成类型的不变量，并用 `MemoryMap::verify()` 做自检（勘察 §⑤ 5.5 的
/// "内存不变量自检作为 debug 断言"）。
///
/// **已知代价（诚实登记，非静默）**：数组的 `insert`/`remove` 是 O(n) 尾部搬移。
/// 稳态条目数有界（隔离预算 256KB ÷ 最小块 16B ≈ 16,387）。命中路径上
/// `remove_overlapping` 平均只动 0–2 条；但**旧块复用**（first-fit 命中低地址
/// 驱逐块）时被删条目的下标靠近 0，搬移量接近全长——这是本容器相对
/// `BTreeMap` 的唯一劣化点。若门 1 基准显示该路径成为热点，换 `@sorted_map`
/// （AVL，O(log n)）即可：**上述区间算法与全部红锚不变，只换容器**。
/// 选择数组的理由是快照路径——`freed_logs` 是 `VMSnapshot` 的一等字段
/// （`snapshot.rs:75`，"UAF 检测窗口，必须往返"），数组克隆是 O(n) 连续拷贝，
/// 树克隆是逐节点分配。

///|
/// 32 位无符号饱和加（对齐 Rust `u32::saturating_add`）。
///
/// 地址域实际 ≤ 1MB 不会溢出，但区间判定的**边界算术**必须与 Rust 同语义：
/// 现版用饱和加而非回绕，回绕会让"高地址 + 大 size"在判定中变成"低 end"，
/// 于是重叠判定反转为"不重叠"——静默漏检。
pub fn sat_u32_add(a : UInt, b : UInt) -> UInt {
  let s = a + b
  if s < a {
    0xFFFFFFFFU
  } else {
    s
  }
}

///|
/// 32 位无符号饱和减（对齐 Rust `u32::saturating_sub`）。
pub fn sat_u32_sub(a : UInt, b : UInt) -> UInt {
  if a < b {
    0U
  } else {
    a - b
  }
}

///|
/// 复制条目并替换 `addr` / `size`（不改其余元数据）。
///
/// 显式逐字段构造而非 `{ ..log, addr, size }`：本函数的三个调用点都在
/// "先读旧值、后覆写同一槽位"的路径上，显式列出全部字段可读性更好，
/// 也不依赖任何结构展开语义。
fn FreedRegionInfo::with_range(
  self : FreedRegionInfo,
  addr : UInt,
  size : Int,
) -> FreedRegionInfo {
  FreedRegionInfo::{
    addr,
    size,
    alloc_line: self.alloc_line,
    freed_line: self.freed_line,
    alloc_step: self.alloc_step,
    freed_step: self.freed_step,
  }
}

///|
/// 已释放块登记表（有序数组 + 二分）。
///
/// **不变量**：`entries` 按 `addr` **严格升序**，任意两条目**互不重叠**
/// （`a.end <= b.addr`），且每条 `size > 0`。写入只有 `insert` 与
/// `remove_overlapping` 两个入口，两者都维持该不变量。
pub struct FreedLogs {
  /// 按 addr 严格升序、互不重叠。私有无 `(all)`——外部只能经方法读写。
  entries : Array[FreedRegionInfo]
}

///|
/// 空表。
pub fn FreedLogs::new() -> FreedLogs {
  FreedLogs::{ entries: [], }
}

///|
/// 条目数。
pub fn FreedLogs::length(self : FreedLogs) -> Int {
  self.entries.length()
}

///|
/// 是否为空。
pub fn FreedLogs::is_empty(self : FreedLogs) -> Bool {
  self.entries.is_empty()
}

///|
/// 取第 `i` 条（升序；`0 <= i < length()`）。
pub fn FreedLogs::at(self : FreedLogs, i : Int) -> FreedRegionInfo {
  self.entries[i]
}

///|
/// 清空（整机重置用）。
pub fn FreedLogs::clear(self : FreedLogs) -> Unit {
  self.entries.clear()
}

///|
/// 升序快照（**独立副本**，供快照往返与诊断导出；后续对副本的改动不影响本表）。
pub fn FreedLogs::to_array(self : FreedLogs) -> Array[FreedRegionInfo] {
  let out : Array[FreedRegionInfo] = Array(capacity=self.entries.length())
  for e in self.entries {
    out.push(e)
  }
  out
}

///|
/// 二分下界：第一个 `addr >= x` 的下标；全小于 x 时返回 `length()`。
///
/// 这是本文件两个区间算法的共同原语——Rust 侧的对应物是
/// `BTreeMap::range(..end)` 的游标，此处以数组下标显式化。
fn FreedLogs::lower_bound(self : FreedLogs, x : UInt) -> Int {
  let mut lo = 0
  let mut hi = self.entries.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if self.entries[mid].addr < x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// 区间重叠查询：与 `[addr, addr + size)` 重叠的**任一**已释放记录。
///
/// 逐句同构 Rust `freed_logs_find_overlapping`（`state.rs:747-755`）：
/// 取"`addr < end`"的最大条目（`lower_bound(end) - 1`）——互不重叠 ⟹ 它的
/// `end` 在全体中最大；`end ≤ 查询起点` 则后续全部不重叠（`None`），
/// 否则它就是重叠块。
pub fn FreedLogs::find_overlapping(
  self : FreedLogs,
  addr : UInt,
  size : UInt,
) -> FreedRegionInfo? {
  let end = sat_u32_add(addr, size)
  let i = self.lower_bound(end) - 1
  if i < 0 {
    return None
  }
  let e = self.entries[i]
  if sat_u32_add(e.addr, e.size.reinterpret_as_uint()) > addr {
    Some(e)
  } else {
    None
  }
}

///|
/// 精确命中（Double-Free 拦截的输入；host 侧据此报 E3061）。
///
/// 注意口径与 `find_overlapping` 的区别：这里是"块**起点**恰为 addr"，
/// Rust 侧对应 `freed_logs.contains_key(&addr)`（`host/memory.rs:66`）。
pub fn FreedLogs::contains(self : FreedLogs, addr : UInt) -> Bool {
  let i = self.lower_bound(addr)
  i < self.entries.length() && self.entries[i].addr == addr
}

///|
/// 精确取条目（`addr` 恰为某条登记的起点）；`None` 表示无此登记。
///
/// 与 `contains` 同源（同一二分 + 同键判定），区别是返回值而非布尔——host 的
/// E3061 文案需要 `freed_line` / `alloc_line` 两个字段，光知道"命中"不够。
pub fn FreedLogs::get(self : FreedLogs, addr : UInt) -> FreedRegionInfo? {
  let i = self.lower_bound(addr)
  if i < self.entries.length() && self.entries[i].addr == addr {
    Some(self.entries[i])
  } else {
    None
  }
}

///|
/// 登记一条已释放块。
///
/// 同键覆盖且**保持原插入位**——对齐 `BTreeMap::insert` 语义。addr 唯一由
/// 调用方保证（Double-Free 拦截在先，`host/memory.rs:66-70`）。
pub fn FreedLogs::insert(self : FreedLogs, info : FreedRegionInfo) -> Unit {
  let i = self.lower_bound(info.addr)
  if i < self.entries.length() && self.entries[i].addr == info.addr {
    self.entries[i] = info
  } else {
    self.entries.insert(i, info)
  }
}

///|
/// 删除与 `[start, end)` 重叠的登记，**部分重叠时只裁剪重叠段**。
///
/// 语义照搬 Rust `freed_logs_remove_overlapping`（`state.rs:694-743`）：
/// - 完全被覆盖（`start <= log.addr && l_end <= end`）→ 整条删除；
/// - 前缀保留（`log.addr < start`）→ 原地缩 `size` 到 `[log.addr, start)`；
///   若同时有后缀（嵌套，`l_end > end`）→ 另插一条 `[end, l_end)`；
/// - 只剩后缀（`log.addr >= start`）→ **原地改键**为 `end`（数组有序性可证
///   保持：前驱 `addr < log.addr` 且其 end ≤ log.addr ≤ end；后继 addr ≥ l_end）。
///
/// 为什么必须精确裁剪（坑 10，`test_u213_freed_logs_partial_overlap_trimmed`）：
/// 旧实现按"重叠即整条删"。`free X(100)` 后 `malloc Y(60)` 复用前段，X 尾部
/// `[x+60, x+100)` 的 UAF 检测窗口随整条记录一起消失——**UAF 假阴性**。
pub fn FreedLogs::remove_overlapping(
  self : FreedLogs,
  start : UInt,
  end : UInt,
) -> Unit {
  let mut i = self.lower_bound(end) - 1
  while i >= 0 {
    let log = self.entries[i]
    let l_addr = log.addr
    let l_end = sat_u32_add(l_addr, log.size.reinterpret_as_uint())
    if l_end <= start {
      // 降序且互不重叠：更小 addr 的条目 end 只会更小 → 之后全部不重叠
      break
    }
    if start <= l_addr && l_end <= end {
      // 完全被覆盖 → 整条删除
      ignore(self.entries.remove(i))
    } else if l_addr < start {
      // 前缀保留 [l_addr, start)
      self.entries[i] = log.with_range(
        l_addr,
        (start - l_addr).reinterpret_as_int(),
      )
      if l_end > end {
        // 嵌套：后缀 [end, l_end) 另插一条，插在 i+1 保序（i 仍指前缀条目）
        self.entries.insert(
          i + 1,
          log.with_range(end, (l_end - end).reinterpret_as_int()),
        )
      }
    } else {
      // 只剩后缀 [end, l_end)：原地改键（保序由上文论证）
      self.entries[i] = log.with_range(end, (l_end - end).reinterpret_as_int())
    }
    i = i - 1
  }
}
