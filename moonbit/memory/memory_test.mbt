///| S6 内存域**黑盒**锚点（`vitro/engine/memory` 的对外契约）。
///
/// 黑盒测试是"包外消费者视角"：只能用 pub 面、拿不到 priv 字段。因此本文件
/// 同时承担两个职责：
/// 1. **对外语义锚**——`host` / `vm` 两个下游包将按这里的调用形态使用本包，
///    故它锁的是"接口够不够用"（例如：字节载体之外能否完成一次完整的
///    malloc/free/UAF 判定循环）；
/// 2. **对外面消费面**——`scripts/moonbit/moonbit_surface -check` 判定一个 pub
///    符号"有无跨包消费"时，黑盒 `*_test.mbt` 里带包前缀的符号引用计入消费
///    （`used[pkgAlias][sym] = true`；同包目录不计新边）。故本文件逐一引用
///    本包全部 pub 符号，避免出现"无主 pub"（仓内既有先例：`names_test.mbt`）。
///
/// 白盒锚（含全部红→绿锚）在 `memory_wbtest.mbt`；本文件重复的语义断言刻意
/// 从**包外视角**再走一遍，两侧同时红才算锚点稳固。

///|
/// 常量面板：本包自有的页几何 / 隔离预算，与 L6 单源的布局常量对账。
test "layout_constants_surface" {
  assert_eq(@memory.PAGE_SHIFT, 12)
  assert_eq(@memory.PAGE_SIZE, 4096)
  assert_eq(@memory.PAGE_COUNT, 256)
  assert_eq(@memory.DIRTY_WORD_COUNT, 4)
  assert_eq(@memory.DEFAULT_QUARANTINE_BUDGET, 262144)
  // 与 L6（bytecode）单源对账：1MB 载体 = PAGE_SIZE × PAGE_COUNT
  assert_eq(
    @memory.PAGE_SIZE * @memory.PAGE_COUNT,
    @bytecode.MEM_SIZE.reinterpret_as_int(),
  )
  assert_eq(
    @memory.DEFAULT_QUARANTINE_BUDGET * 4,
    @bytecode.MEM_SIZE.reinterpret_as_int(),
  )
}

///|
/// 区间的饱和算术原语（跨包共享的边界算术口径）。
test "saturating_arithmetic_surface" {
  assert_eq(@memory.sat_u32_add(1U, 2U), 3U)
  assert_eq(@memory.sat_u32_add(0xFFFFFFFFU, 1U), 0xFFFFFFFFU)
  assert_eq(@memory.sat_u32_sub(3U, 5U), 0U)
  assert_eq(@memory.sat_u32_sub(5U, 3U), 2U)
}

///|
/// `FreedLogs` 的对外契约：插入 / 区间查询 / 精确命中 / 精确裁剪 / 快照副本。
test "freed_logs_surface" {
  let logs = @memory.FreedLogs::new()
  assert_true(logs.is_empty())
  assert_eq(logs.length(), 0)
  logs.insert(@memory.FreedRegionInfo::{
    addr: 0x2000U,
    size: 64,
    alloc_line: 3,
    freed_line: 9,
    alloc_step: 0,
    freed_step: 12,
  })
  assert_eq(logs.length(), 1)
  let e = logs.at(0)
  assert_eq(e.addr, 0x2000U)
  assert_eq(e.size, 64)
  assert_eq(e.alloc_line, 3)
  assert_eq(e.freed_line, 9)
  assert_eq(e.alloc_step, 0)
  assert_eq(e.freed_step, 12)
  assert_eq(logs.contains(0x2000U), true)
  assert_eq(logs.contains(0x2001U), false)
  guard logs.find_overlapping(0x2010U, 4U) is Some(_) else {
    fail("区间内必须命中")
  }
  guard logs.find_overlapping(0x2040U, 4U) is None else {
    fail("区间后不得命中")
  }
  // 精确裁剪：前缀保留 + 后缀另插
  logs.remove_overlapping(0x2008U, 0x2010U)
  assert_eq(logs.length(), 2)
  assert_eq(logs.at(0).addr, 0x2000U)
  assert_eq(logs.at(0).size, 8)
  assert_eq(logs.at(1).addr, 0x2010U)
  assert_eq(logs.at(1).size, 0x2040 - 0x2010)
  // 升序快照（独立副本）
  let copy = logs.to_array()
  assert_eq(copy.length(), 2)
  copy[0] = e
  assert_eq(logs.at(0).size, 8, msg="副本改动不得回写")
  logs.clear()
  assert_eq(logs.length(), 0)
}

