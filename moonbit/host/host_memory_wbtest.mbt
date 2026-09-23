///| S6 宿主内存族白盒锚点（`vitro/engine/host`）。
///
/// **锚点来源**：Rust 冻结区的 host 契约测试逐条照搬（`host_contract_tests.rs`
/// 的 UAF/隔离窗口族、`u213_libc_boundary_test.rs` 的无效 free 族、坑 6/7/10），
/// 加上一条**新发现的 oracle 存量缺陷固化锚**（`calloc` 的置零/清理次序）。
///
/// 全部用例**不起 VM**：这是本批的结构收益——handler 只产出
/// [`HostMemReply`]（`value?` / `note?` / `trap?`），内存语义可以纯函数式锚定。
/// Rust 侧同族用例必须先 `setup_vm` + 手工 `vm.push`/`vm.pop` 才能触达。

///|
/// 新建一对（堆元数据，字节载体）。
fn fresh() -> (@memory.MemoryMap, @memory.Memory) {
  (@memory.MemoryMap::new(), @memory.Memory::new())
}

///|
/// `malloc` 成功路径：地址可用、条目登记正确、按名触发的是 Host 形态。
test "malloc_success_registers_region" {
  let (map, _mem) = fresh()
  let r = host_malloc(map, 100, 7)
  let addr = match r.value {
    Some(a) => a
    None => fail("malloc 必须返回值")
  }
  assert_true(addr != 0U)
  assert_eq(r.note, None)
  assert_eq(r.trap, None)
  guard map.region(addr) is Some(rec) else { fail("必须登记条目") }
  assert_eq(rec.size, 100)
  assert_eq(rec.alloc_line, 7)
  assert_eq(rec.alloc_by, "malloc")
  assert_eq(rec.is_freed, false)
  assert_eq(
    rec.name,
    "heap_1",
    msg="首次分配取 heap_1（alloc_counter 自增）",
  )
  // 路由表把 malloc 归为 Host（诊断敏感函数不走 Bytecode Libc）
  guard @bytecode.call_route("malloc") is Some(@bytecode.CallRoute::Host(_)) else {
    fail("malloc 必须路由到 Host")
  }
}

///|
/// `malloc(0)` / `malloc(负数)`：两条**不同**的失败形态（Rust `host/memory.rs:7-15`）。
test "malloc_zero_and_negative_paths" {
  let (map, _mem) = fresh()
  let z = host_malloc(map, 0, 1)
  assert_eq(z.value, Some(0U))
  guard z.note is Some(n) else { fail("malloc(0) 必须有教学提示") }
  assert_true(n.contains("malloc(0)"))
  assert_eq(z.trap, None)
  assert_eq(map.regions_len(), 0, msg="malloc(0) 不得登记条目")
  let neg = host_malloc(map, -4, 1)
  assert_eq(neg.value, Some(0U))
  assert_eq(neg.note, None, msg="负 size 静默返回 NULL（Rust 同）")
  assert_eq(map.regions_len(), 0)
}

///|
/// 堆耗尽：**返回 NULL + 教学附注，不 trap**（对齐 Clang，避免教坏"不检查返回值"）。
test "malloc_heap_exhausted_note" {
  let (map, _mem) = fresh()
  let mut n = 0
  let mut note : String? = None
  while true {
    let r = host_malloc(map, 4096, 1)
    match r.note {
      Some(t) => {
        note = Some(t)
        assert_eq(r.value, Some(0U))
        assert_eq(r.trap, None, msg="堆耗尽不 trap")
        break
      }
      None => {
        guard r.value is Some(a) else { fail("未耗尽前必须分配成功") }
        assert_true(a != 0U)
        n = n + 1
      }
    }
  }
  assert_true(n > 0)
  let t = note.unwrap()
  assert_true(t.contains("内存耗尽"), msg="文案须含「内存耗尽」")
  assert_true(
    t.contains("1024KB"),
    msg="上限须由 MEM_SIZE 格式化而来（不硬编码 1MB）",
  )
  assert_true(
    t.contains("256KB"),
    msg="隔离预算须由常量格式化而来",
  )
  assert_true(t.contains("malloc"), msg="须点出 malloc/calloc/realloc")
  assert_true(
    t.has_suffix("\n"),
    msg="附注须以换行收尾（否则与后续 printf 粘连）",
  )
}

///|
/// `free(NULL)` 是安全的空操作（C 标准）。
test "free_null_is_noop" {
  let (map, _mem) = fresh()
  let r = host_free(map, 0U, 3, 5)
  assert_eq(r.value, None)
  assert_eq(r.note, None)
  assert_eq(r.trap, None)
}

