///|
/// fuzz_invariant_wbtest —— 工序④准出件·路 A：安全检测不变量自检
/// （判定书 §4.3 / 冻结资产清单配套；Rust fuzz A/B/D/E 的 MoonBit 迁移）。
///
/// 与 Rust 版（native/tests/fuzz_stress_test.rs，随区退役）的关系：
/// **同不变量、独立实现**——Rust 版走 Session+VM 装载；本版 wbtest 直调
/// host/memory 面。随机源 = 自带 LCG（同 @host rand 族参数），seed 固定
/// ⇒ 序列可复现（确定性随机测试，判定书原文口径）。
///
/// 三核心不变量：①UAF 必报（E3060）②1MB 墙必 NULL（不崩不越墙）
/// ③区域表有界（活跃区地址恒在墙内）。加严：double-free 必 E3061、
/// 合法 malloc/free 不得 trap、泄漏面计数准确（场景 E）。
/// J9：fuzz_invariant_canary_red —— 断言线金丝雀（检测失守形态必红）。

// ---- 随机源：LCG（与 @host host_rand 同族参数；seed 固定可复现） ----

struct FRng {
  mut state : Int
}

///|
fn FRng::new(seed : Int) -> FRng {
  { state: seed, }
}

///|
fn FRng::next(self : FRng) -> Int {
  self.state = (self.state * 1103515245 + 12345) & 0x7FFFFFFF
  self.state
}

///|
/// 高位取数：LCG 低位周期短（% 10 取低位实测 8 连不出现 free 分支——探针实锤），range/pick 一律用位 16..31。
fn FRng::high(self : FRng) -> Int {
  self.next() >> 16
}

///|
fn FRng::range(self : FRng, lo : Int, hi : Int) -> Int {
  if hi <= lo {
    return lo
  }
  lo + self.high() % (hi - lo + 1)
}

///|
fn FRng::pick(self : FRng, addrs : Array[UInt]) -> UInt? {
  if addrs.length() == 0 {
    return None
  }
  Some(addrs[self.high() % addrs.length()])
}

// ---- region 视图（MemoryMap 导出面单源消费） ----

///|
fn active_heap_addrs(map : @memory.MemoryMap) -> Array[UInt] {
  let out : Array[UInt] = []
  for entry in map.regions_to_array() {
    let (addr, r) = entry
    if r.is_heap && r.is_freed == false && r.alloc_by != "vfs" {
      out.push(addr)
    }
  }
  out
}

///|
/// 注入用「已释放且未复用」判定：条目不存在（free 删条目——与 Rust 保留
/// is_freed 历史的结构差异）或存在且 is_freed。
fn is_freed_now(map : @memory.MemoryMap, addr : UInt) -> Bool {
  match map.region(addr) {
    Some(r) => r.is_freed
    None => true
  }
}

///|
/// 向墙内一段安全地址写字节串 + NUL（strcpy 的 src 预置）。
fn seed_cstring(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  s : String,
) -> Unit {
  let bytes = s.to_array() // Array[Char]
  for i, b in bytes {
    ignore(mem.store_i8(map, addr + i.reinterpret_as_uint(), b.to_int()))
  }
  ignore(mem.store_i8(map, addr + bytes.length().reinterpret_as_uint(), 0))
}

// ---- 不变量 ②：1MB 墙 ----

///|
test "fuzz_wall_malloc_returns_null" {
  let (map, _) = fresh()
  for size in [-4, 0, 1048576, 2097152, 1073741824] {
    let r = host_malloc(map, size, 1)
    assert_eq(r.trap, None, msg="墙外尺寸不得 trap：size=\{size}")
    assert_eq(r.value.unwrap().to_int(), 0, msg="墙外必 NULL：size=\{size}")
  }
}

// ---- 场景 A：malloc/free 随机序列（含 double-free / UAF 注入） ----

///|
test "fuzz_round_a_malloc_free_invariants" {
  let (map, mem) = fresh()
  seed_cstring(mem, map, 0x7000U, "x")
  let rng = FRng::new(20261005)
  let my_freed : Array[UInt] = []
  let mut bad_legal_ops = 0
  let mut double_free_hits = 0
  let mut uaf_hits = 0
  for op = 0; op < 300; op = op + 1 {
    let kind = rng.range(0, 9)
    if kind <= 4 {
      let size = rng.range(1, 256)
      let r = host_malloc(map, size, op)
      if r.trap is Some(_) {
        bad_legal_ops = bad_legal_ops + 1
      } else {
        let addr = r.value.unwrap().to_uint()
        if addr != 0U {
          assert_true(
            addr + size.reinterpret_as_uint() <= 1048576U,
            msg="不变量③越墙",
          )
        }
      }
    } else if kind <= 6 {
      let a = rng.pick(active_heap_addrs(map))
      if a is Some(addr) {
        if host_free(map, addr, 1, op).trap is Some(_) {
          bad_legal_ops = bad_legal_ops + 1
        } else {
          my_freed.push(addr)
        }
      }
    } else if kind == 7 {
      let a = rng.pick(my_freed)
      if a is Some(addr) && is_freed_now(map, addr) {
        let r = host_free(map, addr, 2, op)
        guard r.trap is Some(t) else {
          fail("不变量①失守：double-free 未报 addr=\{addr}")
        }
        assert_true(
          t.contains("E3061"),
          msg="double-free 须 E3061 实得 \{t}",
        )
        double_free_hits = double_free_hits + 1
      }
    } else if kind == 8 {
      let a = rng.pick(my_freed)
      if a is Some(addr) && is_freed_now(map, addr) {
        let r = host_strcpy(map, mem, addr, 0x7000U, [])
        guard r.trap is Some(t) else {
          fail("不变量①失守：UAF 写未报 addr=\{addr}")
        }
        assert_true(t.contains("E3060"), msg="UAF 须 E3060 实得 \{t}")
        uaf_hits = uaf_hits + 1
      }
    } else {
      assert_eq(
        host_free(map, 0U, 1, op).trap,
        None,
        msg="free(NULL) 不得 trap",
      )
    }
    for a in active_heap_addrs(map) {
      assert_true(a < 1048576U, msg="不变量③：活跃区越墙 \{a}")
    }
  }
  assert_eq(
    bad_legal_ops,
    0,
    msg="合法操作意外 trap \{bad_legal_ops} 处",
  )
  assert_true(
    double_free_hits > 3,
    msg="double-free 命中 \{double_free_hits}——序列覆盖可疑",
  )
  assert_true(
    uaf_hits > 3,
    msg="UAF 命中 \{uaf_hits}——序列覆盖可疑",
  )
}

