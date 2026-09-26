///| S6 内存域白盒锚点（`vitro/engine/memory`）。
///
/// **锚点来源**：Rust 冻结区已有的红锚测试逐条照搬（勘察 §2.2 判据可搬清单），
/// 因为它们是"容器/算法换实现后必须重跑"的那一类：
/// - 坑 10 `test_u213_freed_logs_partial_overlap_trimmed`（区间语义，换容器最易丢）；
/// - 坑 6 `test_u22_realloc_reuse_no_duplicate_entries`（元数据唯一性）；
/// - 坑 7 隔离区三语义：`test_heap_uaf_within_quarantine_window_detected`、
///   `test_heap_double_free_within_quarantine_window_detected`（其内存侧）、
///   `test_u22_churn_steady_state_quarantine_window_alive`、
///   `test_u22_reuse_resets_metadata_and_clears_freed_log`、
///   `test_u22_churn_leak_count_and_no_duplicate_entries`；
/// - 墙与 churn 上界：`test_heap_1mb_wall_returns_null_with_teaching_hint`、
///   `test_heap_churn_beyond_quarantine_budget_no_wall`。
///
/// **本包不含 host**（host 是 S6 后续批），故这些锚以"显式列出 host 的调用
/// 次序"的方式驱动 `MemoryMap`——下面的 `alloc` / `free` 两个辅助函数就是
/// `host/memory.rs` 的内存侧最小复现，次序与 Rust 逐行对应。

///|
/// `host_malloc` 的内存侧最小复现（`host/memory.rs:5-58` 的次序）。
fn alloc(
  map : MemoryMap,
  size : Int,
  alloc_by : String,
  auto_name : Bool,
) -> UInt {
  let aligned = @bytecode.align4(size.reinterpret_as_uint())
  let addr = match map.allocate_raw(aligned, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => return 0U
  }
  map.register_alloc(addr, size, 1, alloc_by, auto_name)
  // 必须在写入新分配的内存之前清理（Rust `host/memory.rs:229-232` 明文）
  map.freed_logs_remove_overlapping(addr, addr + aligned)
  addr
}

///|
/// `host_free` 的内存侧最小复现（Double-Free 拦截在前，`host/memory.rs:60-97`）。
fn free(map : MemoryMap, addr : UInt) -> Bool {
  if map.freed_logs_contains(addr) {
    return false
  }
  match map.release(addr, 1, 1) {
    Some(_) => true
    None => false
  }
}

///|
/// 常量对账锚（`layout.mbt` 的派生量与 L6 单源的算术一致性）。
///
/// 硬编码真值 + 派生表达式双向锚：`DEFAULT_QUARANTINE_BUDGET` 的字面量
/// `1024 * 1024 / 4 = 262144` 必须同时等于 `MEM_SIZE / 4`
/// （Rust `memory_state.rs:30` `(MEM_SIZE / 4) as i32`）——任一侧被改而另一侧
/// 未同步，本锚即红。
test "layout_accounting_anchors" {
  assert_eq(PAGE_SIZE * PAGE_COUNT, @bytecode.MEM_SIZE.reinterpret_as_int())
  assert_eq(DIRTY_WORD_COUNT * 64, PAGE_COUNT)
  assert_eq(DEFAULT_QUARANTINE_BUDGET, 262144)
  assert_eq(
    DEFAULT_QUARANTINE_BUDGET * 4,
    @bytecode.MEM_SIZE.reinterpret_as_int(),
  )
  assert_eq(1 << PAGE_SHIFT, PAGE_SIZE)
}

// ── freed_logs：区间语义（坑 10）────────────────────────────────────────────

///|
/// 坑 10 红锚：**部分重叠必须精确裁剪**。
///
/// `free X(size=100)` 后 `malloc Y(size=60)` 复用 X 的前 60 字节——旧记录
/// `[x, x+100)` 与新块 `[x, x+60)` 部分重叠。整条删除（修复前行为）会让
/// X 尾部 `[x+60, x+100)` 的 UAF 检测窗口消失 = **假阴性**。
test "freed_logs_partial_overlap_trimmed" {
  let map = MemoryMap::new()
  map.set_quarantine_budget(0)
  let x = alloc(map, 100, "malloc", true)
  assert_true(x != 0U)
  assert_true(free(map, x))
  let y = alloc(map, 60, "malloc", true)
  assert_eq(
    y,
    x,
    msg="预算 0 → free 立即进 free_list，first-fit 应复用 x 的起点",
  )
  // X 尾部 [x+60, x+100) 必须仍被某条登记完整覆盖（检测窗口的物理范围）
  let mut has_tail = false
  for i = 0; i < map.freed_logs_len(); i = i + 1 {
    let l = map.freed_logs_at(i)
    let l_end = l.addr + l.size.reinterpret_as_uint()
    if l.addr <= x + 60U && l_end >= x + 100U {
      has_tail = true
    }
  }
  assert_true(
    has_tail,
    msg="未复用尾部 [x+60, x+100) 必须保留（整条删除 = UAF 假阴性）",
  )
  // 原整条记录不得原样保留（复用段 [x, x+60) 已合法覆盖）
  let mut has_full = false
  for i = 0; i < map.freed_logs_len(); i = i + 1 {
    let l = map.freed_logs_at(i)
    if l.addr == x && l.size == 100 {
      has_full = true
    }
  }
  assert_false(has_full, msg="原整条记录不应原样保留")
  // 尾部窗口必须真的会拒绝访问（检测窗口不只是"账上有"，要能拦住）
  match map.check_access(x + 80U, 4U, AccessKind::Write) {
    Err(MemFault::UseAfterFree(_, _)) => ()
    _ => fail("X 尾部必须报 Use-After-Free")
  }
  // 复用段 [x, x+60) 已合法，不得再报
  guard map.check_access(x, 4U, AccessKind::Write) is Ok(_) else {
    fail("复用段不得再报 UAF")
  }
  guard map.verify() is Ok(_) else { fail("不变量自检必须通过") }
}

