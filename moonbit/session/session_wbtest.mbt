// 会话骨架白盒锚（S7 批二号）：session_config_test.rs 四锚的纯配置
// 三锚（存活/回显/编译前不丢）+ 多文件 source_line_at 锚。
// 「2000 步真停」端到端锚（test_max_steps_survives_run_and_actually_
// applies 的执行半）依赖 compile→run 接线——批三号 gateway/cmd/serve
// 落地后补（登记）。

///|
test "session_config_defaults_align_vm" {
  let cfg = SessionConfig::default()
  let vm = @vm.VitroVM::new()
  assert_eq(cfg.max_steps, vm.max_steps, msg="默认步数与 VM 对齐")
  assert_eq(cfg.call_depth_limit, vm.call_depth_limit)
  assert_true(cfg.deterministic)
}

///|
test "session_set_max_steps_single_write_path" {
  // 单一写入口：set 后 config 与 vm 双达（Rust 事故三段式的对偶锚——
  // 配置写入必须立即落到 VM，无论是否已编译）
  let s = Session::new()
  s.set_max_steps(2000)
  assert_eq(s.config.max_steps, 2000, msg="config 侧可达")
  assert_eq(
    s.vm.max_steps,
    2000,
    msg="VM 侧立即生效（编译前设置不丢）",
  )
  // 下限 1（Rust max.max(1) 同）
  s.set_max_steps(0)
  assert_eq(s.vm.max_steps, 1)
  s.set_max_steps(-5)
  assert_eq(s.config.max_steps, 1)
}

///|
test "session_call_depth_limit_survives_reset" {
  // 跨 run 存活：vm.reset 保留会话级配置（vm/state.mbt 纪律——装载通道
  // 不得设置；reset 保留段），config 是真相源不受影响
  let s = Session::new()
  s.set_call_depth_limit(48)
  s.vm.reset()
  assert_eq(
    s.vm.call_depth_limit,
    48,
    msg="会话级配置必须跨 reset 存活（Rust setup_vm 覆盖事故的对偶）",
  )
  assert_eq(s.config.call_depth_limit, 48)
  s.vm.reset()
  assert_eq(s.vm.call_depth_limit, 48, msg="二次 reset 仍存活")
}

///|
test "session_config_echo_roundtrip" {
  // 回显：config 是 serve config.get 的对象——写入后读回一致
  let s = Session::new()
  s.set_max_steps(1234)
  s.set_call_depth_limit(64)
  assert_eq(s.config.max_steps, 1234)
  assert_eq(s.config.call_depth_limit, 64)
}

///|
test "session_config_apply_and_from_vm" {
  // apply/from 投影往返
  let vm = @vm.VitroVM::new()
  let cfg : SessionConfig = {
    max_steps: 777,
    call_depth_limit: 33,
    deterministic: false,
  }
  cfg.apply_to_vm(vm)
  assert_eq(vm.max_steps, 777)
  assert_false(vm.deterministic)
  let back = SessionConfig::from_vm(vm)
  assert_eq(back.max_steps, 777)
  assert_eq(back.call_depth_limit, 33)
  assert_false(back.deterministic)
}

///|
test "session_source_line_at_single_file" {
  let s = Session::new()
  s.compile.compile_units = [
    { filename: "main.c", source: "int a = 1;\nint b = 2;\nint c = 3;\n", },
  ]
  assert_eq(s.source_line_at(1), Some("int a = 1;"))
  assert_eq(s.source_line_at(2), Some("int b = 2;"))
  assert_eq(s.source_line_at(3), Some("int c = 3;"))
  assert_true(s.source_line_at(4) is None, msg="越界行 None")
  assert_true(s.source_line_at(0) is None, msg="非正数 None")
}

///|
test "session_source_line_at_multi_file_ranges" {
  // P0-4：多文件会话按 file_ranges 换算（Rust 事故复盘——直接查首单元
  // 在多文件下必然错配：main.c 13 行却报 line 20..25）
  let s = Session::new()
  s.compile.compile_units = [
    {
      filename: "main.c",
      source: "line1 of main\nline2 of main\nline3 of main\n",
    },
    { filename: "util.c", source: "u1\nu2\nu3\nu4\n", },
  ]
  // 合并形态：main.c 占全局 1..3，util.c 占 4..7（start_line 基于首行）
  s.compile.file_ranges = [
    { filename: "main.c", start_line: 1, end_line: 3, },
    { filename: "util.c", start_line: 4, end_line: 7, },
  ]
  assert_eq(s.source_line_at(1), Some("line1 of main"))
  assert_eq(s.source_line_at(3), Some("line3 of main"))
  // 跨界进第二文件：全局 4 → util.c 的第 1 行（in_file = 4 - 4 = 0）
  assert_eq(s.source_line_at(4), Some("u1"))
  assert_eq(s.source_line_at(7), Some("u4"))
  assert_true(s.source_line_at(8) is None, msg="超出全部区间 None")
}

///|
test "session_unified_frame_buffer_fields_default" {
  // 统一模式帧缓冲族字段照搬（serve 批消费的初始态）
  let s = Session::new()
  assert_true(s.unified_pending is None)
  assert_eq(s.unified_last_line, 0)
  assert_eq(s.unified_last_frame_vars.length(), 0)
  assert_eq(s.unified_row_entry_vars.length(), 0)
}

///|
test "session_nth_line_empty_source_rust_alignment" {
  // 审阅⑦字节级取证：Rust "".lines().nth(0) = None（空串 = 零行）；
  // 修复前 MoonBit split 形态 Some("")。空源码 + 查行必须 None。
  assert_true(
    s_source_line_at_empty(),
    msg="空源码查第 1 行必须 None（Rust lines() 语义：空串零行）",
  )
}

///|
fn s_source_line_at_empty() -> Bool {
  let s = Session::new()
  s.compile.compile_units = [{ filename: "empty.c", source: "", }]
  s.source_line_at(1) is None
}
