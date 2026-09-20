///|
/// S4 差分出口（开发工具，native only）：批量产出类型检查层 dump——
/// typed_ast JSON（E4 面：lowering 后 ProgramNode）+ 三段诊断序列
/// （E1 面：type_errors/type_warnings/type_hints，{code,line,column,
/// message} push 序保序）。
///
/// 用法：moon run cmd/dump_typeck -- <corpus_dir|file.c> <out_dir>
///
/// 输出（每输入 <name>.c）：
/// - <name>.c.typeck.json：与 Rust serve `typeck.dump` 响应同构——
///   {"ok":bool,"parse_error_count":N,"typed_ast":{...}|null,
///    "parse_errors":[...],
///    "type_errors":[...],"type_warnings":[...],"type_hints":[...]}
///
/// **当前形态**：typeck C 子集 4 Pass 部分接线——Pass 1（struct/union
/// 注册 + T-P0-8 环检测）/ Pass 2（函数签名）/ Pass 2.5（全局登记 +
/// U1#12 数组尺寸三形状）已落地；表达式定型 / 初始化器检查 / Pass 3
/// 函数体 visitor 随 expr/decl/init 批接线（当前直通不检查——typed_ast
/// 的 ty 保持 parser 占位）。红面 = 未接线面，实现推进逐步收敛。
/// E2/E3 面不独立出口（驱动从 typed_ast 投影派生——改形登记见总计划
/// §10 S4 行）。
///
/// **载体观察（2026-09-20 审阅）**：目录模式注入 dir-wide vfs，但
/// `tokenize_with_vfs` 的 base_dir 默认 "."，quote-include 候选键
/// `./x.h` 与 vfs 绝对路径键结构性不命中——注入实际无效，两侧同无
/// 自定义 include 解析（与 S3 dump_ast 同款既有模式，597 SAME 属
/// "两侧同失败"的一致——偶然对齐，哨兵用例随 expr 批两出口统一补）。
fn main raise {
  let args = @env.args()
  if args.length() < 3 {
    println("用法: dump_typeck <corpus_dir|file.c> <out_dir>")
    fail("参数不足")
  }
  let target = args[1]
  let out_dir = args[2]
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir)
  }
  let files : Array[String] = []
  let target_is_dir = @fs.is_dir(target) catch { _ => false }
  // 自定义 include 的 Vfs 目录级收集一次共享（S2 §7-5 性能教训）
  let shared_vfs : Map[String, String] = if target_is_dir {
    let vfs : Map[String, String] = Map([])
    collect_files(target, vfs)
    vfs
  } else {
    Map([])
  }
  if target_is_dir {
    for name in @fs.read_dir(target) {
      if name.length() > 2 && name[name.length() - 2:] == ".c" {
        files.push("\{target}/\{name}")
      }
    }
    files.sort()
  } else {
    files.push(target)
  }
  for path in files {
    let src = @fs.read_file_to_string(path)
    let stem = basename_no_ext(path)
    let lexed = if target_is_dir {
      @lexer.tokenize_with_vfs(src, files=shared_vfs)
    } else {
      @lexer.tokenize(src)
    }
    let out = dump_one(lexed)
    // basename_no_ext 实为"取 basename 不去扩展名"（F11 规格：stem 含
    // .c——与 parser_diff 既有对拍约定同源，勿"修正"）
    @fs.write_string_to_file("\{out_dir}/\{stem}.typeck.json", out)
  }
  println("dump_typeck: \{files.length()} 个输入 -> \{out_dir}")
}