///|
/// 嵌套重叠：新块完全落在旧块内部 → 拆成前缀 + 后缀两条。
test "freed_logs_nested_overlap_splits_two" {
  let logs = FreedLogs::new()
  logs.insert(FreedRegionInfo::{
    addr: 100U,
    size: 100,
    alloc_line: 1,
    freed_line: 2,
    alloc_step: 0,
    freed_step: 3,
  })
  logs.remove_overlapping(130U, 140U)
  assert_eq(logs.length(), 2)
  assert_eq(logs.at(0).addr, 100U)
  assert_eq(logs.at(0).size, 30)
  assert_eq(logs.at(1).addr, 140U)
  assert_eq(logs.at(1).size, 60)
}

///|
/// 完全覆盖：整条删除。
test "freed_logs_full_cover_deletes" {
  let logs = FreedLogs::new()
  logs.insert(FreedRegionInfo::{
    addr: 100U,
    size: 100,
    alloc_line: 1,
    freed_line: 2,
    alloc_step: 0,
    freed_step: 3,
  })
  logs.remove_overlapping(100U, 200U)
  assert_eq(logs.length(), 0)
  // 越界覆盖（start 更小、end 更大）同样整条删除
  logs.insert(FreedRegionInfo::{
    addr: 100U,
    size: 100,
    alloc_line: 1,
    freed_line: 2,
    alloc_step: 0,
    freed_step: 3,
  })
  logs.remove_overlapping(0U, 4096U)
  assert_eq(logs.length(), 0)
}

///|
/// 只剩后缀：原地改键（起点变为 `end`），条目数不变。
test "freed_logs_suffix_only_rekeys" {
  let logs = FreedLogs::new()
  logs.insert(FreedRegionInfo::{
    addr: 100U,
    size: 100,
    alloc_line: 1,
    freed_line: 2,
    alloc_step: 0,
    freed_step: 3,
  })
  logs.remove_overlapping(90U, 150U)
  assert_eq(logs.length(), 1)
  assert_eq(logs.at(0).addr, 150U)
  assert_eq(logs.at(0).size, 50)
  // 改键后仍必须有序：再插一条后继，裁剪只动它，顺序保持
  logs.insert(FreedRegionInfo::{
    addr: 200U,
    size: 10,
    alloc_line: 1,
    freed_line: 2,
    alloc_step: 0,
    freed_step: 3,
  })
  logs.remove_overlapping(200U, 205U)
  assert_eq(logs.length(), 2)
  assert_eq(logs.at(0).addr, 150U)
  assert_eq(logs.at(0).size, 50)
  assert_eq(logs.at(1).addr, 205U)
  assert_eq(logs.at(1).size, 5)
}

///|
/// `find_overlapping` 的**单次探测**语义：相邻不重叠不得误判。
///
/// 这条是"降序首个 `addr < end` 的条目即可判定"的边界锁——若实现错成
/// "只要 `addr < end` 就算重叠"，相邻块会误报 UAF；若退化成"全表扫描找
/// 任意重叠"，现象相同但提前 break 的前提与 O(log n) 都丢了。
test "freed_logs_find_overlapping_boundaries" {
  let logs = FreedLogs::new()
  logs.insert(FreedRegionInfo::{
    addr: 100U,
    size: 10,
    alloc_line: 1,
    freed_line: 2,
    alloc_step: 0,
    freed_step: 3,
  })
  // 命中：重叠
  guard logs.find_overlapping(105U, 1U) is Some(_) else {
    fail("块内起点必须命中")
  }
  guard logs.find_overlapping(95U, 10U) is Some(_) else {
    fail("从块前跨入必须命中")
  }
  // 边界：end == addr 不算重叠（半开区间）
  guard logs.find_overlapping(110U, 4U) is None else {
    fail("紧邻其后不得命中")
  }
  guard logs.find_overlapping(96U, 4U) is None else {
    fail("紧邻其前不得命中")
  }
  // 完全在空洞里
  guard logs.find_overlapping(200U, 4U) is None else {
    fail("空洞不得命中")
  }
  // 零长度 size：addr 落在块内仍算命中（`trap_invalid_free` 传 size=1 同族）
  guard logs.find_overlapping(105U, 0U) is Some(_) else {
    fail("size=0 落在块内应命中")
  }
  assert_eq(logs.contains(100U), true)
  assert_eq(logs.contains(101U), false)
}

