// schema 契约白盒锚（S7 批一号）：展开粒度判据 5 锚照搬 contracts.rs
// tests 模块 + v0.1 冻结对账锚（字段白名单/预留位/常量/计数）。
// 三层联动（2026-09-27 用户审阅 P2-2 修正——此前「对账 JSON」为虚假
// 声称，注入第 15 字段实测假绿）：
//   ① JSON 单源 →(gen_protocol_fields 生成期)→ schema_fields_gen.mbt
//   ② 生成物 →(本测试硬编码第三份锚)→ 语义防手改
//   ③ JSON →(Go/Python replay 运行期)→ Rust serve 输出
// 本测试硬编码份锁 ②；① 由生成器 -check（CI）锁；JSON 字段数变更被
// 生成器基线断言拦截（expectedV01=14 只增不改，v0.2 激活走 checklist）。

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
  // 显式 emitter 形状锚：紧凑（无空格分隔）+ 六键齐 + 键序 = serde 字典序
  // （BTreeMap：behavior_contracts 首键、条目内 batch 首键——见函数头注）
  let json = contracts_json()
  assert_false(json.contains(": "), msg="紧凑形态不得含键值空格")
  assert_true(json.contains("\"schema\":\"v0.1\""))
  assert_true(json.contains("\"frozen_at\":\"2026-09-12\""))
  assert_true(
    json.has_prefix("{\"behavior_contracts\":["),
    msg="顶层首键 = behavior_contracts（serde 字典序）",
  )
  assert_true(
    json.has_suffix("]}"),
    msg="顶层末键 = v0_2_field_ledger 段收尾",
  )
  assert_true(
    json.contains("\"reserved_fields_v0_2\":[\"handler_depth\""),
    msg="预留位数组首元素形状",
  )
  assert_true(
    json.contains(
      "{\"batch\":\"-\",\"enforced_by\":\"step_payload_schema_v0_1_test::test_step_payload_top_level_fields_frozen（step_index 连续递增）\",\"id\":\"step_granularity\"",
    ),
    msg="契约条目键序 = batch/enforced_by/id/...（serde 字典序）",
  )
  assert_true(
    json.contains(
      "{\"batch\":\"CS3b\",\"field\":\"handler_depth\",\"kind\":\"reserve\"",
    ),
    msg="台账条目键序 = batch/field/kind/note/status（serde 字典序）",
  )
}

