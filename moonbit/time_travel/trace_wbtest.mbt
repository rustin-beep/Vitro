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

///|
/// root_cause_hint 外置等价锚（#60 批三段一a，2026-10-10）：四族主干
/// （NullDeref/UAF/DoubleFree/DivZero）改造前逐字节基线——改造后须仍绿。
test "hint_migration_snapshot_before" {
  // NullDeref：无 NULL 指针（骨架原样）/ 有（段拼接）
  let h1 = analyze_trap(
    [make_step(0, 5, [], [])],
    0,
    "访问了 NULL 指针区域",
    no_line,
  )
  guard h1 is Some(h) else { fail("NullDeref 须出 hint") }
  assert_eq(
    h.one_liner,
    "试图解引用一个 NULL 指针。NULL 指针不指向任何有效内存。",
  )
  let h1b = analyze_trap(
    [make_step(0, 5, [], [("q", @protocol.PointerStatus::Null)])],
    0,
    "访问了 NULL 指针区域",
    no_line,
  )
  guard h1b is Some(hb) else { fail("须出 hint") }
  assert_eq(
    hb.one_liner,
    "试图解引用一个 NULL 指针。NULL 指针不指向任何有效内存。 当前为 NULL 的指针: q。请在使用前确保指针已被正确初始化（如通过 malloc 或赋值）。",
  )
  // UAF：无 / 有相关指针
  let msg_uaf = "[uaf] Use-After-Free (E3060)：你正在向一块已经在第 2 行（第 19 步）被 free 的内存读取（由第 1 行的 malloc/realloc 分配）"
  let h2 = analyze_trap([make_step(0, 4, [], [])], 0, msg_uaf, no_line)
  guard h2 is Some(u1) else { fail("UAF 须出 hint") }
  assert_eq(
    u1.one_liner,
    "这块内存在第 1 行被分配，在第 2 行被释放，现在又被访问了。free 后请立即将指针置为 NULL，避免继续使用。",
  )
  // DoubleFree：病 4 修订后全串（既有锚 contains——此处逐字节）
  let msg_df = "[double-free] Double-Free (E3061)：你正在 free 一块已经在第 3 行被释放过的内存（由第 2 行的 malloc 分配）"
  let h3 = analyze_trap([make_step(0, 4, [], [])], 0, msg_df, no_line)
  guard h3 is Some(d1) else { fail("DF 须出 hint") }
  assert_eq(
    d1.one_liner,
    "同一块内存在第 3 行已被释放，现在第 4 行又 free 了一次。每次 free(p) 后请立刻执行 p = NULL;，因为对 NULL 重复 free 是安全的。",
  )
  // DivZero：无变量（骨架）/ 被除数形态
  let h4 = analyze_trap(
    [make_step(0, 3, [], [])],
    0,
    "[divide-zero] 除零错误：你试图用 10 除以 0。",
    no_line,
  )
  guard h4 is Some(z1) else { fail("DivZero 须出 hint") }
  assert_eq(
    z1.one_liner,
    "发生了除零错误。除数变成了 0，这在数学上没有定义。 被除数是 10，但除数变成了 0。请确认除法前检查了除数是否为零。",
  )
  // fix_desc 短文案（三族代表）
  assert_eq(h.suggested_fix_desc, Some("使用指针前检查是否为 NULL"))
  assert_eq(u1.suggested_fix_desc, Some("free 后执行 p = NULL"))
  assert_eq(z1.suggested_fix_desc, Some("除法前检查除数是否为 0"))
}

///|
/// bounds hint 外置等价锚（#60 批三段一b，2026-10-10）：build_bounds_hint
/// 五变体代表形态的逐字节基线（直调单元级——LoopInfo/hist_vals 手工构造）。
test "bounds_hint_migration_snapshot_before" {
  let li = LoopInfo::{ lines: [7], has_le: false, increment: Some(1), }
  // OffByOne（带行号）
  let (m1, k1, _, f1) = build_bounds_hint(OffByOne, "i", "a", 5, 5, li, [])
  assert_eq(
    m1, "数组越界是因为第 7 行的循环条件使用了 '<='。数组 'a' 大小为 5，最后一个有效索引是 4。建议将 '<=' 改为 '<'。",
  )
  assert_eq(k1, "ChangeLeToLt")
  assert_eq(f1, Some("将 <= 改为 <"))
  // WrongInit（带行号）
  let (m2, k2, _, f2) = build_bounds_hint(WrongInit, "i", "a", 5, 5, li, [
    1, 2, 3, 4, 5,
  ])
  assert_eq(
    m2, "数组 'a' 访问了越界索引 5。循环变量 'i' 从 1 开始，导致最终访问到索引 5。建议将第 7 行的初始值改为 0。",
  )
  assert_eq(k2, "FixLoopStart")
  assert_eq(f2, Some("将 i 的初始值 1 改为 0"))
  // WrongIncrement（无行号形态）
  let li0 = LoopInfo::{ lines: [], has_le: false, increment: None, }
  let (m3, _, _, f3) = build_bounds_hint(WrongIncrement, "i", "a", 6, 5, li0, [])
  assert_eq(
    m3, "数组 'a' 访问了越界索引 6。循环变量 'i' 的步长是 2，导致跳过了边界检查。建议将步长改为 1，或调整循环条件。",
  )
  assert_eq(f3, Some("将步长 2 改为 1"))
  // UninitializedIndex / Generic（无历史）
  let (m4, _, _, _) = build_bounds_hint(
    UninitializedIndex,
    "idx",
    "a",
    99,
    5,
    li0,
    [],
  )
  assert_eq(
    m4, "索引变量 'idx' 的值是 99，但执行历史太短，可能是变量未初始化或从外部输入读取了非法值。建议在使用前初始化 'idx'。",
  )
  let (m5, _, _, _) = build_bounds_hint(Generic, "i", "a", 5, 5, li0, [])
  assert_eq(
    m5, "数组 'a' 访问了越界索引 5。请检查循环边界或索引计算。",
  )
}
