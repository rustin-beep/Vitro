// S7 批三号二段：serve compile 方法——多文件合并编译管线 + 诊断出口。
// 照搬源：native/src/engine/compile_pipeline.rs 的 merge_compile_units/
// run_multi_file_pipeline 主体 + native/src/bin/vitro_cli.rs 的 compile
// 方法帧 + native/src/session_api.rs 的 compile 出口 emitter。
//
// **file_ranges 生产者义务**（总计划 S7 行登记）：session 批二号备了
// 换算逻辑（source_line_at）但无生产者——写入方在 Rust 侧
// compile_pipeline.rs:557；本文件落 MoonBit 侧合并通道，P0-4 多文件
// 行号定位自此两侧闭环。
//
// 登记分叉（本段不搬，诚实记录）：
// ① algorithm_matches——**已接线**（2026-10-01 批四号）：compile 成功
//    尾段调 @steps.detect_algorithms（teaching/steps 判据族，已迁移
//    sorting/search/string/tree/graph 五族 28/42 算法；未迁移族判据
//    不命中 = 零标注降级，协议合法形态）；
// ② fix_kind/replace_*/replacement_text 恒 0/空——error_catalog 的
//    generate_fix（机器修复文本生成）无 MoonBit 对等物，随 diag 教学
//    批；fix_suggestion 的 catalog explanation fallback 已照搬；
// ③ cpp 扩展名检测（.cpp/.cxx/.vitrocpp → cpp_mode）不搬——F-2 终局
//    已裁 C++（cpp_mode 恒 false，cpp 文件名按 C 子集处理）；
// ④ errors 串富化 = catalog emoji/title 前缀照搬，但 codegen 错误的
//    串形态是"生成错误: {}"逐条（Rust 同形）。
//
// 防线义务（本批 J9）：merge_units 行数语义（尾换行/空文件）+
// file_ranges 区间锚 + 2000 步真停锚（serve_run_wbtest）。

///|
/// 合并编译单元（**file_ranges 生产者**——Rust merge_compile_units 逐语义
/// 照搬，compile_pipeline.rs:557）：源串顺序拼接（无尾换行补 `\n`，空
/// 文件也补）+ 全局行号 → 文件区间表。行数语义：空文件 0 行不产区间；
/// 尾换行时行数 = 换行数（尾 `\n` 不产生额外空行）；无尾换行 = 换行数+1。
fn merge_units(
  units : Array[@session.CompileUnit],
) -> (String, Array[@session.FileRange]) {
  let full = StringBuilder()
  let ranges : Array[@session.FileRange] = []
  let mut current_line = 1
  let nl : String = "\n"
  for u in units {
    let start_line = current_line
    full.write_string(u.source)
    if !u.source.has_suffix(nl) {
      full.write_char('\n')
    }
    let line_count = if u.source.is_empty() {
      0
    } else {
      let mut newline_count = 0
      for i = 0; i < u.source.length(); i = i + 1 {
        if u.source[i].to_int() == 10 {
          newline_count = newline_count + 1
        }
      }
      if u.source.has_suffix(nl) {
        newline_count
      } else {
        newline_count + 1
      }
    }
    if line_count > 0 {
      ranges.push(@session.FileRange::{
        filename: u.filename,
        start_line,
        end_line: start_line + line_count - 1,
      })
    }
    current_line = start_line + line_count
  }
  (full.to_string(), ranges)
}

///|
/// 全局行号 → 文件名（Rust resolve_filename 照搬；未命中 None）。
fn resolve_filename(line : Int, ranges : Array[@session.FileRange]) -> String? {
  for r in ranges {
    if line >= r.start_line && line <= r.end_line {
      return Some(r.filename)
    }
  }
  None
}

///|
/// severity 协议名（Rust session_api::severity_name 同形照搬——Int 输入
/// 4 臂；diag 包 Severity::to_str 是 enum 输入的平行单源，形态不同不互替）。
fn severity_name(severity : Int) -> String {
  match severity {
    0 => "error"
    1 => "warning"
    2 => "hint"
    _ => "info"
  }
}

///|
/// severity 前缀（Rust session_api::severity_prefix 同形：E/W/H/I）。
fn severity_prefix(severity : Int) -> String {
  match severity {
    0 => "E"
    1 => "W"
    2 => "H"
    _ => "I"
  }
}