///|
/// 有序 + 不重叠不变量：乱序插入后仍保序；`to_array` 返回独立副本；
/// 同键覆盖保位（`BTreeMap::insert` 语义）。
test "freed_logs_insert_keeps_order_and_copy_is_independent" {
  let logs = FreedLogs::new()
  for a in [300U, 100U, 200U] {
    logs.insert(FreedRegionInfo::{
      addr: a,
      size: 10,
      alloc_line: 1,
      freed_line: 2,
      alloc_step: 0,
      freed_step: 3,
    })
  }
  assert_eq(logs.at(0).addr, 100U)
  assert_eq(logs.at(1).addr, 200U)
  assert_eq(logs.at(2).addr, 300U)
  // 同键覆盖：位置不变、值更新
  logs.insert(FreedRegionInfo::{
    addr: 200U,
    size: 99,
    alloc_line: 1,
    freed_line: 2,
    alloc_step: 0,
    freed_step: 3,
  })
  assert_eq(logs.at(1).addr, 200U)
  assert_eq(logs.at(1).size, 99)
  assert_eq(logs.length(), 3)
  // 副本独立
  let copy = logs.to_array()
  copy[0] = FreedRegionInfo::{
    addr: 7U,
    size: 7,
    alloc_line: 7,
    freed_line: 7,
    alloc_step: 7,
    freed_step: 7,
  }
  assert_eq(logs.at(0).addr, 100U)
  assert_eq(copy[0].addr, 7U)
  // clear
  logs.clear()
  assert_true(logs.is_empty())
  assert_eq(logs.length(), 0)
}

///|
/// 区间判定的边界算术：**饱和**而非回绕（回绕会把"高地址 + 大 size"的
/// `end` 变成小值 → 重叠判定反转为"不重叠" → 静默漏检）。
test "saturating_interval_arithmetic" {
  assert_eq(sat_u32_add(0xFFFFFFFFU, 2U), 0xFFFFFFFFU)
  assert_eq(sat_u32_add(10U, 5U), 15U)
  assert_eq(sat_u32_sub(5U, 10U), 0U)
  assert_eq(sat_u32_sub(10U, 4U), 6U)
  // 饱和语义真的影响判定：addr 极大时不得因回绕判成"无重叠"
  let logs = FreedLogs::new()
  logs.insert(FreedRegionInfo::{
    addr: 0xFFFFFF00U,
    size: 256,
    alloc_line: 1,
    freed_line: 2,
    alloc_step: 0,
    freed_step: 3,
  })
  guard logs.find_overlapping(0xFFFFFF10U, 16U) is Some(_) else {
    fail("高地址区间必须命中（回绕实现会漏）")
  }
}

// ── 元数据唯一性（坑 6）────────────────────────────────────────────────────

///|
/// 坑 6 红锚：`realloc` 复用驱逐块时**同 addr 双条目**（旧实现无条件 push：
/// 泄漏报告把已释放块虚报为泄漏 + 索引失配）。
///
/// 本实现的条目以 addr 为键，"双条目"在结构上不可表达——本锚锁的是
/// `register_alloc` 的**复用分支**确实被走到（复位 `is_freed` + `size` 更新为
/// 本次请求大小），否则复用后 size 仍是旧值，泄漏统计漂移。
test "realloc_reuse_no_duplicate_entries" {
  let map = MemoryMap::new()
  map.set_quarantine_budget(0)
  // A（256，驱逐块候选）与 B（64，搬移源）都在 free(A) 之前分配
  let a = alloc(map, 256, "malloc", true)
  let b = alloc(map, 64, "malloc", true)
  assert_true(a != b)
  assert_true(free(map, a))
  // realloc(B, 128)：allocate_raw 驱逐 A(256) → first-fit 命中 → 新地址 = a
  let new_addr = match map.allocate_raw(128U, @bytecode.MEM_SIZE) {
    Some(x) => x
    None => fail("free_list 复用应成功")
  }
  assert_eq(
    new_addr,
    a,
    msg="free_list 复用：realloc 新地址应为驱逐块 a",
  )
  map.register_alloc(new_addr, 128, 1, "realloc", false)
  map.freed_logs_remove_overlapping(new_addr, new_addr + 128U)
  let mut dup = 0
  for t in map.regions_to_array() {
    if t.0 == a {
      dup = dup + 1
    }
  }
  assert_eq(
    dup,
    1,
    msg="addr 必须恰一条目（旧实现双条目 = 泄漏虚报 + 索引失配）",
  )
  match map.region(a) {
    Some(r) => {
      assert_false(r.is_freed, msg="复用后 is_freed 必须复位")
      assert_eq(
        r.size,
        128,
        msg="复用后 size 必须更新为本次请求大小",
      )
      assert_eq(r.alloc_by, "realloc")
    }
    None => fail("复用条目必须存在")
  }
  guard map.verify() is Ok(_) else { fail("不变量自检必须通过") }
}

