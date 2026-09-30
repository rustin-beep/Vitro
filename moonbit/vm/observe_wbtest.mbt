///| L7 VM·**教学观测面锚族**（S8 批一号三段-a，2026-10-01）——照搬
/// memory.rs/state.rs 观测方法的语义锚：变量快照作用域过滤与同名择优 /
/// find_variable_name_at_addr 数组区间归属 + 跨帧 / 数组快照 256 截断与
/// 元素文本化 / vis take 幂等。构造走 set_symbols + 直改帧与行号（wbtest
/// 同包特权——观测语义不依赖 executor 驱动）。

///|
fn mksym(
  name : String,
  addr : UInt,
  is_local : Bool,
  ty : @ast.Type,
  func_name : String,
  decl_line : Int,
) -> @bytecode.Symbol {
  {
    name,
    addr,
    is_local,
    ty,
    scope_depth: if is_local {
      1
    } else {
      0
    },
    func_name,
    decl_line,
  }
}

///|
fn mkframe(
  func_name : String,
  locals_base : UInt,
  caller_line : Int,
) -> CallFrame {
  {
    return_ip: Some(0),
    locals_base,
    local_count: 0,
    func_name,
    original_stack_top: 0U,
    caller_line,
    local_buffers: [],
  }
}

///|
/// 锚一：行读口 + vis take 取出即清（两次 take 第二次空）。
test "observe_line_and_vis_take" {
  let vm = VitroVM::new()
  assert_eq(vm.get_current_line(), 0)
  vm.current_line = 7
  assert_eq(vm.get_current_line(), 7)
  vm.vis_event_queue.push({
    ty: 1,
    line: 3,
    extra0: 0,
    extra1: 0,
    extra2: 0,
    context: "",
  })
  let taken = vm.take_vis_events()
  assert_eq(taken.length(), 1)
  assert_eq(taken[0].line, 3)
  // take 即清：再取为空（消费方幂等）
  assert_eq(vm.take_vis_events().length(), 0)
}

///|
/// 锚二：变量快照作用域——函数归属（他函数局部不入）/ 声明行未到不入 /
/// 同名择优（声明行晚者胜）/ Double 8 字节宽读位值 / 全局恒入。
test "observe_variable_snapshot_scoping" {
  let vm = VitroVM::new()
  vm.set_symbols([
    mksym("g", 0U, false, Int(false, false), "", 0),
    mksym("x", 4U, true, Int(false, false), "main", 2),
    mksym("x", 8U, true, Int(false, false), "main", 5),
    mksym("y", 4U, true, Int(false, false), "other", 1),
    mksym("d", 16U, true, Double(false), "main", 1),
  ])
  vm.call_stack.push(mkframe("main", 0x5000U, 0))
  vm.current_line = 6
  // 内存写：g=42；x(decl2)=111；x(decl5)=43；d=1.5（IEEE 位 0x3FF8...）
  ignore(vm.memory.store_u32(vm.mem_map, @bytecode.GLOBAL_START + 0U, 42U))
  ignore(vm.memory.store_u32(vm.mem_map, 0x5000U + 4U, 111U))
  ignore(vm.memory.store_u32(vm.mem_map, 0x5000U + 8U, 43U))
  ignore(vm.memory.store_u64(vm.mem_map, 0x5000U + 16U, 0x3FF8000000000000UL))
  let snaps = vm.get_variable_snapshot()
  // 名集 = {g, x, d}——y 属 other 函数不入
  let names : Array[String] = []
  for s in snaps {
    names.push(s.name)
  }
  assert_eq(names.length(), 3)
  assert_false(names.contains("y"))
  // 同名 x：decl=5 晚者胜（value=43, addr=0x5008）
  let mut x : VariableSnapshotData? = None
  for s in snaps {
    if s.name == "x" {
      x = Some(s)
    }
  }
  guard x is Some(xs) else { fail("x 必在快照") }
  assert_eq(xs.value, 43L)
  assert_eq(xs.addr, 0x5008U)
  // g 全局恒入
  let mut g_found = false
  for s in snaps {
    if s.name == "g" {
      g_found = true
      assert_eq(s.value, 42L)
    }
  }
  assert_true(g_found)
  // d：Double 宽读按位（1.5 的 IEEE754 位模式经 i64 重解释）
  let mut d_found = false
  for s in snaps {
    if s.name == "d" {
      d_found = true
      assert_eq(s.value, 0x3FF8000000000000UL.reinterpret_as_int64())
    }
  }
  assert_true(d_found)
  // 预热步（current_line=0）：局部保守全跳，全局保留
  vm.current_line = 0
  let warm = vm.get_variable_snapshot()
  assert_eq(warm.length(), 1)
  assert_eq(warm[0].name, "g")
}