///|
/// 单条诊断推送（Rust push_one 主体照搬）：Diagnostic 全字段 + errors 串
/// 富化行（catalog 命中 = "{emoji} {title} — 错误 E{code} (第{line}行,
/// 第{column}列): {message}"，未命中 = 裸格式——Rust 富化同形）。
/// fix_suggestion：generate_fix 无对等物（分叉②），fallback 到 catalog
/// explanation（Rust push_one 的空 fix 分支同形）。
fn push_one_diag(
  s : @session.Session,
  code : Int,
  line : Int,
  column : Int,
  message : String,
  severity : Int,
  ranges : Array[@session.FileRange],
) -> Unit {
  let entry = match @diag.ErrorCode::from_code(code) {
    Some(e) => e.catalog()
    None => None
  }
  let fix_suggestion = match entry {
    Some(i) => i.explanation
    None => ""
  }
  let filename = match resolve_filename(line, ranges) {
    Some(f) => f
    None => "main.c"
  }
  s.compile.diagnostics.push(@session.Diagnostic::{
    line,
    column,
    error_code: code,
    severity,
    message,
    fix_suggestion,
    fix_kind: 0, // 分叉②：机器修复生成随 diag 教学批
    replace_start_line: 0,
    replace_start_column: 0,
    replace_end_line: 0,
    replace_end_column: 0,
    replacement_text: "",
    filename,
  })
  let rich = match entry {
    Some(i) =>
      "\{i.emoji} \{i.title} — 错误 E\{code} (第\{line}行, 第\{column}列): \{message}"
    None => "错误 E\{code} (第\{line}行, 第\{column}列): \{message}"
  }
  s.compile.errors = s.compile.errors + rich + "\n"
}

///|
/// 词法错误推送（severity 0）。
fn push_lex_errors(
  s : @session.Session,
  errors : Array[@token.LexError],
  ranges : Array[@session.FileRange],
) -> Unit {
  for e in errors {
    push_one_diag(
      s,
      e.code.code(),
      e.loc.line,
      e.loc.column,
      e.message,
      0,
      ranges,
    )
  }
}

///|
/// 词法警告推送（severity 1）。
fn push_lex_warnings(
  s : @session.Session,
  warnings : Array[@token.LexWarning],
  ranges : Array[@session.FileRange],
) -> Unit {
  for w in warnings {
    push_one_diag(
      s,
      w.code.code(),
      w.loc.line,
      w.loc.column,
      w.message,
      1,
      ranges,
    )
  }
}

///|
/// 解析/类型错误推送（ParseError/TypeError 同构 Int code——统一入口）。
fn push_code_errors(
  s : @session.Session,
  errors : Array[(Int, Int, Int, String)],
  severity : Int,
  ranges : Array[@session.FileRange],
) -> Unit {
  for pair in errors {
    let (code, line, column, message) = pair
    push_one_diag(s, code, line, column, message, severity, ranges)
  }
}

///|
/// 多文件编译管线主体（Rust run_multi_file_pipeline 照搬）。返回是否
/// 编译成功；诊断/错误串/产物状态沿途写入 session.compile。
fn serve_compile_pipeline(
  s : @session.Session,
  units : Array[@session.CompileUnit],
) -> Bool {
  // 清空编译状态（compile_units 由方法帧先行赋值，此处保留——Rust 同）
  let st = s.compile
  st.output = None
  st.diagnostics = []
  st.algorithm_matches = []
  st.struct_fields = Map([])
  st.errors = ""
  st.compiled = false
  st.file_ranges = []
  st.preprocessor_trace = []
  // ── 合并（file_ranges 生产者）──
  let (full_source, ranges) = merge_units(units)
  st.file_ranges = ranges
  // ── 1. Lexer（E2：预处理警告与追踪随词法产出）──
  // quote-include 的 provider 按宿主形态文件级分叉（2026-09-29 审阅
  // P2 修复）：native = 真实文件系统 + base_dir 候选链；wasm-gc =
  // 内存 vfs 空表（无 fs，E1021 是正当教学诊断）。此前统一 vfs 空表
  // 曾使 native 壳静默丢失 include 解析（oracle 同请求成功而本侧
  // E1021——审阅实锤）。
  let lexed = lex_full_source(full_source, units)
  for t in lexed.trace {
    st.preprocessor_trace.push(t.render())
  }
  if !lexed.warnings.is_empty() {
    push_lex_warnings(s, lexed.warnings, ranges)
  }
  if !lexed.errors.is_empty() {
    push_lex_errors(s, lexed.errors, ranges)
    st.errors = st.errors + "词法错误\n"
    return false
  }
  // ── 2. Parser ──
  let r = @parser.parse(lexed.tokens)
  if !r.errors.is_empty() {
    let rows : Array[(Int, Int, Int, String)] = []
    for e in r.errors {
      rows.push((e.code, e.line, e.column, e.message))
    }
    push_code_errors(s, rows, 0, ranges)
    st.errors = st.errors + "语法错误\n"
    return false
  }
  let program = match r.program {
    Some(p) => p
    None => {
      st.errors = "解析失败：无法生成 AST"
      return false
    }
  }
  // ── 3. TypeChecker（errors/warnings/hints 三段 severity 0/1/2）──
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, type_warnings, type_hints) = tc.check(program)
  if !type_errors.is_empty() {
    let rows : Array[(Int, Int, Int, String)] = []
    for e in type_errors {
      rows.push((e.code, e.line, e.column, e.message))
    }
    push_code_errors(s, rows, 0, ranges)
    st.errors = st.errors + "类型错误\n"
    return false
  }
  if !type_warnings.is_empty() {
    let rows : Array[(Int, Int, Int, String)] = []
    for e in type_warnings {
      rows.push((e.code, e.line, e.column, e.message))
    }
    push_code_errors(s, rows, 1, ranges)
  }
  if !type_hints.is_empty() {
    let rows : Array[(Int, Int, Int, String)] = []
    for e in type_hints {
      rows.push((e.code, e.line, e.column, e.message))
    }
    push_code_errors(s, rows, 2, ranges)
  }
  // ── 4. BytecodeGen ──
  let (output_opt, gen_errors) = @codegen.compile(typed)
  let output = match output_opt {
    Some(o) => o
    None => {
      for e in gen_errors {
        st.errors = st.errors + "生成错误: \{e}\n"
      }
      st.errors = st.errors + "字节码生成错误\n"
      return false
    }
  }
  // ── 填充编译结果 ──
  st.output = Some(output)
  // struct_fields：struct 逐字段偏移累加 + union 全 0（Rust 同形——
  // compute_type_size 以产物 struct/union 表自引用迭代）
  let empty_class_map : Map[String, Int] = Map([])
  for k, v in output.struct_defs {
    let fields : Array[(String, Int)] = []
    let mut offset = 0
    for f in v {
      fields.push((f.name, offset))
      offset = offset +
        @ast.compute_type_size(
          f.ty,
          output.struct_defs,
          output.union_defs,
          empty_class_map,
        )
    }
    st.struct_fields.set(k, fields)
  }
  for k, v in output.union_defs {
    let fields : Array[(String, Int)] = []
    for f in v {
      fields.push((f.name, 0))
    }
    st.struct_fields.set(k, fields)
  }
  // 算法检测（Rust compile_pipeline.rs:544 同位点——teaching/steps 判据族）
  st.algorithm_matches = @steps.detect_algorithms(program)
  st.compiled = true
  st.errors = ""
  true
}

