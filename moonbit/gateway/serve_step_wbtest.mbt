// serve step 族白盒锚（S8 批一号接线批，2026-10-01）：五方法协议面 +
// U1#1 一帧发布缓冲（R2 首调空帧语义）+ seek 往返 + trap 帧。编排本体
// 的行为锚在 time_travel/engine_wbtest（九锚）；本族锁 serve 层帧结构、
// 错误分支与 emitter 字段序（serde 序关键邻接形态）。

///|
test "serve_step_begin_not_compiled_state_error" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"step.begin\"}")
  assert_true(resp.contains("\"kind\":\"state\""))
  assert_true(resp.contains("需先编译成功"))
}

///|
test "serve_step_next_without_begin_state_error" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"step.next\"}")
  assert_true(resp.contains("\"kind\":\"state\""))
  assert_true(resp.contains("统一模式会话未初始化"))
}

///|
test "serve_step_flow_begin_next_first_call_empty" {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 1; a = a + 1; return a; }\\n\"}}",
  )
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  let (bresp, _) = serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}")
  assert_true(bresp.contains("\"ready\":true"))
  assert_true(bresp.contains("\"max_collected_step\":-1"))
  // R2 滞后一帧语义：首调只建缓冲、返回空 payloads（修复前形态 = 首调
  // 发布克隆 → 同步重复投递 0,0,1 序列，spec 附录 A 违例）
  let (r1, _) = serve_handle(s, "{\"id\":3,\"method\":\"step.next\"}")
  assert_true(r1.contains("\"payloads\":[]"), msg="首调必空帧")
  // 第二调起发布上一帧：step_index 0 起
  let (r2, _) = serve_handle(s, "{\"id\":4,\"method\":\"step.next\"}")
  assert_true(r2.contains("\"step_index\":0"))
  // emitter 字段序（serde 邻接形态锚）
  assert_true(r2.contains("\"step_index\":0,\"code_line\":"))
  // 帧 0 = 全局初始化帧（未进 main——call_stack 空、func_name 空串是
  // 正确语义，Rust 同形）；main 内帧的 func_name 由 finished 冲刷锚覆盖
  assert_true(r2.contains("\"func_name\":\"\""))
  // 引擎已挂会话
  assert_true(s.unified is Some(_), msg="engine 须挂 Session")
}

///|
test "serve_step_run_to_finished_flush" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 1; return a; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 跑到终结：finished 冲刷缓冲（末帧发布 + finished:true）
  let mut finished = false
  let mut last = ""
  for i = 0; i < 40 && !finished; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    if r.contains("\"finished\":true") {
      finished = true
      last = r
    }
  }
  assert_true(finished, msg="40 步内须到 finished")
  // 冲刷帧带 step_index（非空 payloads）
  assert_true(last.contains("\"step_index\""))
  // 终结后再 step.next：粘性空帧（坑 ⑥-6——不重放末帧）
  let (again, _) = serve_handle(s, "{\"id\":11,\"method\":\"step.next\"}")
  assert_true(again.contains("\"payloads\":[]"))
  assert_true(again.contains("\"finished\":true"))
}

///|
test "serve_step_seek_roundtrip_and_payload_get" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 0; while (a < 3) { a = a + 1; } return a; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 推进若干步（>一帧）
  for i = 0; i < 12; i = i + 1 {
    ignore(serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}"))
  }
  // payload.get：区间帧 + 窗口元数据
  let (pg, _) = serve_handle(
    s, "{\"id\":20,\"method\":\"payload.get\",\"params\":{\"start\":0,\"end\":3}}",
  )
  assert_true(pg.contains("\"cache_start_step\":0"))
  assert_true(pg.contains("\"max_collected_step\""))
  assert_true(pg.contains("\"step_index\":0"))
  // seek 回 0（窗口内直返路径——帧可再取）
  let (sk, _) = serve_handle(
    s, "{\"id\":21,\"method\":\"seek\",\"params\":{\"step\":0}}",
  )
  assert_true(sk.contains("\"success\":true"))
  assert_true(sk.contains("\"step_index\":0"))
  // seek 后 step.next 续跑（is_finished 复位 + 帧连续）
  let (nx, _) = serve_handle(s, "{\"id\":22,\"method\":\"step.next\"}")
  assert_false(nx.contains("\"error\""))
}

///|
test "serve_step_seek_missing_step_param" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"seek\"}")
  assert_true(resp.contains("\"kind\":\"protocol\""))
  assert_true(resp.contains("seek 需要 params.step"))
}

///|
test "serve_step_breakpoints_set_and_clear" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int i = 0; while (i < 5) { i = i + 1; } return i; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let (b1, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"breakpoints.set\",\"params\":{\"lines\":[4,-2,7]}}",
  )
  // 非正行号过滤（Rust 同款）；回显含设置值
  assert_true(
    b1.contains("\"lines\":[4,-2,7]"),
    msg="回显含原始 lines 数组",
  )
  // 清空 = 两层恢复 + 空回显
  let (b2, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"breakpoints.set\",\"params\":{\"lines\":[]}}",
  )
  assert_true(b2.contains("\"lines\":[]"))
}

///|
test "serve_step_trap_frame_trapped_flag" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int z = 0; return 10 / z; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let mut trapped = false
  let mut trap_resp = ""
  for i = 0; i < 40 && !trapped; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    if r.contains("\"trapped\":true") {
      trapped = true
      trap_resp = r
    }
  }
  assert_true(trapped, msg="除零程序须出 trap 帧")
  // trap_message 非空串（回滚前抓取——⑤-5.1 分叉②）
  assert_false(trap_resp.contains("\"trap_message\":null"))
  assert_true(trap_resp.contains("\"trap_message\":\""))
}

///|
test "serve_step_reset_invalidates_engine" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { return 0; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  assert_true(s.unified is Some(_))
  ignore(serve_handle(s, "{\"id\":3,\"method\":\"session.reset\"}"))
  // reset 作废引擎（分叉登记：保守作废语义——旧引擎与 reset 后 vm 失配）
  assert_true(s.unified is None)
  let (resp, _) = serve_handle(s, "{\"id\":4,\"method\":\"step.next\"}")
  assert_true(resp.contains("统一模式会话未初始化"))
}