///|
/// Double-Free（E3061）：文案须含两个行号；且**不执行隔离区释放**（二次释放不改状态）。
test "double_free_trap_text" {
  let (map, _mem) = fresh()
  let a = host_malloc(map, 64, 11).value.unwrap()
  assert_eq(host_free(map, a, 42, 100).trap, None)
  assert_true(
    map.freed_logs_get(a) is Some(_),
    msg="释放须登记检验窗口",
  )
  let q = map.quarantine_len()
  let r2 = host_free(map, a, 43, 101)
  guard r2.trap is Some(t) else { fail("二次 free 必须 trap E3061") }
  assert_true(t.contains("E3061"))
  assert_true(t.contains("Double-Free"))
  assert_true(t.contains("第 42 行"), msg="须报首次释放行号")
  assert_true(t.contains("第 11 行"), msg="须报分配行号")
  assert_eq(
    map.quarantine_len(),
    q,
    msg="Double-Free 分支不得重复入隔离区",
  )
}

///|
/// 无效 free 三分支（E3027 / E3061 变体）——Rust `trap_invalid_free` 逐分支照搬。
test "invalid_free_three_branches" {
  let (map, _mem) = fresh()
  // ① 落在存活块内部的地址
  let a = host_malloc(map, 64, 5).value.unwrap()
  let r1 = host_free(map, a + 8U, 20, 20)
  guard r1.trap is Some(t1) else { fail("块内部地址必须诊断") }
  assert_true(t1.contains("E3027"))
  assert_true(
    t1.contains("内部地址"),
    msg="须点明「不是起始地址」",
  )
  assert_true(t1.contains("第 5 行"))
  assert_true(t1.contains("64 字节"))
  // ② 落在已释放块内部的地址
  assert_eq(host_free(map, a, 21, 21).trap, None)
  let r2 = host_free(map, a + 8U, 22, 22)
  guard r2.trap is Some(t2) else {
    fail("已释放块内部地址必须诊断")
  }
  assert_true(t2.contains("E3061"))
  assert_true(t2.contains("已释放块"))
  assert_true(t2.contains("第 21 行"))
  // ③ 不指向任何分配块起始地址
  let r3 = host_free(map, 0x9F00U, 23, 23)
  guard r3.trap is Some(t3) else { fail("垃圾地址必须诊断") }
  assert_true(t3.contains("E3027"))
  assert_true(t3.contains("不指向任何"))
  assert_true(
    t3.contains("0x9F00"),
    msg="地址按 0x{:X} 大写无前缀口径",
  )
}

///|
/// `calloc` 置零 + 尺寸链 + 零参数分支。
test "calloc_zeroing_and_shape" {
  let (map, mem) = fresh()
  // 先写脏一块区域，再 calloc 必须得到全零
  let seed = host_malloc(map, 32, 1).value.unwrap()
  guard mem.fill(map, seed, 32, b'\xFF') is Ok(_) else {
    fail("预写必须成功")
  }
  guard host_free(map, seed, 2, 2).trap is None else { fail("预释放") }
  let r = host_calloc(map, mem, 2, 16, 3)
  let addr = match r.value {
    Some(a) => a
    None => fail("calloc 必须返回值")
  }
  assert_eq(r.trap, None)
  assert_eq(r.note, None)
  match mem.load_i8(map, addr) {
    Ok(v) => assert_eq(v, 0)
    Err(_) => fail("calloc 后读必须成功")
  }
  match mem.load_i8(map, addr + 31U) {
    Ok(v) => assert_eq(v, 0, msg="整块必须置零（含尾部）")
    Err(_) => fail("calloc 尾部读必须成功")
  }
  guard map.region(addr) is Some(rec) else { fail("calloc 必须登记条目") }
  assert_eq(rec.size, 32, msg="size 存**未对齐**的 total（32）")
  assert_eq(rec.alloc_by, "calloc")
  // 零参数静默 NULL
  let z = host_calloc(map, mem, 0, 16, 4)
  assert_eq(z.value, Some(0U))
  assert_eq(z.note, None)
  assert_eq(z.trap, None)
}

