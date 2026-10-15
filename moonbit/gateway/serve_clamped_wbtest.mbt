// #94（2026-10-15）：config.set 越界钳制显式化锚——静默钳制是「引擎替
// 下游做决定却不告知」的形态（issue 实测 4MiB 被压回 1MiB、判题缓冲在
// 1MiB 处受检 trap 而错误信息与内存无关）。修法：config.set 回包 result
// 追加 clamped 键名数组（恒带；空数组=无钳制）——协议「只增不改」纪律。
// 钳制面四处：quarantine_budget [0,1MB] / output_budget [4KB,16MB] /
// max_steps 下限 1 / call_depth_limit 下限 16。config.get 面零变更。

///|
test "serve_config_set_clamped_flag_quarantine" {
  // issue 原例：4 MiB 静默压回 1 MiB —— 修后回包带 clamped 标记
  let s = @session.Session::new()
  let (r1, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"quarantine_budget\":4194304}}",
  )
  assert_true(
    r1.contains("\"clamped\":[\"quarantine_budget\"]"),
    msg="4MiB 超顶钳制须回包标记",
  )
  assert_true(
    r1.contains("\"quarantine_budget\":1048576"),
    msg="钳后生效值 1MB",
  )
  // 合法值不标记
  let (r2, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"quarantine_budget\":4096}}",
  )
  assert_true(r2.contains("\"clamped\":[]"), msg="合法值 clamped 空数组")
}

///|
test "serve_config_set_clamped_flag_output_budget" {
  let s = @session.Session::new()
  // 下界钳制（<4KB）
  let (r1, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"output_budget\":100}}",
  )
  assert_true(
    r1.contains("\"clamped\":[\"output_budget\"]"),
    msg="output_budget 下界钳制标记",
  )
  assert_true(r1.contains("\"output_budget\":4096"), msg="钳后生效值 4KB")
  // 多键同帧钳制——数组按 serve_apply_config 判定序（max_steps 先于 output_budget）
  let (r2, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"output_budget\":99999999,\"max_steps\":-1}}",
  )
  assert_true(
    r2.contains("\"clamped\":[\"max_steps\",\"output_budget\"]"),
    msg="多键钳制全列（判定序）",
  )
}

///|
test "serve_config_set_clamped_flag_floors" {
  let s = @session.Session::new()
  // max_steps 下限 1（session.set_max_steps：<1 → 1）
  let (r1, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"max_steps\":0}}",
  )
  assert_true(
    r1.contains("\"clamped\":[\"max_steps\"]"),
    msg="max_steps 下界钳制标记",
  )
  assert_true(r1.contains("\"max_steps\":1"), msg="钳后 1")
  // call_depth_limit 下限 16
  let (r2, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"call_depth_limit\":0}}",
  )
  assert_true(
    r2.contains("\"clamped\":[\"call_depth_limit\"]"),
    msg="call_depth_limit 下界钳制标记",
  )
  assert_true(r2.contains("\"call_depth_limit\":16"), msg="钳后 16")
}

///|
test "serve_config_get_no_clamped_key" {
  // config.get 面零变更（七字段不动——clamped 仅 config.set 回包语义）
  let s = @session.Session::new()
  let (r, _) = serve_handle(s, "{\"id\":1,\"method\":\"config.get\"}")
  assert_false(r.contains("\"clamped\""), msg="get 回包不带 clamped")
}
