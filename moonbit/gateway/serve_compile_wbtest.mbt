// serve compile 白盒锚（S7 批三号二段）：merge_units 行数语义（file_ranges
// 生产者——P0-4 多文件行号定位的写入侧闭环）+ 诊断面（filename 解析/
// E 码形态）+ preprocessor_trace 通道。serve_smoke 全量对拍随批四号。

///|
test "serve_compile_single_source_ok" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { return 0; }\\n\"}}",
  )
  assert_true(resp.contains("\"ok\":true"), msg="编译成功")
  assert_true(resp.contains("\"diagnostics\":[]"), msg="零诊断")
  assert_true(s.compile.compiled, msg="compiled 置位")
  assert_true(s.compile.output is Some(_), msg="产物入会话")
}

///|
test "serve_compile_missing_params_error" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{}}",
  )
  // #68 红→绿锚（2026-10-11）：参数错误帧 message 内嵌期望形状 +
  // error.expected 机器可读字段（词汇表冻结：`?` 可省略 / `T[]` 数组 /
  // `{f,f}` 对象 / `A | B` 任一——下游可编程重试面）
  assert_true(
    resp.contains(
      "compile 需要 params.files:[{filename?,source}] 或 params.source:string",
    ),
    msg="message 含形状",
  )
  assert_true(
    resp.contains(
      "\"expected\":\"files:[{filename?,source}] | source:string[,filename:string]\"",
    ),
    msg="expected 字段存在且为形状表达式",
  )
  assert_true(resp.contains("\"ok\":false"))
}

///|
test "serve_compile_multifile_file_ranges_produced" {
  // **file_ranges 生产者锚**（会话批登记的义务）：a.c 三行无尾换行
  //（合并补 \n）+ b.c 两行有尾换行 → 区间 [{a.c,1,3},{b.c,4,5}]；
  // source_line_at 全局行号跨文件定位正确（P0-4 消费面闭环）
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"files\":[{\"filename\":\"a.c\",\"source\":\"int g;\\nint h;\\nint i;\"},{\"filename\":\"b.c\",\"source\":\"int main() { return 0; }\\n\"}]}}",
  )
  assert_true(resp.contains("\"ok\":true"))
  let ranges = s.compile.file_ranges
  assert_eq(ranges.length(), 2)
  assert_eq(ranges[0].filename, "a.c")
  assert_eq(ranges[0].start_line, 1)
  assert_eq(ranges[0].end_line, 3)
  assert_eq(ranges[1].filename, "b.c")
  assert_eq(ranges[1].start_line, 4)
  assert_eq(
    ranges[1].end_line,
    4,
    msg="b.c 单行（尾换行不产额外行）",
  )
  // 消费面：全局行号 4 = b.c 首行（跨文件边界 + 无尾换行补 \n 的合并形态）
  assert_eq(s.source_line_at(1), Some("int g;"))
  assert_eq(s.source_line_at(4), Some("int main() { return 0; }"))
}

///|
test "serve_compile_merge_empty_unit_no_range" {
  // 病 42 锚翻转（#71 第三梯队，2026-10-11）：旧锚把「空文件 0 行不产
  // 区间」错形态钉成预期（A3——补 \n 实占 1 行而行数计 0，后续文件
  // start_line 偏小/行号落洞错报 main.c）。正确形态：空文件产 1 行区间
  //（补行计入），三单元区间 3 条且后续文件行号 +1 连续。
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"files\":[{\"filename\":\"a.c\",\"source\":\"int g;\\n\"},{\"filename\":\"empty.c\",\"source\":\"\"},{\"filename\":\"b.c\",\"source\":\"int main() { return 0; }\\n\"}]}}",
  )
  let ranges = s.compile.file_ranges
  assert_eq(ranges.length(), 3, msg="空文件也产 1 行区间")
  assert_eq(
    ranges[2].start_line,
    3,
    msg="空文件占 1 行——b.c 从第 3 行起",
  )
  assert_eq(ranges[2].filename, "b.c")
  assert_eq(ranges[1].filename, "empty.c")
}