///|
/// `MemoryMap` 的对外契约：一次完整的"分配 → 使用 → 释放 → UAF 判定"循环。
///
/// 这正是 `host` 建包时的调用次序（`host_malloc` / `host_free` 的内存侧），
/// 故本测试等价于下游包的**接口可用性验收**。
test "memory_map_alloc_free_uaf_cycle" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  assert_eq(map.heap_base(), @bytecode.HEAP_START)
  assert_eq(map.heap_offset(), @bytecode.HEAP_START)
  assert_eq(map.alloc_counter(), 0)
  assert_eq(map.quarantine_bytes(), 0)
  assert_eq(map.quarantine_budget(), @memory.DEFAULT_QUARANTINE_BUDGET)
  assert_eq(map.regions_len(), 0)
  assert_eq(map.quarantine_len(), 0)
  assert_eq(map.free_list_len(), 0)
  assert_eq(map.total_allocated(), 0)
  guard map.verify() is Ok(_) else { fail("空堆必须通过自检") }
  // 分配
  let addr = match map.allocate_raw(64U, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => fail("首次分配必须成功")
  }
  map.register_alloc(addr, 64, 7, "malloc", true)
  map.freed_logs_remove_overlapping(addr, addr + 64U)
  assert_eq(map.regions_len(), 1)
  assert_true(map.has_region(addr))
  assert_true(map.region(addr) is Some(_), msg="条目必须存在")
  assert_eq(map.alloc_counter(), 1)
  assert_eq(map.total_allocated(), 64)
  // 使用（受检访问）
  guard mem.store_u32(map, addr, 0xDEADBEEFU) is Ok(_) else {
    fail("合法写必须成功")
  }
  match mem.load_u32(map, addr) {
    Ok(v) => assert_eq(v, 0xDEADBEEFU)
    Err(_) => fail("合法读必须成功")
  }
  // 释放
  match map.release(addr, 11, 33) {
    Some(sz) => assert_eq(sz, 64)
    None => fail("首次释放必须成功")
  }
  assert_eq(map.quarantine_len(), 1)
  assert_eq(map.quarantine_bytes(), 64)
  assert_eq(map.freed_logs_len(), 1)
  assert_eq(map.freed_logs_at(0).addr, addr)
  assert_eq(map.freed_logs_at(0).freed_line, 11)
  assert_eq(map.freed_logs_at(0).freed_step, 33)
  assert_eq(map.freed_logs_contains(addr), true)
  guard map.freed_logs_find_overlapping(addr, 1U) is Some(_) else {
    fail("窗口内必须命中")
  }
  // UAF 判定（结构化故障）
  match mem.load_i8(map, addr) {
    Err(@memory.MemFault::UseAfterFree(info, @memory.AccessKind::Read)) => {
      assert_eq(info.addr, addr)
      assert_eq(info.freed_line, 11)
    }
    _ => fail("窗口内访问必须报 UseAfterFree(Read)")
  }
  // 二次释放必须被拒（E3061 的输入）
  assert_eq(map.release(addr, 12, 34), None)
  // 复用：预算 0 → 驱逐后同址复用，且登记/窗口同步复位
  map.set_quarantine_budget(0)
  let again = match map.allocate_raw(64U, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => fail("驱逐复用必须成功")
  }
  assert_eq(again, addr, msg="预算 0 → first-fit 必须复用同址")
  map.register_alloc(again, 64, 13, "calloc", true)
  map.freed_logs_remove_overlapping(again, again + 64U)
  assert_eq(map.freed_logs_contains(again), false)
  assert_eq(map.alloc_counter(), 1, msg="复用分支不得自增计数")
  guard mem.store_i8(map, again, 1) is Ok(_) else {
    fail("复用块必须可写（窗口已清）")
  }
  // 统计与导出面
  assert_eq(map.total_fragmented(), 0)
  assert_eq(map.fragmentation_rate(), 0)
  let stats : @memory.HeapStatsData = map.build_heap_stats()
  assert_eq(stats.allocated, 64)
  assert_eq(stats.fragmented, 0)
  let regs = map.regions_to_array()
  assert_eq(regs.length(), 1)
  assert_eq(regs[0].0, addr)
  let (addr0, data0) = regs[0]
  assert_eq(addr0, addr)
  assert_eq(data0.size, 64)
  assert_eq(data0.is_heap, true)
  assert_eq(data0.is_freed, false)
  assert_eq(data0.alloc_by, "calloc")
  assert_eq(data0.kind, "heap")
  // 显式设条目（导出层 / vfs 路径）
  map.set_region(
    0x3000U,
    @memory.MemoryRegionData::heap_block(8, "vfs_buf", "char", 5, "fopen"),
  )
  guard map.region(0x3000U) is Some(r) else { fail("显式条目必须存在") }
  assert_eq(r.size, 8)
  assert_eq(r.name, "vfs_buf")
  assert_eq(r.ty, "char")
  assert_eq(r.alloc_line, 5)
  guard map.verify() is Ok(_) else { fail("循环结束必须通过自检") }
  // 隔离区 / 空闲表读面
  if map.quarantine_len() > 0 {
    let qb : @memory.FreeBlock = map.quarantine_at(0)
    assert_true(qb.size > 0)
  }
  ignore(map.free_list_len())
  if map.free_list_len() > 0 {
    let fb : @memory.FreeBlock = map.free_list_at(0)
    assert_true(fb.size > 0)
  }
  // 堆起点重置必须同步 heap_offset
  map.set_heap_base(0x6000U)
  assert_eq(map.heap_offset(), 0x6000U)
}

