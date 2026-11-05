// #451（SWEEP1 批，2026-11-05）：input.feed 的 stdin 跨会话残留锚——
// 独立文件（serve_io 域：input.feed 语义之家）。落位注记：锚初版置于
// serve_run_wbtest.mbt 时修前首断言即红（调试期多因：请求串曾多一层花括号
// 致 json_parse 拒帧、feed text 转义层错——heredoc 吃反斜杠三连踩，批报告
// §五在案）；修复后同代码两文件均绿（审阅复现 180/180——PR #488 审阅 P3-3：
// 「同文件稳定失败」系修前版本现场，根因未追，勿再引用为环境差异证据）。

///|
/// #451 红→绿锚（SWEEP1 批，2026-11-05）：input.feed 的 stdin 跨
/// session.create 残留——修前 vm.input 跨会话存活（vm.reset 纪律性不碰
/// 宿主注入物；protocol.mbt 注释既称 Rust create = Session::default()
/// 「runtime 域全清」且「argv/输入模式在 create/destroy 时回默认」，输入
/// 行同属 runtime 域——迁移遗漏面），叠加 step.begin 的 InputState::
/// new(lines) 游标回卷（合理设计：重跑从头消费）使旧文本整段复活：
/// 同会话 feed 过一次后再次 create→compile→run 同款 scanf 程序**不再
/// waiting_input**、直接从头消费旧文本（教学面真缺陷——学生重采课静默
/// 读旧值，两臂同命中，issue #451 实测）。
test "sweep1_451_session_create_清stdin残留" {
  let s = @session.Session::new()
  let src = "#include <stdio.h>\nint main(void){int x; if(scanf(\"%d\",&x)!=1){printf(\"read fail\\n\");return 1;} printf(\"got %d\\n\",x); return 0;}\n"
  let compile_req = fn(i : Int32) -> String {
    "{\"id\":\{i},\"method\":\"compile\",\"params\":{\"source\":\"\{@util.json_escape(src)}\"}}"
  }
  let (_, _) = serve_handle(s, compile_req(1))
  let (r1, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  assert_true(
    r1.contains("\"waiting_input\":true"),
    msg="首轮 scanf 须等待",
  )
  let (r2, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"input.feed\",\"params\":{\"text\":\"42\\n\"}}",
  )
  assert_true(
    r2.contains("\"status\":\"finished\""),
    msg="feed 后续跑完成",
  )
  let (_, _) = serve_handle(s, "{\"id\":4,\"method\":\"step.begin\"}")
  let (_, _) = serve_handle(
    s, "{\"id\":5,\"method\":\"session.create\",\"params\":{}}",
  )
  let (_, _) = serve_handle(s, compile_req(6))
  let (r3, _) = serve_handle(s, "{\"id\":7,\"method\":\"run\"}")
  assert_true(
    r3.contains("\"waiting_input\":true"),
    msg="新会话零输入——scanf 须再次 waiting（修前残留旧文本静默重读）",
  )
  assert_false(
    r3.contains("\"status\":\"finished\""),
    msg="修前红位：残留文本使程序静默跑完",
  )
}

///|
/// #451 分界锚（SWEEP1 批，2026-11-05）：session.reset **保留** stdin 残余
/// （create/destroy 才回默认——protocol.mbt 的 create/reset 语义分界注释
/// 在案）——feed 后 reset → compile → run 仍 waiting（耗尽），step.begin
/// 回卷重读旧输入（got 42）合法。防 create 修复过度扩面到 reset。
test "sweep1_451_session_reset_保留stdin残余" {
  let s = @session.Session::new()
  let src = "#include <stdio.h>\nint main(void){int x; if(scanf(\"%d\",&x)!=1){printf(\"read fail\\n\");return 1;} printf(\"got %d\\n\",x); return 0;}\n"
  let compile_req = fn(i : Int32) -> String {
    "{\"id\":\{i},\"method\":\"compile\",\"params\":{\"source\":\"\{@util.json_escape(src)}\"}}"
  }
  let (_, _) = serve_handle(s, compile_req(1))
  let (_, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  let (_, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"input.feed\",\"params\":{\"text\":\"42\\n\"}}",
  )
  // reset（保留语义）→ 重新 compile → run：残余游标已耗尽 → 仍 waiting
  let (_, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"session.reset\",\"params\":{}}",
  )
  let (_, _) = serve_handle(s, compile_req(5))
  let (r1, _) = serve_handle(s, "{\"id\":6,\"method\":\"run\"}")
  assert_true(
    r1.contains("\"waiting_input\":true"),
    msg="reset 保留残余（耗尽态）——scanf 等待新输入",
  )
  // step.begin 回卷：旧输入可重读（同会话重跑从头消费——合法设计）
  let (_, _) = serve_handle(s, "{\"id\":7,\"method\":\"step.begin\"}")
  let mut finished = false
  let mut guard_cap = 0
  while !finished && guard_cap < 500 {
    let (sn, _) = serve_handle(s, "{\"id\":8,\"method\":\"step.next\"}")
    finished = sn.contains("\"finished\":true") ||
      sn.contains("\"trapped\":true")
    guard_cap = guard_cap + 1
  }
  assert_true(finished, msg="步进到达终态")
  assert_true(
    stdout_text(s).contains("got 42"),
    msg="reset 后 step.begin 回卷重读旧输入（保留语义——got 42）",
  )
}