///|
/// **已发现的 oracle 存量缺陷固化锚**：`calloc` 的置零发生在清理 freed_logs 之前，
/// 于是复用驱逐块时置零会撞上该块自己的检验窗口 → **Use-After-Free 误报**。
///
/// 触发链路：`free` 入隔离区 → `calloc` 的 `allocate_raw` 因超预算驱逐该块到
/// `free_list` 并 first-fit 取回（同址）→ 此时 freed_logs 里该地址的窗口还在
/// → 置零（受检写）判 UAF。该块**刚刚被合法重分配**，不是 UAF。
///
/// **本锚固化"照搬"后的行为**（Rust 顺序：置零 → 清理 → 登记 → 压地址；且
/// `trap()` 不中断 handler，故 trap 之后状态照常推进）。修复形态是一行换位
/// （先 `freed_logs_remove_overlapping` 再置零），届时本锚由红转绿。
test "calloc_reuse_triggers_uaf_false_positive" {
  let (map, mem) = fresh()
  map.set_quarantine_budget(0)
  let a = host_malloc(map, 64, 1).value.unwrap()
  assert_eq(host_free(map, a, 2, 2).trap, None)
  let r = host_calloc(map, mem, 1, 64, 3)
  assert_eq(r.value, Some(a), msg="预算 0 → 必复用同址")
  guard r.trap is Some(t) else {
    fail("当前实现（照搬 oracle）必触发误报")
  }
  assert_true(t.contains("E3060"), msg="误报以 UAF 形态出现")
  // trap 不中断：登记仍照常完成（与 Rust 逐字节循环的观察一致）
  guard map.region(a) is Some(rec) else { fail("trap 后登记仍应完成") }
  assert_eq(rec.alloc_by, "calloc")
  guard map.verify() is Ok(_) else { fail("元数据自检仍须通过") }
}

///|
/// `realloc` 恒搬移 + 保留数据 + 尾部置零（oracle 行为，C 标准不要求清零）。
test "realloc_moves_preserves_and_zeroes_tail" {
  let (map, mem) = fresh()
  let p = host_malloc(map, 8, 1).value.unwrap()
  for i = 0; i < 8; i = i + 1 {
    guard mem.store_i8(map, p + i.reinterpret_as_uint(), 65 + i) is Ok(_) else {
      fail("种子写必须成功")
    }
  }
  let r = host_realloc(map, mem, p, 32, 2, 2, 2)
  let q = match r.value {
    Some(a) => a
    None => fail("realloc 必须返回值")
  }
  assert_true(
    q != p,
    msg="恒为新块拷贝（决议 §3：原地复用会破坏隔离窗口）",
  )
  for i = 0; i < 8; i = i + 1 {
    match mem.load_i8(map, q + i.reinterpret_as_uint()) {
      Ok(v) => assert_eq(v, 65 + i)
      Err(_) => fail("旧数据必须保留")
    }
  }
  for i = 8; i < 32; i = i + 1 {
    match mem.load_i8(map, q + i.reinterpret_as_uint()) {
      Ok(v) => assert_eq(v, 0, msg="尾部按 oracle 置零")
      Err(_) => fail("尾部读必须成功")
    }
  }
  guard map.region(q) is Some(rec) else { fail("新块必须登记") }
  assert_eq(rec.size, 32)
  assert_eq(rec.alloc_by, "realloc")
  assert_eq(rec.name, "", msg="realloc 的新块不取名（Rust 同）")
  guard map.region(p) is Some(old) else {
    fail("旧块条目仍在（标记为已释放）")
  }
  assert_true(old.is_freed)
}

///|
/// `realloc(p, 0)` 等价 free：结果为 NULL，旧块进隔离区并登记窗口。
test "realloc_zero_size_equivalent_free" {
  let (map, mem) = fresh()
  let p = host_malloc(map, 32, 1).value.unwrap()
  let r = host_realloc(map, mem, p, 0, 2, 33, 55)
  assert_eq(r.value, Some(0U), msg="等价 free 分支结果恒为 NULL")
  assert_eq(r.trap, None)
  guard map.region(p) is Some(rec) else { fail("旧块条目仍在") }
  assert_true(rec.is_freed)
  guard map.freed_logs_get(p) is Some(info) else {
    fail("必须登记检验窗口")
  }
  assert_eq(info.freed_line, 33)
  assert_eq(info.freed_step, 55)
}

///|
/// `realloc(p, 0)` 遇无效指针：走无效 free 诊断（Rust 同样 trap）。
test "realloc_zero_size_invalid_ptr_diagnosed" {
  let (map, mem) = fresh()
  let r = host_realloc(map, mem, 0x8800U, 0, 1, 2, 3)
  assert_eq(r.value, Some(0U))
  guard r.trap is Some(t) else { fail("无效指针必须诊断") }
  assert_true(t.contains("E3027"))
}

///|
/// `realloc(0, n)` 等价 malloc。
test "realloc_null_ptr_equivalent_malloc" {
  let (map, mem) = fresh()
  let r = host_realloc(map, mem, 0U, 16, 9, 9, 9)
  let a = match r.value {
    Some(v) => v
    None => fail("必须返回值")
  }
  assert_true(a != 0U)
  assert_eq(r.trap, None)
  guard map.region(a) is Some(rec) else { fail("必须登记条目") }
  assert_eq(
    rec.alloc_by,
    "malloc",
    msg="等价 malloc 走的是 host_malloc（alloc_by 为 malloc）",
  )
}

