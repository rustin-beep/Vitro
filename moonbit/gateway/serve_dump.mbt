// S8 dump 族三方法（2026-10-01）：ast.dump / symbols.dump / typeck.dump。
// **只读语义（2026-09-29 契约拍板）**：独立编译通道，**不碰会话状态**——
// oracle 三处错误路径副作用（run_multi_file_pipeline 写 session 诊断）
// 按「已知限制与差异」④表登记不照搬（dump 族无对拍断言锁定，无红线
// 代价）。诊断/产物 emitter 单源复用：ast 字段 = @ast.ast_dump_json
//（E1 面，597 语料与 Rust serde 逐字节一致——零新 emitter）；
// wire 形态 = 拼 cmd/dump_{ast,typeck} 同构 JSON 串后 json_parse 转值。
// diagnostics_probe 已随 S8 段三接线（serve_probe.mbt，2026-10-02——
// 一次性会话承载管线的只读形态）。

///|
/// JSON 字符串转义（cmd/dump_* 的 json_escape 复制件——含首尾引号；
/// 修改须两侧同步）。
fn dump_json_escape(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => {
        // 控制字符防御性转义（serde_json 口径）
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
  buf.write_char('"')
  buf.to_string()
}

///|
/// 拼装串转 Json（串由本文件 emitter 拼装——解析失败即拼装 bug，fail loud）。
fn dump_parse_or_abort(s : String) -> Json {
  json_parse(s) catch {
    _ =>
      abort("dump JSON 拼装失败（emitter bug）：\{s[0:80].to_owned()}")
  }
}

///|
/// typeck 三段诊断数组段（cmd/dump_typeck 的 write_diag_array 复制件）。
fn write_type_diag_array(
  buf : StringBuilder,
  diags : Array[@typeck.TypeError],
) -> Unit {
  for i, e in diags {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(
      "{\"code\": \{e.code}, \"line\": \{e.line}, \"column\": \{e.column}, \"message\": \{dump_json_escape(e.message)}}",
    )
  }
}

///|
/// 解析诊断数组段（cmd/dump_ast 的 parse_errors 段同构）。
fn write_parse_diag_array(
  buf : StringBuilder,
  diags : Array[@parser.ParseError],
) -> Unit {
  for i, e in diags {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(
      "{\"code\": \{e.code}, \"line\": \{e.line}, \"column\": \{e.column}, \"message\": \{dump_json_escape(e.message)}}",
    )
  }
}

///|
/// ast.dump（session_api.rs:95 ast_dump 照搬——副作用剔除）：lexer→parser
/// 独立通道；词法错误路径五字段同构（ok:false + lex_error_count + ast:null
/// + 空 parse_errors + stall_count 0）；成功带 E1 emitter 的 AST。
fn serve_ast_dump_frame(
  _s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  guard json_field(params, "source").as_string() is Some(source) else {
    return (
      serve_err(id, "protocol", "ast.dump 需要 params.source").stringify(),
      false,
    )
  }
  // include 通道与 compile 同源（宿主注册态分叉——native 真 fs / wasm
  // E1021）；单文件无 merge（Rust Lexer::new(source) 单文件口径）
  let lexed = lex_full_source(source, [])
  let buf = StringBuilder()
  if !lexed.errors.is_empty() {
    buf.write_string(
      "{\"ok\": false, \"lex_error_count\": \{lexed.errors.length()}, \"ast\": null, \"parse_errors\": [], \"stall_count\": 0}",
    )
    return (
      serve_ok(id, dump_parse_or_abort(buf.to_string())).stringify(),
      false,
    )
  }
  let r = @parser.parse(lexed.tokens)
  buf.write_string("{\"ok\": ")
  buf.write_string(if r.program is Some(_) { "true" } else { "false" })
  buf.write_string(", \"parse_error_count\": \{r.errors.length()}, \"ast\": ")
  match r.program {
    Some(p) => buf.write_string(@ast.ast_dump_json(p))
    None => buf.write_string("null")
  }
  buf.write_string(", \"parse_errors\": [")
  write_parse_diag_array(buf, r.errors)
  buf.write_string("], \"stall_count\": \{r.stall_count}}")
  (serve_ok(id, dump_parse_or_abort(buf.to_string())).stringify(), false)
}

///|
/// typeck.dump（session_api.rs typeck_dump 照搬——副作用剔除）：lexer→
/// parser→typeck **不进 codegen**；词法/语法错误路径六字段同构；成功带
/// lowering 后 typed_ast（E1 emitter 序列化——插入 Cast/dims 推断/ty
/// 定型在内）与三段诊断（push 序保序）。
fn serve_typeck_dump_frame(
  _s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  guard json_field(params, "source").as_string() is Some(source) else {
    return (
      serve_err(id, "protocol", "typeck.dump 需要 params.source").stringify(),
      false,
    )
  }
  let lexed = lex_full_source(source, [])
  let buf = StringBuilder()
  if !lexed.errors.is_empty() {
    buf.write_string(
      "{\"ok\": false, \"lex_error_count\": \{lexed.errors.length()}, \"typed_ast\": null, \"parse_errors\": [], \"type_errors\": [], \"type_warnings\": [], \"type_hints\": []}",
    )
    return (
      serve_ok(id, dump_parse_or_abort(buf.to_string())).stringify(),
      false,
    )
  }
  let r = @parser.parse(lexed.tokens)
  // 管线语义：parse 错误非空（无论 program 是否带占位）→ typeck 不跑
  if !r.errors.is_empty() || r.program is None {
    buf.write_string(
      "{\"ok\": false, \"parse_error_count\": \{r.errors.length()}, \"typed_ast\": null, \"parse_errors\": [",
    )
    write_parse_diag_array(buf, r.errors)
    buf.write_string(
      "], \"type_errors\": [], \"type_warnings\": [], \"type_hints\": []}",
    )
    return (
      serve_ok(id, dump_parse_or_abort(buf.to_string())).stringify(),
      false,
    )
  }
  guard r.program is Some(p) else { abort("unreachable：None 已拦截") }
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, type_warnings, type_hints) = tc.check(p)
  buf.write_string("{\"ok\": true, \"parse_error_count\": 0, \"typed_ast\": ")
  buf.write_string(@ast.ast_dump_json(typed))
  buf.write_string(", \"parse_errors\": [], \"type_errors\": [")
  write_type_diag_array(buf, type_errors)
  buf.write_string("], \"type_warnings\": [")
  write_type_diag_array(buf, type_warnings)
  buf.write_string("], \"type_hints\": [")
  write_type_diag_array(buf, type_hints)
  buf.write_string("]}")
  (serve_ok(id, dump_parse_or_abort(buf.to_string())).stringify(), false)
}

