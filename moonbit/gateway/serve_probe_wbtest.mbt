// diagnostics_probe 帧锚（段三接线 2026-10-02）：八段结构 + 分叉②
// fix 接线验证 + 只读语义 + completion fail loud。wire 文本断言经
// json_parse 回读（confidence 的 f32 文本形态穿透验证随段四双臂对拍）。

///|
test "probe_frame_structure_and_fix_wiring" {
  let s = @session.Session::new()
  // 缺分号 → E2005（LineEnd 载荷：fix_kind 2 + 行末坐标——分叉②接线验证）
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"diagnostics_probe\",\"params\":{\"source\":\"int x = 1\"}}",
  )
  let j = json_parse(r) catch { _ => abort("帧非 JSON") }
  let result = json_field(j, "result")
  // 八段键全在
  for
    key in [
      "ok", "diagnostics", "misconceptions", "learning_paths", "knowledge_graph",
      "intents", "completion", "auto_fixes",
    ] {
    if json_field(result, key) is Null {
      fail("缺段 \{key}")
    }
  }
  inspect(json_field(result, "ok").as_bool(), content="Some(false)")
  // E2005 诊断行 + fix 七元组真值（LineEnd：start==end==行末 8 字节）
  match json_field(result, "diagnostics") {
    Array(diags) => {
      assert_eq(diags.length(), 1)
      let d0 = json_field(diags[0], "code").as_string()
      assert_eq(d0, Some("E2005"))
      assert_eq(json_field(diags[0], "fix_kind").as_int(), Some(2))
      assert_eq(json_field(diags[0], "severity").as_string(), Some("error"))
    }
    _ => fail("diagnostics 非数组")
  }
  // intents/completion 恒空（分叉①②）
  match json_field(result, "intents") {
    Array(a) => assert_eq(a.length(), 0)
    _ => fail("intents 非数组")
  }
  match json_field(result, "completion") {
    Array(a) => assert_eq(a.length(), 0)
    _ => fail("completion 非数组")
  }
  // 图表基线（25/25）
  assert_eq(
    json_field(json_field(result, "knowledge_graph"), "concepts_total").as_int(),
    Some(25),
  )
  // auto_fixes：E2005 的 InsertText 应用（"int x = 1" 行末补 ";"）
  match json_field(result, "auto_fixes") {
    Array(fixes) => {
      assert_eq(fixes.length(), 1)
      assert_eq(
        json_field(fixes[0], "fixed_source").as_string(),
        Some("int x = 1;"),
      )
    }
    _ => fail("auto_fixes 非数组")
  }
}

///|
test "probe_records_misconception_flow" {
  let s = @session.Session::new()
  // 三条 3051 记录 → M01 检出（3/4 = 0.75）+ 学习路径三步
  let req = "{\"id\":2,\"method\":\"diagnostics_probe\",\"params\":{\"source\":\"int main(){return 0;}\",\"records\":[{\"ts\":0,\"ok\":false,\"codes\":[3051]},{\"ts\":1,\"ok\":false,\"codes\":[3021]},{\"ts\":2,\"ok\":false,\"codes\":[3051]},{\"ts\":3,\"ok\":true,\"codes\":[]}]}}"
  let (r, _) = serve_handle(s, req)
  let j = json_parse(r) catch { _ => abort("帧非 JSON") }
  let result = json_field(j, "result")
  match json_field(result, "misconceptions") {
    Array(ms) => {
      assert_eq(ms.length(), 1)
      assert_eq(json_field(ms[0], "pattern_id").as_string(), Some("M01"))
      assert_eq(json_field(ms[0], "occurrence_count").as_int(), Some(3))
    }
    _ => fail("misconceptions 非数组")
  }
  match json_field(result, "learning_paths") {
    Array(ps) => {
      assert_eq(ps.length(), 1)
      match json_field(ps[0], "steps") {
        Array(steps) => assert_eq(steps.length(), 3)
        _ => fail("steps 非数组")
      }
    }
    _ => fail("learning_paths 非数组")
  }
  // 知识图谱段：源码合法（无 error 级诊断）→ from_errors 恒空——
  // records 驱动的误区检测独立于诊断激活（Rust 同形；激活路径的正例
  // 在 probe_frame_structure 锚经 error 源码覆盖表键存在性）
  match json_field(json_field(result, "knowledge_graph"), "from_errors") {
    Array(fe) => assert_eq(fe.length(), 0)
    _ => fail("from_errors 非数组")
  }
}

///|
test "probe_completion_param_fail_loud" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"diagnostics_probe\",\"params\":{\"source\":\"int x\",\"completion\":{\"line\":0,\"column\":0}}}",
  )
  // error 帧（M15 未实现——不支持而非静默假空）
  inspect(
    r.contains("\"error\"") && r.contains("completion 段随 analysis 批"),
    content="true",
  )
}

///|
test "probe_readonly_no_session_mutation" {
  let s = @session.Session::new()
  // 先 compile 建立会话诊断态，再跑 probe——会话诊断不被覆盖（只读语义）
  let _ = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"files\":[{\"filename\":\"main.c\",\"source\":\"int main(){return 0;}\"}]}}",
  )
  let before = s.compile.diagnostics.length()
  let _ = serve_handle(
    s, "{\"id\":2,\"method\":\"diagnostics_probe\",\"params\":{\"source\":\"int x = 1\"}}",
  )
  assert_eq(s.compile.diagnostics.length(), before)
}