///|
test "contracts_json_byte_exact_rust_truth" {
  // 与 Rust 真值逐字节对拍锚（用户审阅 P2-1 实测锁定，2026-09-27）：探针 tmp/review_20260927/json_order（serde_json ~1.0.149 与 native 同版，全量复刻 contracts.rs 数据与 json!+to_string 构造路径）的 stdout 真值。键序漂移（含未来 preserve_order 启用 / 常量改文）即红。
  let truth : Array[String] = [
    "{\"behavior_contracts\":[{\"batch\":\"-\",\"enforced_by\":\"step_payload_schema_v0_1_tes",
    "t::test_step_payload_top_level_fields_frozen（step_index 连续递增）\",\"id\":\"step_granularit",
    "y\",\"statement\":\"一步 = 一条字节码指令（含透明的 StepEvent 调试指令）；同一步不被合并\",\"status\":\"active\"},{",
    "\"batch\":\"-\",\"enforced_by\":\"step_payload_schema_v0_1_test（键集合冻结 + contracts::RESER",
    "VED_FIELDS_V0_2 缺省断言）\",\"id\":\"payload_additive_only\",\"statement\":\"StepPayload 字段只",
    "增不改语义；新增字段必须可空/有默认值；v0.1 阶段不得携带未发布字段\",\"status\":\"active\"},{\"batch\":\"-\",\"enforce",
    "d_by\":\"jit_unit_test / e2e 断点用例\",\"id\":\"jit_breakpoint_integrity\",\"statement\":\"",
    "含断点的循环排除出 JIT trace —— 断点语义不被 trace 优化吞掉\",\"status\":\"active\"},{\"batch\":\"CS3b\",\"",
    "enforced_by\":\"contracts::check_unwinding_granularity（单测合成序列）+ SharpTutor S4 §5 A2/A5 回",
    "放\",\"id\":\"unwinding_step_granularity\",\"statement\":\"UNWINDING 每弹一帧 / 执行一个 finally ",
    "块 = 一个 VM step，**不得合并单步**（展开动画的根基）\",\"status\":\"reserved\"},{\"batch\":\"CS3a\",\"enfo",
    "rced_by\":\"CS3a 批次 jit 用例（激活时落库）\",\"id\":\"try_excludes_jit\",\"statement\":\"含 TryBeg",
    "in 的函数排除出 JIT trace 编译（与断点排除同一模式）\",\"status\":\"reserved\"}],\"frozen_at\":\"2026-09-12",
    "\",\"reserved_fields_v0_2\":[\"handler_depth\",\"unwinding\",\"unwind_frames_left\",\"cu",
    "rrent_exception\"],\"schema\":\"v0.1\",\"v0_2_activation_checklist\":[\"① 只增事件：不得改动 v0.1",
    " 既有 14 字段的名称/类型/语义；预留位激活一律以新增字段形态落地（消费方须忽略未知字段）\",\"② 同步更新 docs/spec/STEP_PAYLOAD_SCHEMA",
    "_V0_1.md：§9 台账状态 active + §7 校验表追加 v0.2 历史行\",\"③ 重跑引擎侧 C1–C3：cargo test --test step_pay",
    "load_schema_v0_1_test / --test unified_engine_window_test + go run ./scripts/serve_smoke",
    "\",\"④ 重跑签字回放 S1–S5：go run ./scripts/replay/replay_s1_s5.go --anchor <新短哈希>（异常域还需 S4 §5 ",
    "激活契约 A1–A8）\",\"⑤ 解除冻结测试中的预留位断言（v0.1 断言 → v0.2 断言），并知会下游按容忍矩阵回归 T4 投影\"],\"v0_2_field_le",
    "dger\":[{\"batch\":\"CS3b\",\"field\":\"handler_depth\",\"kind\":\"reserve\",\"note\":\"",
    "当前受几层 try 保护；与 unwinding 正交（finally 步 handler_depth==0 但仍在展开）\",\"status\":\"pending\"},",
    "{\"batch\":\"CS3b\",\"field\":\"unwinding\",\"kind\":\"reserve\",\"note\":\"展开态显式标记；每帧一 ",
    "step，不得合并（见 BEHAVIOR_CONTRACTS）\",\"status\":\"pending\"},{\"batch\":\"CS3b\",\"field\":",
    "\"unwind_frames_left\",\"kind\":\"reserve\",\"note\":\"剩余待展开帧数，展开动画驱动字段\",\"status\":\"p",
    "ending\"},{\"batch\":\"CS3b\",\"field\":\"current_exception\",\"kind\":\"reserve\",\"not",
    "e\":\"{type_name, message, addr, origin_line}|null；origin_line 为原始抛点（`throw;` 保留 / `thro",
    "w e;` 改写）\",\"status\":\"pending\"},{\"batch\":\"v0.2\",\"field\":\"code_file\",\"kind\"",
    ":\"add\",\"note\":\"多文件行号归位（§8 #9）：code_line 保持全局行号语义，另附文件名，避免破坏断点/heatmap 口径\",\"status",
    "\":\"pending\"},{\"batch\":\"v0.2\",\"field\":\"call_stack[].return_line\",\"kind\":\"ad",
    "d\",\"note\":\"补全既有字段值（§8 #1）：字段已在 v0.1 中恒为 0，激活 = 记录 VM 帧返回行，属**补值不改字段**\",\"status\":",
    "\"pending\"},{\"batch\":\"v0.2\",\"field\":\"func_display_name / func_mangled_name\",\"k",
    "ind\":\"add\",\"note\":\"§8 #2：C++/C# 内部名（`__ctor__Vec`）与源码可读名双字段，保留 func_name 作 display",
    " 语义\",\"status\":\"pending\"}]}",
  ]
  let buf = StringBuilder()
  for p in truth {
    buf.write_string(p)
  }
  assert_eq(
    contracts_json(),
    buf.to_string(),
    msg="contracts_json 必须与 Rust 探针真值逐字符一致",
  )
}
