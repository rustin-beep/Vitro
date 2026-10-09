// M14 根因提示锚（S8 analysis 批，2026-10-03）：analyze_trap 六臂单元锚
//（直调——构造 StepPayload 历史与 trap 文案，免 vm 程序装配）+ 除零端到端。
// 照搬忠实度：文案子串判据/字段值全部对齐 oracle trace_analyzer tests.rs
// 的形态（两侧同文案——vm trap 渲染单源）。

///|
fn make_step(
  step_index : Int,
  code_line : Int,
  vars : Array[(String, String)],
  ptrs : Array[(String, @protocol.PointerStatus)],
) -> @protocol.StepPayload {
  let local_vars : Array[@protocol.ApiVariableSnapshot] = []
  for v in vars {
    local_vars.push({
      name: v.0,
      addr: 0U,
      is_local: true,
      ty_name: "int",
      value: v.1,
    })
  }
  let pointer_snapshots : Array[@protocol.PointerSnapshot] = []
  for p in ptrs {
    pointer_snapshots.push({
      name: p.0,
      addr: 0U,
      ty_name: "int*",
      target_addr: 0U,
      target_name: "",
      status: p.1,
    })
  }
  {
    step_index,
    code_line,
    func_name: "main",
    semantic_label: "active",
    algorithm_step: None,
    local_vars,
    call_stack: [],
    vis_events: [],
    heatmap_line: 0,
    heatmap_count: 0UL,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots,
    root_cause_hint: None,
  }
}

///|
fn no_line(_l : Int) -> String {
  ""
}

///|
test "trace_analyze_div_zero" {
  let steps = [
    make_step(0, 1, [("x", "42"), ("d", "0")], []),
    make_step(1, 2, [("x", "42"), ("d", "0")], []),
  ]
  guard analyze_trap(
      steps, 1, "[divide-zero] 除零错误：你试图用 42 除以 0。", no_line,
    )
    is Some(h) else {
    fail("除零须出 hint")
  }
  assert_eq(h.category, "DivZero")
  assert_eq(h.suggested_fix_kind, "AvoidDivZero")
  assert_true(h.one_liner.contains("当前值为 0 的变量: d"))
}

///|
test "trace_analyze_use_after_free" {
  let msg = "[uaf] Use-After-Free (E3060)：你正在读取一块在第 3 行（第 19 步）被 free 的内存（由第 2 行的 malloc 分配）"
  let steps = [
    make_step(0, 2, [], [("p", @protocol.PointerStatus::Freed)]),
    make_step(1, 4, [], [("p", @protocol.PointerStatus::Freed)]),
  ]
  guard analyze_trap(steps, 1, msg, no_line) is Some(h) else {
    fail("UAF 须出 hint")
  }
  assert_eq(h.category, "UseAfterFree")
  assert_eq(h.suggested_fix_kind, "SetNullAfterFree")
  assert_eq(h.suggested_fix_line, Some(3))
  // related = [alloc 2, freed 3, trap line 4] 去重升序
  assert_eq(h.related_lines, [2, 3, 4])
  assert_true(h.one_liner.contains("第 2 行被分配"))
}

///|
test "trace_analyze_double_free" {
  let msg = "[uaf] Double-Free (E3061)：你正在释放一块在第 3 行（第 19 步）已被 free 的内存（由第 2 行的 malloc 分配）"
  let steps = [make_step(0, 4, [], [])]
  guard analyze_trap(steps, 0, msg, no_line) is Some(h) else {
    fail("Double-Free 须出 hint")
  }
  assert_eq(h.category, "DoubleFree")
  assert_eq(h.suggested_fix_kind, "SetNullAfterFree")
  // 病 4 锚（#47，2026-10-09）：one_liner 行号语义必须正确——freed_line 是
  // 首次 free 行、当前行是第二次 free；旧文案「第一次释放发生在第 {alloc}
  // 行」把 malloc 行说成首次释放，误导学生（对照 analyze_use_after_free
  // 的 alloc/free 分清口径，系漏改）。
  assert_true(h.one_liner.contains("已被释放"))
  assert_true(h.one_liner.contains("又 free 了一次"))
}

///|
test "trace_analyze_null_deref" {
  let steps = [make_step(0, 5, [], [("q", @protocol.PointerStatus::Null)])]
  guard analyze_trap(steps, 0, "访问了 NULL 指针", no_line) is Some(h) else {
    fail("NULL 须出 hint")
  }
  assert_eq(h.category, "NullDeref")
  assert_eq(h.suggested_fix_kind, "AddNullCheck")
  assert_true(h.one_liner.contains("当前为 NULL 的指针: q"))
}

///|
test "trace_analyze_bounds_generic" {
  // 无匹配循环变量（local_vars 值不等于下标）→ GenericBounds
  let msg = "[deny] 数组越界：你访问了 arr[5]，但数组 'arr' 只有 5 个元素"
  let steps = [make_step(0, 3, [("total", "9")], [])]
  guard analyze_trap(steps, 0, msg, no_line) is Some(h) else {
    fail("越界须出 hint")
  }
  assert_eq(h.category, "GenericBounds")
  assert_eq(h.suggested_fix_kind, "None")
  assert_true(h.one_liner.contains("'arr'"))
}

