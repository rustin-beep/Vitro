// 黑盒测试（S7 批一号）：对外面消费面点名——本包全部 pub 符号经
// @protocol. 形态消费（moonbit_surface 边表登记依据）。

///|
test "blackbox_schema_surface" {
  // 常量 + 白名单 + 台账
  assert_eq(@protocol.SCHEMA_VERSION, "v0.1")
  assert_eq(@protocol.SCHEMA_V0_1_FROZEN_AT, "2026-09-12")
  let fields = @protocol.step_payload_fields_v0_1()
  assert_eq(fields.length(), 14)
  assert_eq(fields[0], "step_index")
  assert_eq(fields[13], "root_cause_hint")
  let reserved = @protocol.reserved_fields_v0_2()
  assert_eq(reserved.length(), 4)
  assert_eq(reserved[3], "current_exception")
  let checklist = @protocol.v0_2_activation_checklist()
  assert_eq(checklist.length(), 5)
  let ledger : Array[@protocol.SchemaFieldPlan] = @protocol.v0_2_field_ledger()
  assert_eq(ledger.length(), 7)
  let contracts : Array[@protocol.BehaviorContract] = @protocol.behavior_contracts()
  assert_eq(contracts.length(), 5)
  // emitter
  let json = @protocol.contracts_json()
  assert_true(json.contains("\"schema\":\"v0.1\""))
}

///|
test "blackbox_granularity_surface" {
  let samples : Array[@protocol.UnwindSample] = [
    { step_index: 1, unwinding: false, unwind_frames_left: 0, },
    { step_index: 2, unwinding: true, unwind_frames_left: 2, },
    { step_index: 3, unwinding: true, unwind_frames_left: 1, },
    { step_index: 4, unwinding: false, unwind_frames_left: 0, },
  ]
  assert_true(@protocol.check_unwinding_granularity(samples) is Ok(_))
  let merged : Array[@protocol.UnwindSample] = [
    { step_index: 1, unwinding: false, unwind_frames_left: 0, },
    { step_index: 2, unwinding: true, unwind_frames_left: 2, },
    { step_index: 3, unwinding: true, unwind_frames_left: 0, },
  ]
  assert_true(@protocol.check_unwinding_granularity(merged) is Err(_))
}

///|
test "blackbox_vocabulary_surface" {
  let vocab : Array[@protocol.SemanticLabelKind] = @protocol.semantic_label_vocabulary()
  assert_eq(vocab.length(), 14)
  assert_eq(@protocol.classify("返回"), Some("return"))
  assert_eq(@protocol.classify("第 12 行"), Some("line_fallback"))
  assert_eq(@protocol.classify("未知标签"), None)
  assert_true(@protocol.kind_by_id("swap") is Some(_))
  assert_true(@protocol.vocabulary_json().contains("\"labels\":["))
}

