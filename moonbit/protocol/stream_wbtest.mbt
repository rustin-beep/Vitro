// stream 差分编码白盒锚（S7 批一号段二）：8 锚照搬 stream.rs tests 模块
// + 符号表边界锚（索引 0 预留空串 / 空输入形态）。

///|
fn make_payload(step : Int, vars : Array[ApiVariableSnapshot]) -> StepPayload {
  {
    step_index: step,
    code_line: step + 1,
    func_name: "main",
    semantic_label: "step \{step}",
    algorithm_step: None,
    local_vars: vars,
    call_stack: [{ func_name: "main", return_line: 0, }],
    vis_events: [],
    heatmap_line: step + 1,
    heatmap_count: 1,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots: [],
    root_cause_hint: None,
  }
}

///|
fn mkvar(name : String, ty : String, value : String) -> ApiVariableSnapshot {
  { name, addr: 0, is_local: true, ty_name: ty, value, }
}

///|

///| Rust p.clone() 的深拷贝等价物（MoonBit struct/Array 按引用共享，

///|
/// 测试 mutate 形态须深重建到可变层——String 不可变共享安全）。
fn clone_payload(p : StepPayload) -> StepPayload {
  {
    step_index: p.step_index,
    code_line: p.code_line,
    func_name: p.func_name,
    semantic_label: p.semantic_label,
    algorithm_step: match p.algorithm_step {
      Some(a) =>
        Some({
          algorithm_name: a.algorithm_name,
          display_name: a.display_name,
          phase: a.phase,
          description: a.description,
        })
      None => None
    },
    local_vars: p.local_vars.map(v => {
      name: v.name,
      addr: v.addr,
      is_local: v.is_local,
      ty_name: v.ty_name,
      value: v.value,
    }),
    call_stack: p.call_stack.map(f => {
      func_name: f.func_name,
      return_line: f.return_line,
    }),
    vis_events: p.vis_events.map(e => {
      ty: e.ty,
      line: e.line,
      extra0: e.extra0,
      extra1: e.extra1,
      extra2: e.extra2,
      context: e.context,
    }),
    heatmap_line: p.heatmap_line,
    heatmap_count: p.heatmap_count,
    accessed_vars: p.accessed_vars.map(a => {
      name: a.name,
      access_type: a.access_type,
    }),
    array_snapshots: p.array_snapshots.map(a => {
      name: a.name,
      element_ty: a.element_ty,
      elements: a.elements.map(e => e),
      truncated: a.truncated,
    }),
    pointer_snapshots: p.pointer_snapshots.map(pt => {
      name: pt.name,
      addr: pt.addr,
      ty_name: pt.ty_name,
      target_addr: pt.target_addr,
      target_name: pt.target_name,
      status: pt.status,
    }),
    root_cause_hint: p.root_cause_hint,
  }
}

///|
test "stream_empty_payloads" {
  let batch = encode_payloads([], 0)
  assert_true(batch.base_payloads.is_empty())
  assert_true(batch.deltas.is_empty())
  assert_eq(batch.symbol_table.length(), 1, msg="空字符串预留位")
  assert_eq(batch.symbol_table[0], "", msg="索引 0 = 空串")
}

///|
test "stream_single_payload_roundtrip" {
  let payloads = [
    make_payload(0, [mkvar("i", "int", "0"), mkvar("n", "int", "5")]),
  ]
  let batch = encode_payloads(payloads, 0)
  let decoded = decode_batch(batch)
  assert_eq(decoded.length(), 1)
  assert_eq(decoded[0].step_index, 0)
  assert_eq(decoded[0].local_vars.length(), 2)
  assert_eq(decoded[0].local_vars[0].name, "i")
  assert_eq(decoded[0].local_vars[0].value, "0")
}

///|
test "stream_delta_encoding_roundtrip" {
  let payloads = [
    make_payload(0, [mkvar("i", "int", "0"), mkvar("n", "int", "5")]),
    make_payload(1, [mkvar("i", "int", "1"), mkvar("n", "int", "5")]),
    make_payload(2, [mkvar("i", "int", "2"), mkvar("n", "int", "5")]),
  ]
  let batch = encode_payloads(payloads, 0)
  assert_eq(batch.base_payloads.length(), 1)
  assert_eq(batch.deltas.length(), 2)
  // 验证差分：只有 i 变化，n 不变
  assert_eq(batch.deltas[0].var_deltas.length(), 1)
  assert_eq(batch.deltas[0].var_deltas[0].value, "1")
  assert_true(batch.deltas[0].new_vars.is_empty())
  assert_true(batch.deltas[0].removed_var_name_indices.is_empty())
  let decoded = decode_batch(batch)
  assert_eq(decoded.length(), 3)
  assert_eq(decoded[1].local_vars[0].value, "1")
  assert_eq(decoded[2].local_vars[0].value, "2")
  assert_eq(decoded[2].local_vars[1].value, "5", msg="n 未变")
}