// ── 隔离区三语义（坑 7）────────────────────────────────────────────────────

///|
/// 坑 7（窗口内）：`free` 后立即访问**必被检出**——隔离窗口内地址不复用是
/// UAF 检测的物理基础。
test "quarantine_window_uaf_detected" {
  let map = MemoryMap::new()
  let mem = Memory::new()
  let p = alloc(map, 10, "malloc", true)
  assert_true(free(map, p))
  // 写：报 Use-After-Free（Write）
  match mem.store_i8(map, p, 88) {
    Err(MemFault::UseAfterFree(info, AccessKind::Write)) => {
      assert_eq(info.addr, p)
      assert_eq(
        info.size,
        12,
        msg="登记 size 按 4 字节向上对齐（10 → 12）",
      )
    }
    _ => fail("窗口内写必须报 E3060（Write）")
  }
  // 读：同窗口同样拦住（Read）
  match mem.load_i8(map, p) {
    Err(MemFault::UseAfterFree(_, AccessKind::Read)) => ()
    _ => fail("窗口内读必须报 E3060（Read）")
  }
  // 窗口内 Double-Free：精确命中 freed_logs
  assert_true(map.freed_logs_contains(p))
  assert_false(
    free(map, p),
    msg="第二次 release 必须返回 false（E3061 的输入）",
  )
}

///|
/// 坑 7（预算 0）：预算 0 → free 立即被驱逐复用，且**复用后必须清理
/// freed_logs 与复位元数据**，否则使用新块会误报 UAF。
test "quarantine_budget_zero_immediate_reuse" {
  let map = MemoryMap::new()
  let mem = Memory::new()
  map.set_quarantine_budget(0)
  let a = alloc(map, 64, "malloc", true)
  assert_true(free(map, a))
  let b = alloc(map, 64, "malloc", true)
  assert_eq(b, a, msg="预算 0 → 驱逐后必须复用同地址")
  assert_false(
    map.freed_logs_contains(b),
    msg="复用后 freed_logs 必须已清理",
  )
  match map.region(b) {
    Some(r) => {
      assert_false(r.is_freed, msg="复用条目 is_freed 必须复位")
      assert_eq(r.size, 64, msg="复用条目 size 更新为新分配大小")
    }
    None => fail("复用条目必须存在")
  }
  // 使用新块不得误报 UAF
  guard mem.store_i8(map, b, 1) is Ok(_) else {
    fail("复用块可正常写入")
  }
}

///|
/// 坑 7（稳态）：churn 进入复用稳态后，**最后释放的块仍须在 freed_logs**
/// ——UAF 检测窗口不得被复用路径的清理误删。
test "churn_steady_state_quarantine_window_alive" {
  let map = MemoryMap::new()
  map.set_quarantine_budget(64) // 恰容一块 64B → 每次新分配驱逐上一块
  let mut last = 0U
  for n = 0; n < 50; n = n + 1 {
    let a = alloc(map, 64, "malloc", true)
    assert_true(a != 0U)
    assert_true(free(map, a))
    last = a
  }
  assert_true(
    map.regions_len() < 50,
    msg="预算 64B 下应进入地址复用稳态，实际条目 \{map.regions_len()}",
  )
  assert_true(
    map.freed_logs_contains(last),
    msg="稳态下最后释放的块必须仍在 freed_logs（检测窗口存活）",
  )
  match map.region(last) {
    Some(r) =>
      assert_true(r.is_freed, msg="对应 region 条目必须为 is_freed")
    None => fail("条目必须存在")
  }
  guard map.verify() is Ok(_) else { fail("不变量自检必须通过") }
}

///|
/// 泄漏计数与条目唯一性：churn 100 次（默认预算下不复用，各占新地址）后
/// 恰 1 块泄漏、条目恰 101。
test "churn_leak_count_and_no_duplicate_entries" {
  let map = MemoryMap::new()
  for n = 0; n < 100; n = n + 1 {
    let a = alloc(map, 32, "malloc", true)
    assert_true(free(map, a))
  }
  let live = alloc(map, 48, "malloc", true)
  assert_true(live != 0U)
  assert_eq(
    map.regions_len(),
    101,
    msg="churn 100 次 + 1 活块 = 101 个堆条目",
  )
  assert_eq(
    map.total_allocated(),
    48,
    msg="恰 1 块未释放（churn 全 free + 1 活块）",
  )
  // 地址唯一（由 Map 键保证，此处做健全性确认）
  let addrs : Array[UInt] = []
  for t in map.regions_to_array() {
    addrs.push(t.0)
  }
  addrs.sort_by(fn(x, y) { x.compare(y) })
  let mut dup = false
  for i = 1; i < addrs.length(); i = i + 1 {
    if addrs[i] == addrs[i - 1] {
      dup = true
    }
  }
  assert_false(dup, msg="堆条目地址必须唯一")
}