///|
test "blackbox_dto_surface" {
  // DTO 全族点名构造（协议面 = 消费方解码后的状态形态）
  let event : @protocol.VisEvent = {
    ty: 0,
    line: 1,
    extra0: 0,
    extra1: 0,
    extra2: 0,
    context: "",
  }
  let hint : @protocol.RootCauseHint = {
    category: "None",
    one_liner: "",
    related_lines: [],
    suggested_fix_kind: "None",
    suggested_fix_line: None,
    suggested_fix_desc: None,
  }
  let algo : @protocol.AlgorithmStepSnapshot = {
    algorithm_name: "",
    display_name: "",
    phase: "",
    description: "",
  }
  let pointer : @protocol.PointerSnapshot = {
    name: "p",
    addr: 0,
    ty_name: "int*",
    target_addr: 0,
    target_name: "",
    status: @protocol.PointerStatus::Null,
  }
  let accessed : @protocol.AccessedVar = { name: "x", access_type: "Read", }
  let variable : @protocol.ApiVariableSnapshot = {
    name: "x",
    addr: 0,
    is_local: true,
    ty_name: "int",
    value: "0",
  }
  let arr : @protocol.ArraySnapshot = {
    name: "arr",
    element_ty: "int",
    elements: [],
    truncated: false,
  }
  let frame : @protocol.ApiFrameInfo = { func_name: "main", return_line: 0, }
  let payload : @protocol.StepPayload = {
    step_index: 1,
    code_line: 1,
    func_name: "main",
    semantic_label: "返回",
    algorithm_step: Some(algo),
    local_vars: [variable],
    call_stack: [frame],
    vis_events: [event],
    heatmap_line: 1,
    heatmap_count: 1,
    accessed_vars: [accessed],
    array_snapshots: [arr],
    pointer_snapshots: [pointer],
    root_cause_hint: Some(hint),
  }
  let meta : @protocol.StepMeta = {
    code_line: 1,
    func_name: "main",
    loop_depth: 0,
    semantic_label: "返回",
  }
  let summary : @protocol.DebugSummary = {
    local_vars: [],
    call_stack: [],
    output_len: 0,
  }
  let delta : @protocol.HeatmapDelta = { line: 1, count: 1, }
  let run : @protocol.UnifiedRunResult = {
    success: true,
    error: None,
    total_steps: 1,
    finished: true,
  }
  let auto : @protocol.AutoStepResult = {
    payloads: [payload],
    finished: true,
    trapped: false,
    waiting_input: false,
    paused: false,
    current_line: 1,
    trap_message: None,
    cache_start_step: 0,
  }
  let seek : @protocol.SeekResult = {
    success: true,
    payload: None,
    error: None,
  }
  let heatmap : @protocol.HeatmapData = { line_counts: [(1, 1)], max_count: 1, }
  assert_eq(auto.payloads.length(), 1)
  assert_eq(meta.loop_depth, 0)
  assert_eq(summary.output_len, 0)
  assert_eq(delta.count, 1)
  assert_true(run.finished)
  assert_true(seek.payload is None)
  assert_eq(heatmap.max_count, 1)
  assert_eq(@protocol.PointerStatus::Null.to_json_text(), "Null")
}

///|
test "blackbox_stream_surface" {
  // stream 差分编码四函数消费面点名（encode_step_delta 为 encode_payloads
  // 内部路径的独立出口——TS 侧同构消费；显式点名保面闸）
  let p0 : @protocol.StepPayload = {
    step_index: 0,
    code_line: 1,
    func_name: "main",
    semantic_label: "返回",
    algorithm_step: None,
    local_vars: [
      { name: "i", addr: 0, is_local: true, ty_name: "int", value: "0", },
    ],
    call_stack: [{ func_name: "main", return_line: 0, }],
    vis_events: [],
    heatmap_line: 1,
    heatmap_count: 1,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots: [],
    root_cause_hint: None,
  }
  // 第二步仅 i 值变化（黑盒侧不用 mutate 链——直接构造）
  let p1 : @protocol.StepPayload = {
    step_index: 1,
    code_line: 2,
    func_name: "main",
    semantic_label: "返回",
    algorithm_step: None,
    local_vars: [
      { name: "i", addr: 0, is_local: true, ty_name: "int", value: "1", },
    ],
    call_stack: [{ func_name: "main", return_line: 0, }],
    vis_events: [],
    heatmap_line: 2,
    heatmap_count: 1,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots: [],
    root_cause_hint: None,
  }
  let batch = @protocol.encode_payloads([p0, p1], 0)
  assert_eq(batch.deltas.length(), 1)
  // 两个 encode 细粒度出口的签名含 priv SymbolTable 跨包不可调（照搬
  // Rust pub+priv 形态，surface_allowlist 登记）——黑盒不点名
  let single = @protocol.encode_payloads([p0], 7)
  assert_eq(@protocol.decode_batch(single).length(), 1)
  assert_eq(single.cache_start_step, 7)
}