///|
/// 锚三：find_variable_name_at_addr——数组元素区间归属（&arr[2] → arr）/
/// 精确命中 / 非数组不覆盖相邻 / 跨帧（由内向外，外层帧按 caller_line
/// 判可见）。
test "observe_find_variable_name_at_addr" {
  let vm = VitroVM::new()
  let arr_ty : @ast.Type = Array(Int(false, false), 4, [4], false, false, [])
  vm.set_symbols([
    mksym("arr", 0U, false, arr_ty, "", 0),
    mksym("s", 32U, false, Int(false, false), "", 0),
    mksym("m", 4U, true, Int(false, false), "main", 3),
  ])
  let base = @bytecode.GLOBAL_START
  // 数组区间：&arr[2] = base+8 → arr
  assert_eq(vm.find_variable_name_at_addr(base + 8U), Some("arr"))
  // 精确命中
  assert_eq(vm.find_variable_name_at_addr(base), Some("arr"))
  // 区间外（末元素后）不命中 arr；s 非数组只精确
  assert_eq(vm.find_variable_name_at_addr(base + 16U), None)
  assert_eq(vm.find_variable_name_at_addr(base + 32U), Some("s"))
  assert_eq(vm.find_variable_name_at_addr(base + 36U), None)
  // 跨帧：callee(f) 内层无局部；外层 main 的 m 可见（frame_line=caller_line
  // ≥ decl_line=3）——由内向外命中
  vm.call_stack.push(mkframe("main", 0x5000U, 10))
  vm.call_stack.push(mkframe("f", 0x6000U, 0))
  vm.current_line = 10
  assert_eq(vm.find_variable_name_at_addr(0x5004U), Some("m"))
}

///|
/// 锚四：数组快照——256 截断（U2#10）+ Char 元素形态（可打印 'c' /
/// 域外按 i8 数值）+ int 数组元素文本 + element_ty 显示名。
test "observe_array_snapshots_truncation_and_chars" {
  let vm = VitroVM::new()
  let char_arr : @ast.Type = Array(
    Char(false, false),
    300,
    [300],
    false,
    false,
    [],
  )
  let int_arr : @ast.Type = Array(Int(false, false), 2, [2], false, false, [])
  vm.set_symbols([
    mksym("big", 0U, false, char_arr, "", 0),
    mksym("ci", 512U, false, int_arr, "", 0),
  ])
  let base = @bytecode.GLOBAL_START
  ignore(vm.memory.store_u32(vm.mem_map, base + 0U, 0x0000C841U)) // 小端：[0]=0x41'A', [1]=0xC8
  ignore(vm.memory.store_u32(vm.mem_map, base + 512U, 7U))
  let snaps = vm.get_array_snapshots()
  assert_eq(snaps.length(), 2)
  let mut big : ArraySnapshotData? = None
  let mut ci : ArraySnapshotData? = None
  for s in snaps {
    if s.name == "big" {
      big = Some(s)
    }
    if s.name == "ci" {
      ci = Some(s)
    }
  }
  guard big is Some(b) else { fail("big 必在") }
  guard ci is Some(c) else { fail("ci 必在") }
  // 300 > 256：截断 + 标记（消费方不得当全量）
  assert_true(b.truncated)
  assert_eq(b.elements.length(), 256)
  assert_eq(b.element_ty, "char")
  // Char 形态：65 可打印 'A'；200 域外按 i8 → -56
  assert_eq(b.elements[0], "'A'")
  assert_eq(b.elements[1], "-56")
  assert_false(c.truncated)
  assert_eq(c.elements.length(), 2)
  assert_eq(c.elements[0], "7")
  assert_eq(c.element_ty, "int")
}