///|
/// `Memory` 的对外契约：受检读写 + 两类结构化故障 + 脏页 + 批量原语。
test "memory_carrier_surface" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  assert_eq(mem.length(), @bytecode.MEM_SIZE.reinterpret_as_int())
  // NULL 区
  match mem.load_i8(map, 0U) {
    Err(@memory.MemFault::NullDeref(_, @memory.AccessKind::Read)) => ()
    _ => fail("NULL 区读必须报 NullDeref")
  }
  // 上界（用判定入口直接验）
  match map.check_access(@bytecode.MEM_SIZE, 1U, @memory.AccessKind::Write) {
    Err(@memory.MemFault::OutOfBounds(_, _)) => ()
    _ => fail("越上界必须报 OutOfBounds")
  }
  // 四类宽度读写
  guard mem.store_i8(map, 0x5000U, 65) is Ok(_) else { fail("i8 写") }
  guard mem.store_u32(map, 0x5004U, 0x11223344U) is Ok(_) else {
    fail("u32 写")
  }
  guard mem.store_u64(map, 0x5008U, 0x1122334455667788UL) is Ok(_) else {
    fail("u64 写")
  }
  match mem.load_i8(map, 0x5000U) {
    Ok(v) => assert_eq(v, 65)
    Err(_) => fail("i8 读")
  }
  match mem.load_u32(map, 0x5004U) {
    Ok(v) => assert_eq(v, 0x11223344U)
    Err(_) => fail("u32 读")
  }
  match mem.load_u64(map, 0x5008U) {
    Ok(v) => assert_eq(v, 0x1122334455667788UL)
    Err(_) => fail("u64 读")
  }
  // 批量原语
  guard mem.fill(map, 0x6000U, 16, b'\x7F') is Ok(_) else { fail("fill") }
  guard mem.write_bytes(map, 0x6010U, b"abc") is Ok(_) else {
    fail("write_bytes")
  }
  guard mem.copy(map, 0x6020U, 0x6000U, 16) is Ok(_) else { fail("copy") }
  match mem.load_i8(map, 0x6020U) {
    Ok(v) => assert_eq(v, 0x7F)
    Err(_) => fail("copy 后读")
  }
  // 脏页面
  mem.mark_dirty(0x7000U, 8U)
  assert_true(mem.dirty_pages().length() > 0)
  assert_eq(mem.dirty_word_count(), @memory.DIRTY_WORD_COUNT)
  let w = mem.dirty_word(0)
  assert_true(w != 0UL)
  mem.clear_dirty()
  assert_eq(mem.dirty_pages().length(), 0)
  // 快照面
  let page = mem.page(6)
  assert_eq(page.length(), @memory.PAGE_SIZE)
  mem.write_page(6, page)
  let full = mem.clone_raw()
  assert_eq(full.length(), @bytecode.MEM_SIZE.reinterpret_as_int())
  mem.reset()
  mem.restore_raw(full)
  match mem.load_u32(map, 0x5004U) {
    Ok(v) => assert_eq(v, 0x11223344U, msg="restore_raw 必须还原")
    Err(_) => fail("restore 后读")
  }
}

///|
/// `MemoryMap::verify` 是对外可用的不变量闸（下游包可作 debug 断言调用）。
test "verify_is_usable_from_outside" {
  let map = @memory.MemoryMap::new()
  guard map.verify() is Ok(_) else { fail("空堆自检") }
  // 建一个带隔离块与非空 free_list 的堆，自检仍须通过
  let a = match map.allocate_raw(128U, @bytecode.MEM_SIZE) {
    Some(x) => x
    None => fail("分配")
  }
  map.register_alloc(a, 128, 1, "malloc", true)
  ignore(map.release(a, 2, 2))
  let b = match map.allocate_raw(16U, @bytecode.MEM_SIZE) {
    Some(x) => x
    None => fail("分配")
  }
  map.register_alloc(b, 16, 3, "malloc", true)
  guard map.verify() is Ok(_) else { fail("非空堆自检") }
}

// ── 未在本批落地的对外面（登记，不静默）─────────────────────────────────────
//
// 以下面**有意**不在本批 pub：它们在语义上属于本包，但依赖尚未落地的上游，
// 现在定形会返工，故登记到 S6 后续批（总计划 §S6 行）：
// - 快照批量装载（`load_regions` / `load_free_list` / `load_quarantine` /
//   `load_freed_logs`）：形状由 `vm` 的 `VMSnapshot` / `MemoryImage` 决定
//   （勘察 §5.2 要求"回滚 = 整体替换、字段增删不改快照代码"）；
// - `MemoryFragmentData`（`{addr, size}`）：Rust 侧只被 L8 导出层
//   `session.rs:289-298` 消费，属导出 DTO，随协议层建包；
// - cstring 通道（`write_cstring` / `read_cbytes` / `read_cstring`）：
//   `\xHH ≥ 0x80 → Latin-1` 的口径单源目前长在 L6 `codegen/init.mbt`
//   （`cstring_bytes`，priv），跨层复用需先把该口径上提为独立单源
//   （勘察 §1.6 表格 F 类；坑 16「`strlen(NULL)` 静默返回 0」也在此列）。