///|
test "serve_compile_syntax_error_diagnostics_shape" {
  // 诊断面：E 码前缀 + severity 名 + end_column 起点退化 + 1（Rust
  // session_api::compile 同形）；单文件 filename 缺省 main.c
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { return 0 \\n\"}}",
  )
  assert_true(resp.contains("\"ok\":false"))
  assert_true(resp.contains("\"severity\":\"error\""))
  assert_true(
    resp.contains("\"code\":\"E2"),
    msg="parse 错码域 E2xxx（探针实测 E2005）",
  )
  assert_true(resp.contains("\"filename\":\"main.c\""))
  assert_false(s.compile.compiled)
}

///|
test "serve_compile_multifile_diagnostic_filename_resolved" {
  // 多文件时诊断 filename 按全局行号反查文件（Rust resolve_filename +
  // push_one 同形）——错误落在第二个文件时 filename 必须 != main.c
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"files\":[{\"filename\":\"a.c\",\"source\":\"int g;\\nint h;\\n\"},{\"filename\":\"b.c\",\"source\":\"int main() { return 0 \\n\"}]}}",
  )
  assert_true(resp.contains("\"ok\":false"))
  assert_true(
    resp.contains("\"filename\":\"b.c\""),
    msg="诊断必须反查到第二文件（P0-4 诊断面——探针实测 E2005 缺分号行号落 b.c 区间）",
  )
  // EOF 级联第二诊断（E2006 预期 '}'）行号在合并串尾越界 → resolve
  // 未命中回 main.c（Rust push_one unwrap_or "main.c" 同形）——存在性
  // 不断言，仅注释登记

}

///|
test "serve_compile_preprocessor_trace_surface" {
  // E2 白箱教学层：带参宏展开链随 compile 出口（lexer TraceEntry::render
  // 通道——探针实证 SQ(2) 形态产 1 条）
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#define SQ(x) ((x)*(x))\\nint main() { return SQ(2); }\\n\"}}",
  )
  assert_true(resp.contains("\"ok\":true"))
  assert_eq(s.compile.preprocessor_trace.length(), 1)
  assert_true(
    s.compile.preprocessor_trace[0].contains("SQ(2)"),
    msg="宏展开链条目形态",
  )
  assert_true(resp.contains("preprocessor_trace"))
}

///|
test "serve_compile_replaces_previous_units" {
  // 覆盖式语义：二次 compile 替换编译单元集合（非追加）
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int g;\\nint main() { return 0; }\\n\"}}",
  )
  let (_, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"compile\",\"params\":{\"filename\":\"x.c\",\"source\":\"int main() { return 7; }\\n\"}}",
  )
  assert_eq(s.compile.compile_units.length(), 1, msg="覆盖非追加")
  assert_eq(s.compile.compile_units[0].filename, "x.c")
  assert_eq(s.compile.file_ranges.length(), 1)
}

///|
test "serve_compile_struct_fields_populated" {
  // struct_fields 派生：struct 逐字段偏移累加（Rust compute_type_size
  // 同形）+ union 全 0——变量快照的 ty 渲染消费面
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"struct P { int a; char b; };\\nunion U { int x; char y; };\\nint main() { return 0; }\\n\"}}",
  )
  assert_true(resp.contains("\"ok\":true"))
  let p = s.compile.struct_fields.get("P")
  guard! p is Some(fields)
  assert_eq(fields.length(), 2)
  assert_eq(fields[0], ("a", 0))
  assert_eq(fields[1], ("b", 4), msg="int 4 字节对齐后 char 落偏移 4")
  let u = s.compile.struct_fields.get("U")
  guard! u is Some(ufields)
  assert_eq(ufields.length(), 2)
  assert_eq(ufields[1], ("y", 0), msg="union 字段全 0 偏移")
}

///|
/// #70：codegen 错误文案行号提取
test "extract_gen_error_line_shapes" {
  assert_eq(extract_gen_error_line("第 3 行：未声明的标识符 'a'"), 3)
  assert_eq(
    extract_gen_error_line("全局作用域不支持变长数组(VLA) 'a'"),
    0,
  )
  assert_eq(extract_gen_error_line("第 12 行：x"), 12)
}

///|