///|
test "stream_variable_add_remove_roundtrip" {
  let payloads = [
    make_payload(0, [mkvar("i", "int", "0")]),
    make_payload(1, [mkvar("i", "int", "1"), mkvar("j", "int", "10")]),
    make_payload(2, [mkvar("j", "int", "11")]),
  ]
  let batch = encode_payloads(payloads, 0)
  assert_eq(batch.deltas[0].new_vars.length(), 1, msg="j 新增")
  assert_eq(
    batch.deltas[1].removed_var_name_indices.length(),
    1,
    msg="i 移除",
  )
  assert_eq(batch.deltas[1].var_deltas.length(), 1, msg="j 变化")
  let decoded = decode_batch(batch)
  assert_eq(decoded.length(), 3)
  assert_eq(decoded[0].local_vars.length(), 1)
  assert_eq(decoded[1].local_vars.length(), 2)
  assert_eq(decoded[2].local_vars.length(), 1)
  assert_eq(decoded[2].local_vars[0].name, "j")
  assert_eq(decoded[2].local_vars[0].value, "11")
}

///|
test "stream_symbol_table_dedup" {
  let payloads = [
    make_payload(0, [mkvar("i", "int", "0")]),
    make_payload(1, [mkvar("i", "int", "1")]),
  ]
  let batch = encode_payloads(payloads, 0)
  // 重复字符串（"main"/"i"/"int"）必须被符号表去重
  let seen : Map[String, Bool] = Map([])
  for s in batch.symbol_table {
    assert_false(
      seen.get(s).unwrap_or(false),
      msg="符号表出现重复条目：\{s}",
    )
    seen.set(s, true)
  }
}

///|
test "stream_call_stack_delta" {
  let p0 = make_payload(0, [mkvar("i", "int", "0")])
  let p1 = make_payload(1, [mkvar("i", "int", "1")])
  let p2 = make_payload(2, [mkvar("i", "int", "2")])
  // p1 调用栈与 p0 相同（make_payload 同构），p2 进入 foo
  p2.call_stack = [
    { func_name: "main", return_line: 3, },
    { func_name: "foo", return_line: 0, },
  ]
  let batch = encode_payloads([p0, p1, p2], 0)
  assert_true(batch.deltas[0].call_stack is None, msg="p1 调用栈未变")
  assert_true(batch.deltas[1].call_stack is Some(_), msg="p2 调用栈变化")
  match batch.deltas[1].call_stack {
    Some(frames) => assert_eq(frames.length(), 2)
    None => fail("上已断言 Some")
  }
  let decoded = decode_batch(batch)
  assert_eq(decoded[2].call_stack.length(), 2)
  assert_eq(decoded[2].call_stack[1].func_name, "foo")
}

///|
test "stream_array_and_pointer_delta" {
  let p0 = make_payload(0, [mkvar("i", "int", "0")])
  p0.array_snapshots = [
    { name: "a", element_ty: "int", elements: ["1", "2"], truncated: false, },
  ]
  p0.pointer_snapshots = [
    {
      name: "p",
      addr: 100,
      ty_name: "int*",
      target_addr: 200,
      target_name: "x",
      status: Valid,
    },
  ]
  let p1 = clone_payload(p0)
  // p1 数组变化（元素值改变），指针不变
  p1.array_snapshots[0].elements = ["3", "2"]
  let p2 = clone_payload(p1)
  // p2 删除数组 a、新增数组 b；指针 p 目标改变
  p2.array_snapshots = [
    { name: "b", element_ty: "int", elements: ["7"], truncated: false, },
  ]
  p2.pointer_snapshots[0].target_addr = 300
  let batch = encode_payloads([p0, p1, p2], 0)
  // p1：数组变化，指针未变
  assert_true(batch.deltas[0].array_snapshots is Some(_))
  assert_true(batch.deltas[0].pointer_snapshots is None)
  // p2：数组替换 + 删除 a，指针变化
  assert_true(batch.deltas[1].array_snapshots is Some(_))
  assert_false(batch.deltas[1].removed_array_name_indices.is_empty())
  assert_true(batch.deltas[1].pointer_snapshots is Some(_))
  let decoded = decode_batch(batch)
  assert_eq(decoded[2].array_snapshots.length(), 1)
  assert_eq(decoded[2].array_snapshots[0].name, "b")
  assert_eq(decoded[2].pointer_snapshots[0].target_addr, 300)
}