///|
/// symbols.dump（session_api.rs:164 symbols_dump 照搬——只读形态）：
/// 独立跑全管线（merge→lex→parse→typeck→codegen）取产物 symbols 表
///（全局 + 局部统一：name/addr/is_local/decl_line）——不写 session
///（oracle 走 run_multi_file_pipeline 复用会话管线，副作用不照搬）。
fn serve_symbols_dump_frame(
  _s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  guard json_field(params, "source").as_string() is Some(source) else {
    return (
      serve_err(id, "protocol", "symbols.dump 需要 params.source").stringify(),
      false,
    )
  }
  let filename = match json_field(params, "filename").as_string() {
    Some(f) => f
    None => "main.c"
  }
  let units : Array[@session.CompileUnit] = [{ filename, source, }]
  // 单遍独立管线（serve_compile_pipeline 的只读投影——状态零写入）。
  // 错误路径两侧均空表（审阅 P3 实测：oracle 管线失败即清 session.
  // compile.symbols，无「失败残留」形态——早前头注声称的分叉不存在，
  // 已删；只读通道失败同样空表，行为两侧一致）
  let (full_source, _) = merge_units(units)
  let lexed = lex_full_source(full_source, units)
  let symbols : Array[@bytecode.Symbol] = []
  let compiled = if !lexed.errors.is_empty() {
    false
  } else {
    let r = @parser.parse(lexed.tokens)
    if !r.errors.is_empty() || r.program is None {
      false
    } else {
      guard r.program is Some(p) else { abort("unreachable") }
      let tc = @typeck.TypeChecker::new()
      let (typed, type_errors, _w, _h) = tc.check(p)
      if !type_errors.is_empty() {
        false
      } else {
        match @codegen.compile(typed).0 {
          Some(o) => {
            for sym in o.symbols {
              symbols.push(sym)
            }
            true
          }
          None => false
        }
      }
    }
  }
  let arr : Array[Json] = []
  for sym in symbols {
    let m : Map[String, Json] = Map([])
    m.set("name", sym.name.to_json())
    m.set("addr", Json::number(sym.addr.to_double()))
    m.set("is_local", sym.is_local.to_json())
    m.set("decl_line", sym.decl_line.to_json())
    arr.push(Json::object(m))
  }
  let m : Map[String, Json] = Map([])
  m.set("ok", compiled.to_json())
  m.set("symbols", Json::array(arr))
  m.set("count", symbols.length().to_json())
  (serve_ok(id, Json::object(m)).stringify(), false)
}
