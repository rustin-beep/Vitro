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
  assert_true(resp.contains("compile 需要 params.files:[{filename?,source}] 或 params.source:string"), msg="message 含形状")
  assert_true(
    resp.contains("\"expected\":\"files:[{filename?,source}] | source:string[,filename:string]\""),
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
  // 空文件 0 行不产区间（Rust merge_compile_units 同语义）——三单元
  // 中间空文件，区间仍 2 条且后续文件行号连续
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"files\":[{\"filename\":\"a.c\",\"source\":\"int g;\\n\"},{\"filename\":\"empty.c\",\"source\":\"\"},{\"filename\":\"b.c\",\"source\":\"int main() { return 0; }\\n\"}]}}",
  )
  let ranges = s.compile.file_ranges
  assert_eq(ranges.length(), 2, msg="空文件不产区间")
  assert_eq(
    ranges[1].start_line,
    2,
    msg="空文件占一行合并位（补 \\n）但行数 0",
  )
  assert_eq(ranges[1].filename, "b.c")
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