///|
test "stream_accessed_vars_and_vis_events_delta" {
  let p0 = make_payload(0, [mkvar("i", "int", "0")])
  p0.accessed_vars = [{ name: "i", access_type: "Read", }]
  p0.vis_events = [
    { ty: 1, line: 10, extra0: 0, extra1: 0, extra2: 0, context: "swap", },
  ]
  let p1 = clone_payload(p0)
  p1.accessed_vars[0].access_type = "Write"
  // vis_events 不变
  let p2 = clone_payload(p1)
  p2.vis_events = []
  p2.accessed_vars = p1.accessed_vars
  let batch = encode_payloads([p0, p1, p2], 0)
  assert_true(batch.deltas[0].accessed_vars is Some(_))
  assert_true(batch.deltas[0].vis_events is None, msg="未变")
  assert_true(batch.deltas[1].vis_events is Some(_), msg="变为空列表")
  match batch.deltas[1].vis_events {
    Some(events) => assert_eq(events.length(), 0)
    None => fail("上已断言 Some")
  }
  let decoded = decode_batch(batch)
  assert_eq(decoded[1].accessed_vars[0].access_type, "Write")
  assert_eq(decoded[2].vis_events.length(), 0)
}

///|
test "stream_symbol_table_index_zero_reserved" {
  // 索引 0 预留空串：首个真实字符串必从索引 1 起
  let payloads = [make_payload(0, [mkvar("i", "int", "0")])]
  let batch = encode_payloads(payloads, 0)
  assert_eq(batch.symbol_table[0], "")
  let real = batch.base_payloads[0].func_name_idx
  assert_true(real >= 1, msg="func_name 索引必 >= 1（0 为预留位）")
  assert_eq(batch.symbol_table[real], "main")
}

///|
test "stream_cache_start_step_passthrough" {
  // 窗口起点直通 + current_line 取末步 code_line（Rust 同形）
  let payloads = [
    make_payload(0, [mkvar("i", "int", "0")]),
    make_payload(1, [mkvar("i", "int", "1")]),
  ]
  let batch = encode_payloads(payloads, 42)
  assert_eq(batch.cache_start_step, 42)
  assert_eq(batch.current_line, 2, msg="current_line = 末步 code_line")
  // 状态八字段 encode 侧默认值（语义由 gateway serve 批填充）
  assert_false(batch.finished)
  assert_false(batch.trapped)
  assert_false(batch.waiting_input)
  assert_false(batch.paused)
  assert_true(batch.trap_message is None)
}
// decode_batch 不 mutate 输入（回放幂等）——修复前本文件必须红。

///|
test "j9_vis_events_base_frame_not_clobbered" {
  let p0 = make_payload(0, [mkvar("i", "int", "0")])
  p0.vis_events = [
    { ty: 1, line: 10, extra0: 0, extra1: 0, extra2: 0, context: "swap", },
  ]
  let p1 = clone_payload(p0)
  p1.vis_events = []
  let batch = encode_payloads([p0, p1], 0)
  let decoded = decode_batch(batch)
  // 修复前：共享引用被 clear ⇒ decoded[0] 也变空（审阅实测实锤）
  assert_eq(
    decoded[0].vis_events.length(),
    1,
    msg="base 帧 vis_events 不得被后续 delta 的空列表覆盖",
  )
}

///|
test "j9_decode_batch_does_not_mutate_input" {
  let p0 = make_payload(0, [mkvar("i", "int", "0")])
  p0.vis_events = [
    { ty: 2, line: 5, extra0: 0, extra1: 0, extra2: 0, context: "cmp", },
  ]
  let p1 = clone_payload(p0)
  p1.vis_events = []
  let batch = encode_payloads([p0, p1], 0)
  let base_events_before = batch.base_payloads[0].vis_events.length()
  ignore(decode_batch(batch))
  assert_eq(
    batch.base_payloads[0].vis_events.length(),
    base_events_before,
    msg="decode_batch 不得 mutate 输入（Rust &不可变借用等价——回放幂等）",
  )
}

