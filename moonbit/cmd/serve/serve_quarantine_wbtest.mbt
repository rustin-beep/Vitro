// quarantine_budget 通道锚（2026-09-28 一段欠账销项）：config.set 直写
// MemoryMap 定义点（clamp 0..1MB，Rust serve_apply_config 同形）+ 回显
// 六字段补齐（quarantine_budget / input_mode_batch——Rust config() 同构）
// + reset 保留语义（vm reset 跨重建保留 = 会话级配置）。
// 销项联动：serve_smoke 豁免表删两条（「config.set 生效」/「reset 保留
// 会话级配置（隔离预算）」）——MoonBit 臂 43→45 断言。

///|
test "serve_config_set_quarantine_budget_effective" {
  let s = @session.Session::new()
  // 默认 256KB（MemoryMap::new 的 DEFAULT_QUARANTINE_BUDGET——与 Rust 一致）
  let (r0, _) = serve_handle(s, "{\"id\":1,\"method\":\"config.get\"}")
  assert_true(
    r0.contains("\"quarantine_budget\":262144"),
    msg="默认回显 256KB",
  )
  // set 生效（直写 mem_map + 回显）
  let (r1, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"quarantine_budget\":1024}}",
  )
  assert_true(r1.contains("\"quarantine_budget\":1024"), msg="set 回显")
  assert_eq(s.vm.mem_map.quarantine_budget(), 1024, msg="定义点生效")
}

///|
test "serve_config_set_quarantine_budget_clamped" {
  // clamp 0..1MB（Rust v.clamp(0, 1024*1024) 同形）
  let s = @session.Session::new()
  let (r1, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"quarantine_budget\":-5}}",
  )
  assert_true(r1.contains("\"quarantine_budget\":0"), msg="负值 clamp 到 0")
  let (r2, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"quarantine_budget\":99999999}}",
  )
  assert_true(
    r2.contains("\"quarantine_budget\":1048576"),
    msg="超 1MB clamp 到顶",
  )
}

///|
test "serve_config_reset_preserves_quarantine_budget" {
  // reset 保留会话级配置（隔离预算）：R3 单源语义——vm reset 跨重建保留
  // （memory state.mbt「隔离预算是会话配置」纪律），serve 层无回放代码
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"quarantine_budget\":4096}}",
  )
  let (r2, _) = serve_handle(s, "{\"id\":2,\"method\":\"session.reset\"}")
  assert_true(
    r2.contains("\"quarantine_budget\":4096"),
    msg="reset 保留隔离预算",
  )
  // run（内部 setup_from_output → reset 重建 mem_map）后仍保留
  let _ = serve_handle(
    s, "{\"id\":3,\"method\":\"compile\",\"params\":{\"source\":\"int main(){ return 0; }\\n\"}}",
  )
  let _ = serve_handle(s, "{\"id\":4,\"method\":\"run\"}")
  assert_eq(
    s.vm.mem_map.quarantine_budget(),
    4096,
    msg="跨 run 保留（重建后回设）",
  )
}

///|
test "serve_config_echoes_input_mode_batch" {
  // input_mode_batch 回显（Rust config() 六字段同构——本批补齐）；
  // batch_input 参数切换即反映（run 帧须已编译——not_compiled 早退在参数域之前）
  let s = @session.Session::new()
  let (r0, _) = serve_handle(s, "{\"id\":1,\"method\":\"config.get\"}")
  assert_true(
    r0.contains("\"input_mode_batch\":false"),
    msg="默认 Interactive",
  )
  let _ = serve_handle(
    s, "{\"id\":2,\"method\":\"compile\",\"params\":{\"source\":\"int main(){ return 0; }\\n\"}}",
  )
  let _ = serve_handle(
    s, "{\"id\":3,\"method\":\"run\",\"params\":{\"batch_input\":true,\"max_steps\":10}}",
  )
  let (r2, _) = serve_handle(s, "{\"id\":4,\"method\":\"config.get\"}")
  assert_true(
    r2.contains("\"input_mode_batch\":true"),
    msg="run 帧切换后回显",
  )
}