// ---- 场景 B：字符串写随机序列（E3070 溢出检测） ----

///|
test "fuzz_round_b_string_overflow_detected" {
  let (map, mem) = fresh()
  let rng = FRng::new(7331)
  let src_addr = 0x7000U
  let mut overflows = 0
  for round = 0; round < 30; round = round + 1 {
    let buf = host_malloc(map, 16, round + 1).value.unwrap().to_uint()
    let len = rng.range(1, 48)
    seed_cstring(mem, map, src_addr, "a".repeat(len))
    let r = host_strcpy(map, mem, buf, src_addr, [])
    if len >= 16 {
      guard r.trap is Some(t) else {
        fail("E3070 漏检：\{len} 字节写 16B 缓冲未报")
      }
      assert_true(t.contains("E3070"), msg="溢出须 E3070 实得 \{t}")
      overflows = overflows + 1
    } else {
      assert_eq(r.trap, None, msg="界内写不得 trap len=\{len}")
    }
    ignore(host_free(map, buf, round, 7))
  }
  assert_true(
    overflows > 10,
    msg="30 轮随机溢出命中 \{overflows}——覆盖可疑",
  )
}

// ---- 场景 D：混合恶意（分配/释放/野写交叉）整体稳定 + 检测不漏 ----

///|
test "fuzz_round_d_mixed_stability" {
  let (map, mem) = fresh()
  seed_cstring(mem, map, 0x7000U, "zz")
  let rng = FRng::new(424242)
  let my_freed : Array[UInt] = []
  let mut e3060 = 0
  for op = 0; op < 120; op = op + 1 {
    let kind = rng.range(0, 3)
    match kind {
      0 => ignore(host_malloc(map, rng.range(1, 64), op))
      1 => {
        let a = rng.pick(active_heap_addrs(map))
        if a is Some(addr) {
          if host_free(map, addr, 1, op).trap is None {
            my_freed.push(addr)
          }
        }
      }
      _ => {
        let a = rng.pick(my_freed)
        if a is Some(addr) && is_freed_now(map, addr) {
          let r = host_strcpy(map, mem, addr, 0x7000U, [])
          if r.trap is Some(t) && t.contains("E3060") {
            e3060 = e3060 + 1
          }
        }
      }
    }
  }
  assert_true(map.regions_len() > 0, msg="区域表须有记录")
  assert_true(
    e3060 > 2,
    msg="混合序列 UAF 命中 \{e3060}——覆盖可疑",
  )
}

// ---- 场景 E：泄漏面准确（随机分配不释放 → 活跃区数 = 成功分配数） ----

///|
test "fuzz_round_e_leak_report_accurate" {
  let (map, _) = fresh()
  let rng = FRng::new(998877)
  let mut ok = 0
  for op = 0; op < 50; op = op + 1 {
    let size = rng.range(1, 128)
    if host_malloc(map, size, op + 900).value.unwrap().to_int() != 0 {
      ok = ok + 1
    }
  }
  assert_eq(active_heap_addrs(map).length(), ok, msg="泄漏面失准")
}

// ---- J9：断言线金丝雀（模拟检测失守形态必红——证明非恒真死锚） ----

///|
test "fuzz_invariant_canary_red" {
  let (map, mem) = fresh()
  let a = host_malloc(map, 32, 1).value.unwrap().to_uint()
  ignore(host_free(map, a, 1, 1))
  seed_cstring(mem, map, 0x7000U, "x")
  let r = host_strcpy(map, mem, a, 0x7000U, [])
  // 检测正常 → 此两断言绿；引擎检测失守（trap 为 None / 码错）→ 红。
  assert_true(
    r.trap is Some(_),
    msg="J9 金丝雀：UAF 检测失守此处必红",
  )
  assert_true(
    r.trap.unwrap().contains("E3060"),
    msg="J9 金丝雀：检测码漂移必红",
  )
}