///|
test "stream_symbol_table_full_content_anchor" {
  // 符号表全内容锚（审阅 P3：往返锚对「序」零判别力，而符号表插入序
  // 是批四号双宿主字节级对拍核心面）。期望数组 = 独立第二份硬编码。
  // 求值序 = encode_step_payload 的 struct 字面量书写序 = Rust 求值序
  // （审阅探针实证：MoonBit struct 字面量按书写序求值）。
  let p : StepPayload = {
    step_index: 0,
    code_line: 1,
    func_name: "main",
    semantic_label: "step 0",
    algorithm_step: Some({
      algorithm_name: "ALGO",
      display_name: "DISPLAY",
      phase: "PHASE",
      description: "DESC",
    }),
    local_vars: [mkvar("i", "int", "0")],
    call_stack: [],
    vis_events: [],
    heatmap_line: 1,
    heatmap_count: 1,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots: [],
    root_cause_hint: None,
  }
  let batch = encode_payloads([p], 0)
  let expected : Array[String] = [
    "", "main", "step 0", "ALGO", "DISPLAY", "PHASE", "DESC", "i", "int",
  ]
  assert_eq(batch.symbol_table.length(), expected.length())
  for i, want in expected {
    assert_eq(
      batch.symbol_table[i],
      want,
      msg="符号表第 \{i} 项漂移——插入序是批四号字节级对拍面，禁改",
    )
  }
}

///|
test "stream_frame_same_length_change_detected" {
  // 审阅 P3 锚盲区：frame_lists_equal 的 return_line 比较——现有
  // call_stack_delta 锚只用「长度变化」形态，同长变化测不到（突变
  // 实证：去掉 return_line 比较全绿）。本锚补同长 return_line 变化形态。
  let p0 = make_payload(0, [mkvar("i", "int", "0")])
  let p1 = make_payload(1, [mkvar("i", "int", "1")])
  // 同长（1 帧）、func_name 同、仅 return_line 变
  p1.call_stack = [{ func_name: "main", return_line: 3, }]
  let batch = encode_payloads([p0, p1], 0)
  assert_true(
    batch.deltas[0].call_stack is Some(_),
    msg="同长 return_line 变化必须产生 call_stack 差分",
  )
  let decoded = decode_batch(batch)
  assert_eq(decoded[1].call_stack[0].return_line, 3)
}

///|
test "stream_removed_var_reappears_as_new" {
  // 审阅 P3 锚盲区：retain_ref_vars 恒不删突变全绿——需「变量删除后
  // 同名重新出现」形态。突变下 current_full_ref 残留 i ⇒ prev_vars 含
  // i ⇒ 重现走 var_deltas 而非 new_vars ⇒ 本锚红。
  let payloads = [
    make_payload(0, [mkvar("i", "int", "0")]),
    make_payload(1, []),
    make_payload(2, [mkvar("i", "int", "9")]),
  ]
  let batch = encode_payloads(payloads, 0)
  assert_eq(
    batch.deltas[0].removed_var_name_indices.length(),
    1,
    msg="i 删除",
  )
  assert_eq(
    batch.deltas[1].new_vars.length(),
    1,
    msg="删除后的 i 重现必须走 new_vars（removed 链路正确性）",
  )
  let decoded = decode_batch(batch)
  assert_eq(decoded[2].local_vars.length(), 1)
  assert_eq(decoded[2].local_vars[0].name, "i")
  assert_eq(decoded[2].local_vars[0].value, "9")
}

///|
test "stream_get_sym_out_of_bounds_tolerant" {
  // 审阅 P3（可接受级）：get_sym 越界容错读照搬 Rust unwrap_or_default
  // ——白盒直调锚（跨包不可达 priv，直调即锚）。
  assert_eq(get_sym(["a", "b"], 0), "a")
  assert_eq(get_sym(["a", "b"], 1), "b")
  assert_eq(get_sym(["a", "b"], 2), "", msg="越界返回空串")
  assert_eq(get_sym(["a"], -1), "", msg="负索引返回空串")
}