///|
/// 超隔离预算的 churn 不撞墙：3000 块 × 100B 饱和后持续驱逐复用；
/// 之后 10 万次 `alloc+free` 不得返回 NULL（若无驱逐复用，100B × 10485 次
/// 即耗尽 1MB）。
///
/// **规模口径**：与 Rust 侧同规模（10 万次），不做缩减——这是"堆顶是否
/// 单调推进"的直接证据，规模缩水会削弱判定强度。
test "churn_beyond_quarantine_budget_no_wall" {
  let map = MemoryMap::new()
  let mut i = 0
  while i < 3000 {
    let p = alloc(map, 100, "malloc", true)
    assert_true(p != 0U, msg="饱和前的分配不应失败（第 \{i} 次）")
    i = i + 1
  }
  // 全部释放 → 隔离区超预算
  let snapshot = map.regions_to_array()
  for t in snapshot {
    ignore(free(map, t.0))
  }
  // 驱逐复用后拿到一个地址并在下次分配中再次复用（证明 free_list 生效）
  let hi = match map.allocate_raw(100U, @bytecode.MEM_SIZE) {
    Some(x) => x
    None => fail("驱逐复用后仍应分配到地址")
  }
  ignore(free(map, hi))
  let mut k = 0
  while k < 100000 {
    let p = alloc(map, 100, "malloc", true)
    if p == 0U {
      fail("10 万次 churn 不得撞墙（第 \{k} 次）")
    }
    ignore(free(map, p))
    k = k + 1
  }
  assert_true(map.heap_offset() <= @bytecode.MEM_SIZE)
  guard map.verify() is Ok(_) else { fail("不变量自检必须通过") }
}

///|
/// leak 路径撞 1MB 墙：bump 单调推进直至 `allocate_raw` 返回 `None`
/// （调用方据此返回 NULL + 教学提示——**不 trap**，对齐 Clang）。
test "heap_1mb_wall_returns_null" {
  let map = MemoryMap::new()
  let mem = Memory::new()
  let mut count = 0
  while true {
    match map.allocate_raw(4096U, @bytecode.MEM_SIZE) {
      Some(a) => {
        count = count + 1
        // 每个新块都写一下，确认它确实落在载体合法范围内
        guard mem.store_i8(map, a, 1) is Ok(_) else {
          fail("新块必须可写")
        }
      }
      None => break
    }
  }
  assert_true(count > 0)
  // 撞墙后 heap_offset 不得越过载体上界
  assert_true(map.heap_offset() <= @bytecode.MEM_SIZE)
  guard map.verify() is Ok(_) else { fail("不变量自检必须通过") }
}

// ── 统计与自检 ──────────────────────────────────────────────────────────────

///|
/// 堆统计口径（`build_heap_stats` 与 Rust `build_heap_stats` 同算式）。
test "heap_stats_and_fragmentation" {
  let map = MemoryMap::new()
  assert_eq(map.heap_base(), @bytecode.HEAP_START)
  let s0 = map.build_heap_stats()
  assert_eq(s0.total_heap, 0)
  assert_eq(s0.fragmentation_rate, 0)
  let a = alloc(map, 300, "malloc", true)
  let _b = alloc(map, 100, "malloc", true)
  assert_true(free(map, a))
  // 预算 1 → 释放的块在 allocate_raw 入口即被驱逐进 free_list
  map.set_quarantine_budget(1)
  let _c = alloc(map, 16, "malloc", true)
  assert_true(map.total_fragmented() >= 0)
  let s1 = map.build_heap_stats()
  assert_eq(s1.heap_base, @bytecode.HEAP_START.reinterpret_as_int())
  assert_eq(s1.allocated, map.total_allocated())
  assert_eq(s1.fragmented, map.total_fragmented())
  assert_true(s1.fragmentation_rate >= 0 && s1.fragmentation_rate <= 100)
  // 计数口径：第 3 次分配走了**复用分支**（驱逐 a 的块后 first-fit 命中同址），
  // 只有"追加新条目"才自增 alloc_counter——复用不得抬高计数（否则 `heap_{n}`
  // 命名会跳号，与 Rust `host/memory.rs:43` 仅在新条目分支自增同口径）。
  assert_eq(
    map.alloc_counter(),
    2,
    msg="复用分支不得自增 alloc_counter",
  )
  assert_eq(map.quarantine_bytes() >= 0, true)
  // `set_heap_base` 必须同步 heap_offset（口径分裂会让 total_heap 变负）
  map.set_heap_base(0x6000U)
  assert_eq(map.heap_offset(), 0x6000U)
  assert_eq(map.build_heap_stats().total_heap, 0)
  // 显式设区域条目（host 之外的写入路径：导出层/测试）
  map.set_region(0x9000U, MemoryRegionData::heap_block(8, "", "", 0, "vfs"))
  assert_true(map.has_region(0x9000U))
  assert_eq(map.region(0x9000U).unwrap().size, 8)
}

