// schema 契约白盒锚（S7 批一号）：展开粒度判据 5 锚照搬 contracts.rs
// tests 模块 + v0.1 冻结对账锚（字段白名单/预留位/常量/计数）。
// 对账单源：scripts/replay/v01_payload_fields.json（Go/Python 回放驱动
// 共读）；本测试硬编码第二份预期，MoonBit 表与任一侧漂移即红。

///|
fn s(step_index : Int, unwinding : Bool, left : Int) -> UnwindSample {
  { step_index, unwinding, unwind_frames_left: left, }
}

///|
test "unwinding_one_frame_per_step_passes" {
  // 栈深 3：进入展开 → 逐帧 3 → 2 → 1 → catch
  let seq = [
    s(1, false, 0),
    s(2, true, 3),
    s(3, true, 2),
    s(4, true, 1),
    s(5, false, 0),
  ]
  assert_true(
    check_unwinding_granularity(seq) is Ok(_),
    msg="逐帧展开序列必须通过",
  )
}

///|
test "unwinding_with_finally_step_passes" {
  // finally 执行步不弹帧：剩余帧数持平是合法的（S4 A5）
  let seq = [
    s(1, true, 3),
    s(2, true, 3),
    s(3, true, 2),
    s(4, true, 2),
    s(5, true, 1),
  ]
  assert_true(
    check_unwinding_granularity(seq) is Ok(_),
    msg="含 finally 持平步的序列必须通过",
  )
}

///|
test "merged_unwinding_fails" {
  // 一次弹 2 帧 = 合并单步（契约核心违规）
  let seq = [s(1, false, 0), s(2, true, 3), s(3, true, 1)]
  let err = check_unwinding_granularity(seq)
  assert_true(err is Err(_), msg="合并单步必须被判据拒绝")
  match err {
    Err(msg) =>
      assert_true(
        msg.contains("不得合并单步"),
        msg="错误信息应指明契约，实际: \{msg}",
      )
    Ok(_) => fail("上已断言 Err，不可达")
  }
}

///|
test "unwinding_direction_and_bounds_fail" {
  // 回增
  assert_true(
    check_unwinding_granularity([s(1, true, 2), s(2, true, 3)]) is Err(_),
  )
  // 进入展开时剩余 0 帧
  assert_true(
    check_unwinding_granularity([s(1, false, 0), s(2, true, 0)]) is Err(_),
  )
  // 离开展开但未归零
  assert_true(
    check_unwinding_granularity([s(1, true, 2), s(2, false, 1)]) is Err(_),
  )
  // 负值
  assert_true(check_unwinding_granularity([s(1, true, -1)]) is Err(_))
  // 步号不递增
  assert_true(
    check_unwinding_granularity([s(2, true, 2), s(2, true, 1)]) is Err(_),
  )
}

///|
test "empty_and_single_samples_pass" {
  assert_true(check_unwinding_granularity([]) is Ok(_))
  assert_true(check_unwinding_granularity([s(7, true, 1)]) is Ok(_))
}

///|
test "schema_constants_frozen" {
  // v0.1 冻结锚：版本串与冻结日期逐字对齐 Rust contracts.rs
  assert_eq(SCHEMA_VERSION, "v0.1")
  assert_eq(SCHEMA_V0_1_FROZEN_AT, "2026-09-12")
}

///|
test "payload_field_whitelist_matches_replay_single_source" {
  // 对账锚：scripts/replay/v01_payload_fields.json 的 v01_payload_fields
  // 逐条（14 条，顺序一致）——两侧漂移即红
  let expected : Array[String] = [
    "step_index", "code_line", "func_name", "semantic_label", "algorithm_step", "local_vars",
    "call_stack", "vis_events", "heatmap_line", "heatmap_count", "accessed_vars",
    "array_snapshots", "pointer_snapshots", "root_cause_hint",
  ]
  let got = step_payload_fields_v0_1()
  assert_eq(got.length(), 14, msg="v0.1 字段白名单必须恰 14 条")
  for i, want in expected {
    assert_eq(
      got[i],
      want,
      msg="第 \{i} 条字段名与 v01_payload_fields.json 漂移",
    )
  }
}

///|
test "reserved_fields_match_replay_single_source" {
  // 对账锚：v01_payload_fields.json 的 reserved_fields 逐条（4 条）
  let expected : Array[String] = [
    "handler_depth", "unwinding", "unwind_frames_left", "current_exception",
  ]
  let got = reserved_fields_v0_2()
  assert_eq(got.length(), 4, msg="预留位必须恰 4 条")
  for i, want in expected {
    assert_eq(got[i], want, msg="预留位第 \{i} 条漂移")
  }
}

///|
test "contract_table_counts_and_ids" {
  // 台账/清单/契约表计数与 id 锚（照搬 contracts.rs 常量表）
  assert_eq(v0_2_field_ledger().length(), 7, msg="台账必须恰 7 条")
  assert_eq(
    v0_2_activation_checklist().length(),
    5,
    msg="激活清单必须恰 5 条",
  )
  let contracts = behavior_contracts()
  assert_eq(contracts.length(), 5, msg="行为契约必须恰 5 条")
  assert_eq(contracts[0].id, "step_granularity")
  assert_eq(contracts[1].id, "payload_additive_only")
  assert_eq(contracts[2].id, "jit_breakpoint_integrity")
  assert_eq(contracts[3].id, "unwinding_step_granularity")
  assert_eq(contracts[4].id, "try_excludes_jit")
}

///|
test "contracts_json_shape" {
  // 显式 emitter 形状锚：紧凑（无空格分隔）+ 六键齐 + 值锚
  let json = contracts_json()
  assert_false(json.contains(": "), msg="紧凑形态不得含键值空格")
  assert_true(json.contains("\"schema\":\"v0.1\""))
  assert_true(json.contains("\"frozen_at\":\"2026-09-12\""))
  assert_true(
    json.contains("\"reserved_fields_v0_2\":[\"handler_depth\""),
    msg="预留位数组首元素形状",
  )
  assert_true(json.contains("\"v0_2_activation_checklist\":["))
  assert_true(json.contains("\"v0_2_field_ledger\":["))
  assert_true(json.contains("\"behavior_contracts\":["))
  assert_true(
    json.contains(
      "{\"id\":\"step_granularity\",\"statement\":\"一步 = 一条字节码指令",
    ),
    msg="契约条目字段序 = id 在首",
  )
}