///|
/// `realloc` 遇非活跃块：静默 NULL（Rust `:212-215` 不 trap）。
test "realloc_not_live_silent_null" {
  let (map, mem) = fresh()
  let p = host_malloc(map, 16, 1).value.unwrap()
  assert_eq(host_free(map, p, 2, 2).trap, None)
  let r = host_realloc(map, mem, p, 32, 3, 3, 3)
  assert_eq(r.value, Some(0U))
  assert_eq(r.note, None)
  assert_eq(
    r.trap,
    None,
    msg="已释放块不是「无效指针」——Rust 静默",
  )
}

///|
/// 坑 6 在 host 层的闭合：`realloc` 复用驱逐块时**同 addr 不双条目**。
///
/// 与 `memory` 包的同名锚同构，但走完整 host 调用链（含 `freed_logs` 清理次序）。
test "realloc_reuse_no_duplicate_entries" {
  let (map, mem) = fresh()
  map.set_quarantine_budget(0)
  let a = host_malloc(map, 256, 1).value.unwrap()
  let b = host_malloc(map, 64, 2).value.unwrap()
  assert_true(a != b)
  assert_eq(host_free(map, a, 3, 3).trap, None)
  let r = host_realloc(map, mem, b, 128, 4, 4, 4)
  assert_eq(r.value, Some(a), msg="free_list first-fit 必须复用驱逐块 a")
  assert_eq(
    r.trap,
    None,
    msg="复用块不得被判 UAF（清理次序正确）",
  )
  let mut dup = 0
  for pa in map.regions_to_array() {
    if pa.0 == a {
      dup = dup + 1
    }
  }
  assert_eq(dup, 1, msg="addr 必须恰一条目")
  guard map.region(a) is Some(rec) else { fail("条目必须存在") }
  assert_false(rec.is_freed)
  assert_eq(rec.size, 128)
  guard map.verify() is Ok(_) else { fail("不变量自检必须通过") }
}

///|
/// 大写十六进制口径（`0x{:X}`：无前缀、无前导零）。
test "hex_upper_format" {
  assert_eq(hex_upper(0U), "0")
  assert_eq(hex_upper(0x1A2BU), "1A2B")
  assert_eq(hex_upper(0x9F00U), "9F00")
  assert_eq(hex_upper(0xFFFFFFFFU), "FFFFFFFF")
}

///|
/// 尺寸链饱和乘：`nmemb * size` 不得回绕成小值（勘察坑 9 的修法在
/// `host/misc.rs`，`calloc` 用的是 `saturating_mul`）。
test "calloc_size_chain_saturates" {
  assert_eq(sat_mul_u32(0x10000U, 0x10000U), 0xFFFFFFFFU)
  assert_eq(sat_mul_u32(2U, 16U), 32U)
}

///|
/// **已发现的第二个 oracle 存量缺陷固化锚**：尺寸链饱和之后仍会**回绕**——
/// `align4(0xFFFFFFFF)` 在 32 位加法回绕下等于 **0**，`allocate_raw(0)` 按"零尺寸
/// 分配"短路返回 `Some(0)`。于是"超大尺寸"这条路径**不失败**，反而返回 NULL
/// 并登记一条 `addr = 0`、`size = -1` 的垃圾区域。
///
/// 这是**独立于**坑 9（`qsort` 那条已被 `checked_mul` 修掉）的第二条路径：
/// `calloc` 用的是 `saturating_mul`。本锚同时锁住三件事：① 当前不失败；
/// ② 不产生 trap（跳过 0 长度置零，与 Rust 的 0 次循环同）；③ **元数据被写坏
/// 是可被 `verify()` 抓到的**（把静默损坏变成可断言事实）。
/// 修复形态：`total` 先与 `MEM_SIZE` 比，超限直接走堆耗尽分支。
test "calloc_oversize_size_chain_registers_garbage_region" {
  let (map, mem) = fresh()
  let r = host_calloc(map, mem, 65536 * 1024, 65536 * 1024, 1)
  assert_eq(r.value, Some(0U), msg="当前实现返回 NULL（不失败）")
  assert_eq(
    r.trap,
    None,
    msg="0 长度置零被跳过 ⇒ 无 NULL trap（与 Rust 0 次循环同）",
  )
  assert_true(
    r.note is None,
    msg="不走堆耗尽分支（allocate_raw(0) 短路成功）",
  )
  // 垃圾区域确实被登记：addr=0、size=total as i32 = -1
  guard map.region(0U) is Some(rec) else { fail("必须登记到 addr = 0") }
  assert_eq(rec.size, -1, msg="0xFFFFFFFF as i32 = -1")
  assert_eq(rec.alloc_by, "calloc")
  // 元数据自检吃这条 ⇒ 静默损坏变成可断言事实
  match map.verify() {
    Err(_) => ()
    Ok(_) => fail("垃圾区域必须被自检抓到")
  }
}