///|
/// 自检闸自身可红：注入 `quarantine_bytes` 漂移后 `verify` 必须报错。
///
/// （"判定型设施必须先证会红"的最小形态；完整的多路证红留痕见提交说明。）
test "verify_catches_quarantine_bytes_drift" {
  let map = MemoryMap::new()
  let a = alloc(map, 64, "malloc", true)
  assert_true(free(map, a))
  guard map.verify() is Ok(_) else { fail("基线必须通过自检") }
  map.quarantine_bytes = map.quarantine_bytes + 1
  match map.verify() {
    Err(_) => ()
    Ok(_) => fail("quarantine_bytes 漂移必须被自检抓到")
  }
  // 复原后再次自检通过（确认是漂移而不是结构性失效）
  map.quarantine_bytes = map.quarantine_bytes - 1
  guard map.verify() is Ok(_) else { fail("复原后必须通过") }
}

// ── 载体（`Memory`）─────────────────────────────────────────────────────────

///|
/// 载体的 little-endian 位模式往返（u32/u64 与字节序对齐 Rust
/// `from_le_bytes`/`to_le_bytes`），以及页 / 全量快照的还原。
test "carrier_le_roundtrip" {
  let map = MemoryMap::new()
  let mem = Memory::new()
  assert_eq(mem.length(), @bytecode.MEM_SIZE.reinterpret_as_int())
  // u32 位模式逐字节核对（不靠自身读回自证）
  guard mem.store_u32(map, 0x5000U, 0x01020304U) is Ok(_) else {
    fail("写必须成功")
  }
  let raw = mem.clone_raw()
  assert_eq(raw[0x5000], b'\x04')
  assert_eq(raw[0x5001], b'\x03')
  assert_eq(raw[0x5002], b'\x02')
  assert_eq(raw[0x5003], b'\x01')
  match mem.load_u32(map, 0x5000U) {
    Ok(v) => assert_eq(v, 0x01020304U)
    Err(_) => fail("u32 读回必须成功")
  }
  // u64
  guard mem.store_u64(map, 0x5010U, 0x0102030405060708UL) is Ok(_) else {
    fail("u64 写必须成功")
  }
  match mem.load_u64(map, 0x5010U) {
    Ok(v) => assert_eq(v, 0x0102030405060708UL)
    Err(_) => fail("u64 读回必须成功")
  }
  // i8 符号扩展
  guard mem.store_i8(map, 0x5020U, 200) is Ok(_) else {
    fail("i8 写必须成功")
  }
  match mem.load_i8(map, 0x5020U) {
    Ok(v) =>
      assert_eq(
        v,
        -56,
        msg="200 的 i8 语义是 -56（Rust `b as i8 as i32`）",
      )
    Err(_) => fail("i8 读回必须成功")
  }
  // 页快照 / 写回往返（0x5000 落在第 5 页偏移 0）
  let page = mem.page(5)
  assert_eq(page.length(), PAGE_SIZE)
  assert_eq(page[0], b'\x04')
  guard mem.store_i8(map, 0x5000U, 0) is Ok(_) else {
    fail("清位必须成功")
  }
  mem.write_page(5, page)
  match mem.load_i8(map, 0x5000U) {
    Ok(v) => assert_eq(v, 4)
    Err(_) => fail("页写回必须还原")
  }
  // restore_raw 全量还原
  let full = mem.clone_raw()
  mem.reset()
  match mem.load_i8(map, 0x5000U) {
    Ok(v) => assert_eq(v, 0, msg="reset 后必须全零")
    Err(_) => fail("reset 后读必须成功")
  }
  mem.restore_raw(full)
  match mem.load_i8(map, 0x5000U) {
    Ok(v) => assert_eq(v, 4)
    Err(_) => fail("restore_raw 必须还原")
  }
  // 长度不符 → min 部分覆盖（六轮审阅顺带修：照搬 Rust snapshot.rs
  // `apply_to` Full 分支 `min(v.len, dst.len)`——静默 return 会使快照短于
  // 载体时恢复悄悄全丢，clone_snapshot_deep 往返正确性隐式依赖长度相等）
  let short : FixedArray[Byte] = FixedArray::make(8, b'\xCC')
  mem.restore_raw(short)
  assert_eq(
    mem.bytes[0],
    b'\xCC',
    msg="前缀必须覆盖（min 部分覆盖）",
  )
  assert_eq(mem.bytes[8], full[8], msg="超出短映像的部分必须保留")
  match mem.load_i8(map, 0x5000U) {
    Ok(v) => assert_eq(v, 4, msg="尾部（0x5000）必须不受影响")
    Err(_) => fail("读必须成功")
  }
}