///|
/// compile 方法帧（Rust vitro_cli.rs compile 臂照搬）：覆盖式语义——
/// params.files（数组）即当前完整编译单元集合（非追加）；或 params.source
/// 单文件（可选 filename）。返回 (响应 JSON, 无停机)。
fn serve_compile_frame(
  s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  let units : Array[@session.CompileUnit] = []
  match json_field(params, "files") {
    Array(files) =>
      for f in files {
        let filename = match json_field(f, "filename").as_string() {
          Some(n) => n
          None => "main.c"
        }
        let source = match json_field(f, "source").as_string() {
          Some(src) => src
          None => ""
        }
        units.push({ filename, source, })
      }
    _ =>
      match json_field(params, "source").as_string() {
        Some(source) => {
          let filename = match json_field(params, "filename").as_string() {
            Some(n) => n
            None => "main.c"
          }
          units.push({ filename, source, })
        }
        None => ()
      }
  }
  if units.is_empty() {
    return (
      serve_err(id, "protocol", "compile 需要 params.files 或 params.source").stringify(),
      false,
    )
  }
  s.compile.compile_units = units
  s.compile.compiled = false
  s.unified_pending = None
  ignore(serve_compile_pipeline(s, units))
  (serve_ok(id, compile_result_json(s)).stringify(), false)
}

///|
/// compile 出口 emitter（Rust session_api::compile 的 json! 序照搬）：
/// `{ok, diagnostics, preprocessor_trace}`；诊断元素十字段
/// （end_line/end_column 为「起点 + 1」退化值——Rust Phase 1 同形）。
fn compile_result_json(s : @session.Session) -> Json {
  let diags : Array[Json] = []
  for d in s.compile.diagnostics {
    let m : Map[String, Json] = Map([])
    m.set("code", Json::string("\{severity_prefix(d.severity)}\{d.error_code}"))
    m.set("error_code", d.error_code.to_json())
    m.set("severity", Json::string(severity_name(d.severity)))
    m.set("line", d.line.to_json())
    m.set("column", d.column.to_json())
    m.set("end_line", d.line.to_json())
    m.set("end_column", (d.column + 1).to_json())
    m.set("message", Json::string(d.message))
    m.set("fix_suggestion", Json::string(d.fix_suggestion))
    m.set("filename", Json::string(d.filename))
    diags.push(Json::object(m))
  }
  let trace : Array[Json] = []
  for t in s.compile.preprocessor_trace {
    trace.push(Json::string(t))
  }
  let m : Map[String, Json] = Map([])
  m.set("ok", s.compile.compiled.to_json())
  m.set("diagnostics", Json::array(diags))
  m.set("preprocessor_trace", Json::array(trace))
  Json::object(m)
}
