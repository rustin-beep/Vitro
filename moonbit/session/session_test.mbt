// 黑盒测试（S7 批二号）：对外面消费面点名——本包全部 pub 符号经
// @session. 形态消费（moonbit_surface 边表登记依据）。

///|
test "blackbox_config_surface" {
  let cfg : @session.SessionConfig = @session.SessionConfig::default()
  assert_true(cfg.max_steps > 0)
  assert_true(cfg.call_depth_limit > 0)
  assert_true(cfg.deterministic)
  let vm = @vm.VitroVM::new()
  ignore(@session.SessionConfig::from_vm(vm))
  cfg.max_steps = 100
  cfg.call_depth_limit = 32
  cfg.deterministic = false
  cfg.apply_to_vm(vm)
  assert_eq(vm.max_steps, 100)
}

///|
test "blackbox_session_surface" {
  let s = @session.Session::new()
  s.set_max_steps(2000)
  s.set_call_depth_limit(48)
  assert_eq(s.config.max_steps, 2000)
  s.compile.compile_units = [
    { filename: "main.c", source: "int main(){ return 0; }\n", },
  ]
  assert_eq(s.source_line_at(1), Some("int main(){ return 0; }"))
  assert_true(s.unified_pending is None)
}

///|
test "blackbox_dto_surface" {
  // DTO 全族点名构造
  let d : @session.Diagnostic = {
    line: 3,
    column: 5,
    error_code: 3032,
    severity: 1,
    message: "m",
    fix_suggestion: "f",
    fix_kind: 0,
    replace_start_line: 0,
    replace_start_column: 0,
    replace_end_line: 0,
    replace_end_column: 0,
    replacement_text: "",
    filename: "main.c",
  }
  let am : @session.AlgorithmMatch = {
    name: "bubble_sort",
    display_name: "冒泡排序",
    func_name: "main",
    confidence: 80,
    suggestion: "s",
    line: 1,
    vis_events: [],
  }
  let t : @session.TraceEntry = { line: 1, operation: "op", }
  let vs : @session.VariableSnapshot = {
    name: "i",
    addr: 0,
    is_local: true,
    ty: @ast.Type::Int(false, false),
    value: 1L,
  }
  let mr : @session.MemoryRegion = {
    addr: 4096,
    size: 64,
    name: "p",
    ty: "int*",
    is_heap: true,
    is_freed: false,
    alloc_line: 3,
    alloc_by: "malloc",
    kind: "heap",
  }
  let mf : @session.MemoryFragment = { addr: 4096, size: 64, }
  let hs : @session.HeapStats = {
    heap_base: 65536,
    total_heap: 100,
    allocated: 64,
    fragmented: 36,
    fragmentation_rate: 36,
  }
  let sr : @session.StepResult = {
    status: @session.StepStatus::Paused,
    current_line: 1,
    output: "",
    waiting_input: false,
  }
  let cu : @session.CompileUnit = { filename: "a.c", source: "", }
  let fr : @session.FileRange = { filename: "a.c", start_line: 1, end_line: 1, }
  assert_eq(d.error_code, 3032)
  assert_eq(am.confidence, 80)
  assert_eq(t.line, 1)
  assert_eq(vs.value, 1L)
  assert_true(mr.is_heap)
  assert_eq(mf.size, 64)
  assert_eq(hs.fragmentation_rate, 36)
  assert_true(sr.status is @session.StepStatus::Paused)
  assert_eq(sr.status.to_text(), "Paused")
  assert_eq(cu.filename, "a.c")
  assert_eq(fr.end_line, 1)
}