///|
/// NULL 陷阱区与上界两类故障（`check_access` 的 1–2 级）。
test "carrier_null_and_bounds_faults" {
  let map = MemoryMap::new()
  let mem = Memory::new()
  match mem.load_u32(map, 0x0FFFU) {
    Err(MemFault::NullDeref(addr, AccessKind::Read)) => assert_eq(addr, 0x0FFFU)
    _ => fail("NULL 区读必须报 NullDeref")
  }
  match mem.store_u32(map, 0x0FFCU, 1U) {
    Err(MemFault::NullDeref(_, AccessKind::Write)) => ()
    _ => fail("跨越 NULL 区上沿的写必须报 NullDeref")
  }
  // 上界：末 4 字节内合法，越过即报
  guard mem.store_u32(map, @bytecode.MEM_SIZE - 4U, 7U) is Ok(_) else {
    fail("末 4 字节必须可写")
  }
  match mem.store_u32(map, @bytecode.MEM_SIZE - 3U, 7U) {
    Err(MemFault::OutOfBounds(addr, size)) => {
      assert_eq(addr, @bytecode.MEM_SIZE - 3U)
      assert_eq(size, 4U)
    }
    _ => fail("越上界必须报 OutOfBounds")
  }
  // 直接查判定入口（vm/host 的段级预检查路径）
  guard map.check_access(0x5000U, 4U, AccessKind::Read) is Ok(_) else {
    fail("合法地址必须通过")
  }
}

///|
/// 脏页：页号用移位定位，跨页写必须置**全部**被覆盖页；清单升序。
test "carrier_dirty_pages_shift" {
  let map = MemoryMap::new()
  let mem = Memory::new()
  mem.clear_dirty()
  assert_eq(mem.dirty_pages().length(), 0)
  // 0x1000 起写 4 字节：恰落第 1 页（0x1000 >> 12 = 1）
  guard mem.store_u32(map, 0x1000U, 1U) is Ok(_) else {
    fail("写必须成功")
  }
  assert_eq(mem.dirty_pages(), [1])
  assert_eq(mem.dirty_word(0), 2UL)
  assert_eq(mem.dirty_word_count(), DIRTY_WORD_COUNT)
  // 跨页：0x1FFE 起 4 字节覆盖第 1、2 页
  mem.clear_dirty()
  guard mem.store_u32(map, 0x1FFEU, 1U) is Ok(_) else {
    fail("跨页写必须成功")
  }
  assert_eq(mem.dirty_pages(), [1, 2])
  // 页 200 → word 3、bit 8（200 >> 6 = 3，200 & 63 = 8）
  mem.clear_dirty()
  guard mem.store_i8(map, 200U * 4096U, 1) is Ok(_) else {
    fail("写必须成功")
  }
  assert_eq(mem.dirty_word(3), 256UL)
  // 只读不脏
  mem.clear_dirty()
  ignore(mem.load_u32(map, 0x5000U))
  assert_eq(mem.dirty_pages().length(), 0)
  // reset 清脏
  guard mem.store_i8(map, 0x5000U, 1) is Ok(_) else { fail("写必须成功") }
  mem.reset()
  assert_eq(mem.dirty_pages().length(), 0)
}

///|
/// 批量原语：`fill` / `copy`（memmove 语义）/ `write_bytes`；
/// 以及"段级一次判定"确实拦住段内命中。
test "carrier_bulk_ops" {
  let map = MemoryMap::new()
  let mem = Memory::new()
  // fill
  guard mem.fill(map, 0x6000U, 64, b'\xAB') is Ok(_) else {
    fail("fill 必须成功")
  }
  match mem.load_u32(map, 0x6000U) {
    Ok(v) => assert_eq(v, 0xABABABABU)
    Err(_) => fail("fill 后读必须成功")
  }
  // write_bytes（Bytes 源）
  guard mem.write_bytes(map, 0x7000U, b"hello") is Ok(_) else {
    fail("write_bytes 必须成功")
  }
  match mem.load_i8(map, 0x7002U) {
    Ok(v) => assert_eq(v, 108, msg="'l'")
    Err(_) => fail("write_bytes 后读必须成功")
  }
  // copy 非重叠
  guard mem.copy(map, 0x7100U, 0x7000U, 5) is Ok(_) else {
    fail("copy 必须成功")
  }
  match mem.load_i8(map, 0x7104U) {
    Ok(v) => assert_eq(v, 111, msg="'o'")
    Err(_) => fail("copy 后读必须成功")
  }
  // copy 重叠：向前搬移必须是 memmove 语义（经临时缓冲）
  //   写 10..17 到 0x8000..0x8007，再 dst=0x8002 src=0x8000 len=6
  //   结果应为 10,11,10,11,12,13,14,15（memcpy 会污染成 10,11,10,11,10,11,10,11）
  for k = 0; k < 8; k = k + 1 {
    guard mem.store_i8(map, 0x8000U + k.reinterpret_as_uint(), 10 + k) is Ok(_) else {
      fail("写种子必须成功")
    }
  }
  guard mem.copy(map, 0x8002U, 0x8000U, 6) is Ok(_) else {
    fail("重叠 copy 必须成功")
  }
  match mem.load_i8(map, 0x8007U) {
    Ok(v) => assert_eq(v, 15, msg="重叠搬移必须按 memmove 语义")
    Err(_) => fail("重叠 copy 后读必须成功")
  }
  // 批量写已释放段必须整段拦住（段级判定一次，不损语义）
  let p = alloc(map, 32, "malloc", true)
  assert_true(free(map, p))
  match mem.fill(map, p, 8, b'\x00') {
    Err(MemFault::UseAfterFree(_, AccessKind::Write)) => ()
    _ => fail("批量写已释放段必须整段拦住")
  }
  // 段内某处命中同样要拦（dst 起点合法、区间尾部落在已释放块内）
  let q = alloc(map, 64, "malloc", true)
  assert_true(free(map, q))
  match mem.copy(map, q, q + 16U, 32) {
    Err(MemFault::UseAfterFree(_, _)) => ()
    _ => fail("区间判定必须覆盖段内命中")
  }
}