///|
test "trace_analyze_bounds_off_by_one" {
  // 经典 OffByOne：i 从 0 单调 +1 到 size，源码行含 <=
  let msg = "[deny] 数组越界：你访问了 arr[5]，但数组 'arr' 只有 5 个元素"
  let steps = [
    make_step(0, 2, [("i", "0")], []),
    make_step(1, 2, [("i", "1")], []),
    make_step(2, 2, [("i", "2")], []),
    make_step(3, 2, [("i", "3")], []),
    make_step(4, 2, [("i", "4")], []),
    make_step(5, 2, [("i", "5")], []),
  ]
  let get_line = fn(l : Int) -> String {
    if l == 2 {
      "for (i = 0; i <= n; i++) { sum += arr[i]; }"
    } else {
      ""
    }
  }
  guard analyze_trap(steps, 5, msg, get_line) is Some(h) else {
    fail("OffByOne 须出 hint")
  }
  assert_eq(h.category, "OffByOne")
  assert_eq(h.suggested_fix_kind, "ChangeLeToLt")
  assert_eq(h.suggested_fix_line, Some(2))
  assert_true(h.one_liner.contains("'<=' 改为 '<'"))
}

///|
test "engine_run_batch_trap_root_cause_hint_divzero" {
  // 端到端：除零程序的 trap 帧带 root_cause_hint（DivZero）——M14 接线
  //（此前 StepPayload.root_cause_hint 恒 None，serve 头注分叉①销案）
  let vm = @vm.VitroVM::new()
  vm.load_program(
    code_of([
      instr_at(@opcode.PushConst, 0, 1),
      instr_at(@opcode.PushConst, 0, 2),
      instr_at(@opcode.Div, 0, 3),
      instr_at(@opcode.Nop, 0, 3),
    ]),
  )
  let e = UnifiedEngine::new()
  let src = fake_src()
  guard e.run_batch(vm, src, 10) is Ok(r) else { fail("trap 走 Ok 通道") }
  assert_true(r.trapped)
  let n = r.payloads.length()
  guard r.payloads[n - 1].root_cause_hint is Some(h) else {
    fail("trap 帧须带 hint")
  }
  assert_eq(h.category, "DivZero")
}

///|
test "trace_analyze_bounds_wrong_init" {
  // oracle test_infer_wrong_init 照搬：i 从 1 起单调 +1，accessed=5=size
  let hist : Array[Int] = [1, 2, 3, 4, 5]
  let loop_info : LoopInfo = { lines: [3], has_le: false, increment: Some(1), }
  let cat = infer_bounds_category(hist, 5, 5, loop_info)
  assert_eq(cat.as_str(), "WrongInit")
  let (one_liner, fix_kind, fix_line, fix_desc) = build_bounds_hint(
    cat, "i", "arr", 5, 5, loop_info, hist,
  )
  assert_true(one_liner.contains("从 1 开始"))
  assert_true(one_liner.contains("改为 0"))
  assert_eq(fix_kind, "FixLoopStart")
  assert_eq(fix_line, Some(3))
  assert_eq(fix_desc, Some("将 i 的初始值 1 改为 0"))
}

///|
test "trace_analyze_bounds_wrong_increment" {
  // oracle test_infer_wrong_increment 照搬：步长 2 跳越，accessed=6>size=5
  let hist : Array[Int] = [0, 2, 4, 6]
  let loop_info : LoopInfo = {
    lines: [3, 5],
    has_le: false,
    increment: Some(2),
  }
  let cat = infer_bounds_category(hist, 6, 5, loop_info)
  assert_eq(cat.as_str(), "WrongIncrement")
  let (one_liner, fix_kind, fix_line, fix_desc) = build_bounds_hint(
    cat, "i", "arr", 6, 5, loop_info, hist,
  )
  assert_true(one_liner.contains("步长是 2"))
  assert_eq(fix_kind, "FixLoopIncrement")
  assert_eq(fix_line, Some(3))
  assert_eq(fix_desc, Some("将步长 2 改为 1"))
}

///|
test "trace_analyze_bounds_uninitialized_index" {
  // oracle test_infer_uninitialized_index 照搬：历史过短（<2）
  let hist : Array[Int] = []
  let loop_info = LoopInfo::new()
  let cat = infer_bounds_category(hist, 99, 5, loop_info)
  assert_eq(cat.as_str(), "UninitializedIndex")
  let (one_liner, fix_kind, fix_line, fix_desc) = build_bounds_hint(
    cat, "idx", "arr", 99, 5, loop_info, hist,
  )
  assert_true(one_liner.contains("未初始化"))
  assert_eq(fix_kind, "InitVariable")
  assert_eq(fix_line, None)
  assert_eq(fix_desc, Some("初始化 'idx'"))
}