///|
/// #92（2026-10-14 报/修）：codegen 错误（E0 无码——#38 立码段拍板前的
/// 过渡形态）与 typeck 警告共存时 W 在 E 前——下游按首条/严重级分流把
/// 阻断态显示成黄色提示（issue 实测 UI 形态）。修复：gen 失败路径对
/// diagnostics 全数组 stable partition（error 前、W/hint 后——含 lex 段
/// 警告，实测 W3053 来自 lexed.warnings），对齐 native cli 三轮渲染
/// （E→W）合成序。
test "issue92_gen_error_orders_before_warnings" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"char g[524288];\\nint main(void) { g[0] = 1; return 0; }\\n\"}}",
  )
  assert_true(r.contains("\"ok\":false"), msg="容量超限应阻断")
  let e_pos = r.find("\"severity\":\"error\"")
  let w_pos = r.find("\"severity\":\"warning\"")
  let ordered = match (e_pos, w_pos) {
    (Some(e), Some(w)) => e < w
    (Some(_), None) => true
    _ => false
  }
  assert_true(ordered, msg="error 级须先于 warning 级出现")
  assert_true(
    r.contains("全局数据区容量不足"),
    msg="容量文案在列",
  )
}

///|
/// #92 审阅 P1-① 扩面锚（2026-10-15）：E 前置 partition 原只挂 gen 失败
/// 分支——四条早退路径（词法/语法/AST 失败/类型）W 仍占首条。审阅突变
/// 实证：partition 反序 110/110 假绿（锚唯一样本只落 gen 分支）。本锚
/// 锁两条早退形态：宏遮蔽 W1018（词法警告 + 语法错误共存）与类型错误
/// 形态——error 级必须先于 warning 级。
test "issue92_early_exit_paths_ordered" {
  // 词法警告 + 语法错误（语法早退路径——审阅探针原样形态）
  let s1 = @session.Session::new()
  let (r1, _) = serve_handle(
    s1, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#define M 1\\n#define M 2\\nint main(void) { return 1 +; }\\n\"}}",
  )
  let e1 = r1.find("\"severity\":\"error\"")
  let w1 = r1.find("\"severity\":\"warning\"")
  let ok1 = match (e1, w1) {
    (Some(e), Some(w)) => e < w
    _ => false
  }
  assert_true(ok1, msg="语法早退：W1018 宏遮蔽不得占首条")
  assert_true(r1.contains("E2003"), msg="语法错误在列")
  // 类型错误早退路径
  let s2 = @session.Session::new()
  let (r2, _) = serve_handle(
    s2, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main(void) { undeclared_fn(); return 0; }\\n\"}}",
  )
  assert_true(r2.contains("\"ok\":false"), msg="类型错误阻断")
  let e2 = r2.find("\"severity\":\"error\"")
  let w2 = r2.find("\"severity\":\"warning\"")
  let ok2 = match (e2, w2) {
    (Some(e), Some(w)) => e < w
    (Some(_), None) => true
    _ => false
  }
  assert_true(ok2, msg="类型早退：error 前置")
}

///|
/// 病 78 锚（#71 P2，2026-10-16）：severity wire 值域四臂映射——突变
/// 实锤零检测（交换 0/1 臂后全闸绿——severity 直接误导判分线/教学 UI）。
/// 直锚 severity_name/severity_prefix 全臂 + 端到端 compile 帧 warning
/// 场景的 severity 字段值。
test "severity_wire_mapping_locked" {
  assert_eq(severity_name(0), "error")
  assert_eq(severity_name(1), "warning")
  assert_eq(severity_name(2), "hint")
  assert_eq(severity_name(3), "info")
  assert_eq(severity_prefix(0), "E")
  assert_eq(severity_prefix(1), "W")
  assert_eq(severity_prefix(2), "H")
  assert_eq(severity_prefix(3), "I")
  // 端到端：double→int 窄化警告（W3053）——severity 字段必为 "warning"
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main(){ int x = 3.14; return x; }\"}}",
  )
  assert_true(
    resp.contains("\"severity\":\"warning\""),
    msg="W3053 场景 severity 字段须为 warning（突变交换臂即红）",
  )
  // 端到端：编译错（E 码）——severity 字段必为 "error"
  let (resp2, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"compile\",\"params\":{\"source\":\"int main(){ return x; }\"}}",
  )
  assert_true(
    resp2.contains("\"severity\":\"error\""),
    msg="E 码场景 severity 字段须为 error",
  )
}
