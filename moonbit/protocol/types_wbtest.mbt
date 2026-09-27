// DTO 族白盒锚（S7 批一号）：StepPayload 全 14 字段构造与读取锚
// （字段名/类型语义逐一对齐 Rust types.rs）+ PointerStatus 序列化文本。

///|
test "step_payload_all_fourteen_fields_constructible" {
  let payload : StepPayload = {
    step_index: 42,
    code_line: 12,
    func_name: "main",
    semantic_label: "调用 printf",
    algorithm_step: Some({
      algorithm_name: "bubble_sort",
      display_name: "冒泡排序",
      phase: "compare",
      description: "比较相邻元素",
    }),
    local_vars: [
      { name: "a", addr: 4096, is_local: true, ty_name: "int", value: "3", },
    ],
    call_stack: [{ func_name: "main", return_line: 0, }],
    vis_events: [
      { ty: 1, line: 12, extra0: 3, extra1: 4, extra2: 0, context: "swap", },
    ],
    heatmap_line: 12,
    heatmap_count: 7,
    accessed_vars: [
      { name: "a", access_type: "Read", },
      { name: "b", access_type: "Write", },
    ],
    array_snapshots: [
      {
        name: "arr",
        element_ty: "int",
        elements: ["1", "2", "3"],
        truncated: false,
      },
    ],
    pointer_snapshots: [
      {
        name: "p",
        addr: 8192,
        ty_name: "int*",
        target_addr: 4096,
        target_name: "a",
        status: Valid,
      },
    ],
    root_cause_hint: Some({
      category: "OffByOne",
      one_liner: "循环边界越界一处",
      related_lines: [12, 13],
      suggested_fix_kind: "ChangeLeToLt",
      suggested_fix_line: Some(12),
      suggested_fix_desc: Some("将 <= 改为 <"),
    }),
  }
  // 读取锚：14 字段逐一（字段名语义与 Rust 侧逐一对齐）
  assert_eq(payload.step_index, 42)
  assert_eq(payload.code_line, 12)
  assert_eq(payload.func_name, "main")
  assert_eq(payload.semantic_label, "调用 printf")
  match payload.algorithm_step {
    Some(a) => assert_eq(a.algorithm_name, "bubble_sort")
    None => fail("algorithm_step 应为 Some")
  }
  assert_eq(payload.local_vars.length(), 1)
  assert_eq(payload.local_vars[0].addr, 4096)
  assert_true(payload.local_vars[0].is_local)
  assert_eq(payload.call_stack[0].func_name, "main")
  assert_eq(payload.call_stack[0].return_line, 0)
  assert_eq(payload.vis_events[0].context, "swap")
  assert_eq(payload.vis_events[0].extra2, 0)
  assert_eq(payload.heatmap_line, 12)
  assert_eq(payload.heatmap_count, 7)
  assert_eq(payload.accessed_vars[1].access_type, "Write")
  assert_eq(payload.array_snapshots[0].elements.length(), 3)
  assert_false(payload.array_snapshots[0].truncated)
  match payload.pointer_snapshots[0].status {
    Valid => ()
    _ => fail("status 应为 Valid")
  }
  match payload.root_cause_hint {
    Some(h) => {
      assert_eq(h.related_lines.length(), 2)
      assert_eq(h.suggested_fix_line, Some(12))
    }
    None => fail("root_cause_hint 应为 Some")
  }
}

///|
test "step_payload_optional_fields_default_none" {
  // 空 payload 形态（协议消费方解码前/无标注步）
  let payload : StepPayload = {
    step_index: 0,
    code_line: -1,
    func_name: "",
    semantic_label: "",
    algorithm_step: None,
    local_vars: [],
    call_stack: [],
    vis_events: [],
    heatmap_line: -1,
    heatmap_count: 0,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots: [],
    root_cause_hint: None,
  }
  assert_true(payload.algorithm_step is None)
  assert_true(payload.root_cause_hint is None)
  assert_eq(payload.local_vars.length(), 0)
}

///|
test "pointer_status_json_text_aligns_serde" {
  // serde enum 序列化形态：裸字符串（Rust 侧 PointerStatus Serialize）
  assert_eq(Valid.to_json_text(), "Valid")
  assert_eq(Freed.to_json_text(), "Freed")
  assert_eq(Null.to_json_text(), "Null")
  assert_eq(Dangling.to_json_text(), "Dangling")
}

///|
test "pointer_status_ordering_total" {
  // derive(Compare) 冒烟：同一变体相等、不同变体有序（快照 diff 排序用）
  assert_true(Valid == Valid)
  assert_true(Valid != Dangling)
  assert_true(Valid.compare(Freed) < 0)
  assert_true(Dangling.compare(Null) > 0)
}

///|
test "heatmap_data_tuple_semantics" {
  // line_counts 保持 Rust Vec<(i32, u64)> 元组语义
  let data : HeatmapData = {
    line_counts: [(3, 100), (7, 250)],
    max_count: 250,
  }
  assert_eq(data.line_counts.length(), 2)
  assert_eq(data.line_counts[0].0, 3)
  assert_eq(data.line_counts[1].1, 250)
  assert_eq(data.max_count, 250)
}