///|
/// 快照整装往返锚（load 单点，S6 vm 批一号）：构造含 regions / free_list /
/// quarantine / freed_logs 的活状态 → 抓快照（导出通道）→ churn 改状态 →
/// `load` 装回 → 全字段与不变量回到快照时点。region refcount（CS 批 ARC
/// 预留，C 侧恒 0）随 regions 往返不丢。
test "snapshot_load_roundtrip_restores_all_metadata" {
  let map = MemoryMap::new()
  let a = alloc(map, 32, "malloc", true)
  let b = alloc(map, 64, "malloc", true)
  ignore(b)
  // b 释放进隔离区，制造 quarantine / freed_logs 活状态
  assert_true(free(map, a))
  let snap = map.dump()
  let snap_regions = snap.regions
  let snap_freed = snap.freed
  let snap_heap_base = snap.heap_base
  let snap_heap_offset = snap.heap_offset
  let snap_counter = snap.alloc_counter
  // churn：再分配一块并释放，推进各状态
  let c = alloc(map, 128, "calloc", false)
  assert_true(free(map, c))
  ignore(snap_heap_base)
  ignore(snap_heap_offset)
  assert_true(
    map.alloc_counter() > snap_counter ||
    map.freed_logs_len() >= snap_freed.length(),
  )
  // 装回快照
  map.load(snap)
  assert_eq(map.regions_len(), snap_regions.length())
  assert_eq(map.alloc_counter(), snap_counter)
  assert_eq(map.freed_logs_len(), snap_freed.length())
  // region 条目逐字段往返（含 refcount 字段）
  for pair in snap_regions {
    guard map.region(pair.0) is Some(r) else {
      fail("region \{pair.0} 必须装回")
    }
    assert_eq(r.size, pair.1.size)
    assert_eq(r.refcount, pair.1.refcount)
  }
  // freed_logs 内容逐条往返
  for i = 0; i < snap_freed.length(); i = i + 1 {
    let e = map.freed_logs_at(i)
    assert_eq(e.addr, snap_freed[i].addr)
    assert_eq(e.size, snap_freed[i].size)
  }
  // 不变量自检过（隔离区清空 + bytes=0 自洽）
  guard map.verify() is Ok(_) else { fail("load 后 verify 必须过") }
}

///|
/// load_entries 契约锚（P3-1 修复后可判定）：升序合法灌入 Ok 且内容就位；
/// 降序 / 等键重复均 Err（乱序数据会让二分静默漏检 UAF——契约违约必须有
/// 判定力，不再依赖不可捕获的 abort；先校验后装载，违约不清空旧内容）。
test "load_entries_rejects_out_of_order" {
  let logs = FreedLogs::new()
  guard logs.load_entries([
      FreedRegionInfo::{
        addr: 0x100U,
        size: 16,
        alloc_line: 1,
        freed_line: 2,
        alloc_step: 3,
        freed_step: 4,
      },
      FreedRegionInfo::{
        addr: 0x200U,
        size: 16,
        alloc_line: 1,
        freed_line: 2,
        alloc_step: 3,
        freed_step: 5,
      },
    ])
    is Ok(_) else {
    fail("升序灌入必须 Ok")
  }
  assert_eq(logs.length(), 2)
  assert_true(logs.contains(0x100U))
  guard logs.load_entries([
      FreedRegionInfo::{
        addr: 0x300U,
        size: 16,
        alloc_line: 1,
        freed_line: 2,
        alloc_step: 3,
        freed_step: 6,
      },
      FreedRegionInfo::{
        addr: 0x100U,
        size: 16,
        alloc_line: 1,
        freed_line: 2,
        alloc_step: 3,
        freed_step: 7,
      },
    ])
    is Err(_) else {
    fail("降序必须 Err")
  }
  assert_eq(logs.length(), 2)
  guard logs.load_entries([
      FreedRegionInfo::{
        addr: 0x100U,
        size: 16,
        alloc_line: 1,
        freed_line: 2,
        alloc_step: 3,
        freed_step: 4,
      },
      FreedRegionInfo::{
        addr: 0x100U,
        size: 16,
        alloc_line: 1,
        freed_line: 2,
        alloc_step: 3,
        freed_step: 5,
      },
    ])
    is Err(_) else {
    fail("等键重复必须 Err")
  }
}