///|
/// 单输入 dump：词法错误 → ok:false 同构（typeck 无从谈起，lex_error_count
/// 面）；解析层带完整 parse_errors；parse 错误 → typeck 不跑（管线语义：
/// parse_errors 非空即止，与 Rust compile_pipeline 对齐）。
fn dump_one(lexed : @lexer.LexResult) -> String {
  let buf = StringBuilder()
  if !lexed.errors.is_empty() {
    buf.write_string("{\"ok\": false, \"lex_error_count\": ")
    buf.write_string(lexed.errors.length().to_string())
    buf.write_string(
      ", \"typed_ast\": null, \"parse_errors\": [], \"type_errors\": [], \"type_warnings\": [], \"type_hints\": []}",
    )
    return buf.to_string()
  }
  let r = @parser.parse(lexed.tokens)
  // 管线语义：parse 错误非空（无论 program 是否带占位）→ typeck 不跑
  if !r.errors.is_empty() || r.program is None {
    buf.write_string("{\"ok\": false, \"parse_error_count\": ")
    buf.write_string(r.errors.length().to_string())
    buf.write_string(", \"typed_ast\": null, \"parse_errors\": [")
    for i, e in r.errors {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string(
        "{\"code\": \{e.code}, \"line\": \{e.line}, \"column\": \{e.column}, \"message\": \{json_escape(e.message)}}",
      )
    }
    buf.write_string(
      "], \"type_errors\": [], \"type_warnings\": [], \"type_hints\": []}",
    )
    return buf.to_string()
  }
  // —— typeck 实接线（C 子集 4 Pass；表达式族/初始化器/函数体 visitor
  // 随下批补——当前 Pass 1/2/2.5 部分面）——
  let p = match r.program {
    Some(p) => p
    None => abort("unreachable：None 已在上方拦截")
  }
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, type_warnings, type_hints) = tc.check(p)
  buf.write_string("{\"ok\": true, \"parse_error_count\": 0, \"typed_ast\": ")
  buf.write_string(@ast.ast_dump_json(typed))
  buf.write_string(", \"parse_errors\": [], \"type_errors\": [")
  write_diag_array(buf, type_errors)
  buf.write_string("], \"type_warnings\": [")
  write_diag_array(buf, type_warnings)
  buf.write_string("], \"type_hints\": [")
  write_diag_array(buf, type_hints)
  buf.write_string("]}")
  buf.to_string()
}

///|
/// 三段诊断序列序列化（{code,line,column,message} push 序保序——与
/// parse_errors 同形态）。
fn write_diag_array(
  buf : StringBuilder,
  diags : Array[@typeck.TypeError],
) -> Unit {
  for i, e in diags {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(
      "{\"code\": \{e.code}, \"line\": \{e.line}, \"column\": \{e.column}, \"message\": \{json_escape(e.message)}}",
    )
  }
}

///|
/// JSON 字符串字面量转义（serde_json 口径：控制字符 \u00XX；与 dump_ast
/// 同源——E1 面 message 在 canonicalize 逐字节比较面内）。
fn json_escape(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('\"')
  for c in s {
    match c {
      '\"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => {
        let code = c.to_int()
        if code < 32 {
          buf.write_string("\\u00")
          let hex = "0123456789abcdef"
          buf.write_string(hex[code / 16:code / 16 + 1].to_owned())
          buf.write_string(hex[code % 16:code % 16 + 1].to_owned())
        } else {
          buf.write_char(c)
        }
      }
    }
  }
  buf.write_char('\"')
  buf.to_string()
}

///|
fn basename_no_ext(path : String) -> String {
  let mut name = path
  let mut i = path.length() - 1
  while i >= 0 {
    let slash = '/'.to_int()
    let bslash = 92 // '\'
    let dot = '.'.to_int()
    match path[i].to_int() {
      c if c == slash || c == bslash => {
        name = path[i + 1:].to_owned()
        break
      }
      c if c == dot => if name == path { name = path[0:i].to_owned() }
      _ => ()
    }
    i -= 1
  }
  name
}

///|
fn collect_files(dir : String, vfs : Map[String, String]) -> Unit raise {
  for name in @fs.read_dir(dir) {
    let full = "\{dir}/\{name}"
    let is_dir = @fs.is_dir(full) catch { _ => false }
    if is_dir {
      collect_files(full, vfs)
    } else {
      let content = @fs.read_file_to_string(full) catch { _ => continue }
      vfs.set(full, content)
    }
  }
}
