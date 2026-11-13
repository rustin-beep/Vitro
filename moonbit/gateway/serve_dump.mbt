// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

// S8 dump 族三方法（2026-10-01）：ast.dump / symbols.dump / typeck.dump。
// **只读语义（2026-09-29 契约拍板）**：独立编译通道，**不碰会话状态**——
// oracle 三处错误路径副作用（run_multi_file_pipeline 写 session 诊断）
// 按「已知限制与差异」④表登记不照搬（dump 族无对拍断言锁定，无红线
// 代价）。诊断/产物 emitter 单源复用：ast 字段 = @ast.ast_dump_json
//（E1 面，迁移期 597 语料与 Rust serde 逐字节对拍锁定——零新 emitter）；
// wire 形态 = 拼 cmd/dump_{ast,typeck} 同构 JSON 串后 json_parse 转值。
// diagnostics_probe 已随 S8 段三接线（serve_probe.mbt，2026-10-02——
// 一次性会话承载管线的只读形态）。

///|
/// JSON 字符串转义（含首尾引号）——转义体已收口 @util.json_escape
///（issue #55 六份收一；与 cmd/dump_* 的旧「复制件同步」义务就此解除，
/// 三侧同源 @util）。
fn dump_json_escape(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  @util.json_escape_into(s, buf)
  buf.write_char('"')
  buf.to_string()
}

///|
/// 拼装串转 Json（串由本文件 emitter 拼装——解析失败即拼装 bug，fail loud）。
fn dump_parse_or_abort(s : String) -> Json {
  @util.json_parse(s) catch {
    _ =>
      abort("dump JSON 拼装失败（emitter bug）：\{s[0:80].to_owned()}")
  }
}

///|
/// 深路径 JSON 词法校验器（O(n) 迭代状态机，#418 + #466 审阅 P2-1）：
/// 通过则返回最大嵌套深度（`{`/`[` 计层），任一非法返回 -1。
/// 值级与 json_parse 同强度（fail loud 不因深路径降级）——文法面：
/// 转义合法性（`\"` 八式 + `\uXXXX` 四 hex）/ 字符串裸控制字符禁放 /
/// 数字 RFC 8259（复用 @util.valid_json_number 单源）/ true|false|null
/// 精确匹配 / 键必引号 / 逗号与冒号分隔形态 / 尾随内容。
/// 修前形态（纯配平扫描）对 `{"a":01}`、`"x\qy"` 等坏值返回正值——
/// 深链直拼出非法 JSON 帧的静默降级（审阅 P2-1 实锤）。
priv enum JPhase {
  TopValue // 顶层：期待唯一值
  ArrValueOrClose // 数组：期待元素或 ']'
  KeyOrClose // 对象：期待键 '"' 或 '}'
  Colon // 键后期待 ':'
  CommaOrCloseObj // 成员值后：期待 ',' 或 '}'
  CommaOrCloseArr // 元素后：期待 ',' 或 ']'
  ObjKeyAfterComma // 对象 ',' 后：期待键（禁 '}'——尾逗号非法）
  ArrValueAfterComma // 数组 ',' 后：期待元素（禁 ']'——尾逗号非法）
  Done // 顶层值完成：期待 EOF
}

///|
fn j_peek(text : String, pos : Int32) -> Int32 {
  if pos < text.length() {
    text[pos].to_int()
  } else {
    -1
  }
}

///|
fn j_skip_ws(text : String, pos : Int32) -> Int32 {
  let mut p = pos
  while p < text.length() {
    match text[p].to_int() {
      32 | 9 | 10 | 13 => p += 1
      _ => break
    }
  }
  p
}

///|
fn json_structural_depth(text : String) -> Int32 {
  let n = text.length()
  let mut depth = 0
  let mut max_depth = 0
  let containers : Array[Bool] = [] // true=Obj false=Arr（容器栈）
  let mut phase = TopValue
  let mut pos = 0
  while true {
    pos = j_skip_ws(text, pos)
    let c = j_peek(text, pos)
    // 值消费子程序后的流转标记
    match phase {
      TopValue | ArrValueOrClose | ArrValueAfterComma => {
        if phase is ArrValueOrClose && c == 93 {
          // ']'
          ignore(containers.remove(containers.length() - 1))
          depth -= 1
          phase = if containers.length() == 0 {
            Done
          } else if containers[containers.length() - 1] {
            CommaOrCloseObj
          } else {
            CommaOrCloseArr
          }
          pos += 1
          continue
        }
        match c {
          -1 => return -1
          123 => {
            // '{'
            pos += 1
            depth += 1
            if depth > max_depth {
              max_depth = depth
            }
            containers.push(true)
            phase = KeyOrClose
          }
          91 => {
            // '['
            pos += 1
            depth += 1
            if depth > max_depth {
              max_depth = depth
            }
            containers.push(false)
            phase = ArrValueOrClose
          }
          34 =>
            // '"'
            match j_scan_string(text, pos) {
              Some(next) => {
                pos = next
                phase = if containers.length() == 0 {
                  Done
                } else if containers[containers.length() - 1] {
                  CommaOrCloseObj
                } else {
                  CommaOrCloseArr
                }
              }
              None => return -1
            }
          45 | 48..<=57 =>
            // '-' digit
            match j_scan_number(text, pos) {
              Some(next) => {
                pos = next
                phase = if containers.length() == 0 {
                  Done
                } else if containers[containers.length() - 1] {
                  CommaOrCloseObj
                } else {
                  CommaOrCloseArr
                }
              }
              None => return -1
            }
          116 =>
            // 't'
            match j_scan_lit(text, pos, "true") {
              Some(next) => {
                pos = next
                phase = if containers.length() == 0 {
                  Done
                } else if containers[containers.length() - 1] {
                  CommaOrCloseObj
                } else {
                  CommaOrCloseArr
                }
              }
              None => return -1
            }
          102 =>
            // 'f'
            match j_scan_lit(text, pos, "false") {
              Some(next) => {
                pos = next
                phase = if containers.length() == 0 {
                  Done
                } else if containers[containers.length() - 1] {
                  CommaOrCloseObj
                } else {
                  CommaOrCloseArr
                }
              }
              None => return -1
            }
          110 =>
            // 'n'
            match j_scan_lit(text, pos, "null") {
              Some(next) => {
                pos = next
                phase = if containers.length() == 0 {
                  Done
                } else if containers[containers.length() - 1] {
                  CommaOrCloseObj
                } else {
                  CommaOrCloseArr
                }
              }
              None => return -1
            }
          _ => return -1
        }
      }
      KeyOrClose =>
        match c {
          125 => {
            // '}'
            ignore(containers.remove(containers.length() - 1))
            depth -= 1
            phase = if containers.length() == 0 {
              Done
            } else if containers[containers.length() - 1] {
              CommaOrCloseObj
            } else {
              CommaOrCloseArr
            }
            pos += 1
          }
          34 =>
            match j_scan_string(text, pos) {
              Some(next) => {
                pos = next
                phase = Colon
              }
              None => return -1
            }
          _ => return -1
        }
      ObjKeyAfterComma =>
        if c == 34 {
          match j_scan_string(text, pos) {
            Some(next) => {
              pos = next
              phase = Colon
            }
            None => return -1
          }
        } else {
          return -1
        }
      Colon =>
        if c == 58 {
          // ':'
          pos += 1
          phase = ArrValueOrClose // 复用「期待值」态（容器语义由流转收）
        } else {
          return -1
        }
      CommaOrCloseObj =>
        match c {
          44 => {
            // ','
            pos += 1
            phase = ObjKeyAfterComma
          }
          125 => {
            // '}'
            ignore(containers.remove(containers.length() - 1))
            depth -= 1
            phase = if containers.length() == 0 {
              Done
            } else if containers[containers.length() - 1] {
              CommaOrCloseObj
            } else {
              CommaOrCloseArr
            }
            pos += 1
          }
          _ => return -1
        }
      CommaOrCloseArr =>
        match c {
          44 => {
            // ','
            pos += 1
            phase = ArrValueAfterComma
          }
          93 => {
            // ']'
            ignore(containers.remove(containers.length() - 1))
            depth -= 1
            phase = if containers.length() == 0 {
              Done
            } else if containers[containers.length() - 1] {
              CommaOrCloseObj
            } else {
              CommaOrCloseArr
            }
            pos += 1
          }
          _ => return -1
        }
      Done => {
        if pos >= n {
          return max_depth
        }
        return -1
      }
    }
  }
  // 不可达（Done 分支必 return）
  abort("unreachable：json_structural_depth 状态机 Done 必然返回")
}

///|
/// 字符串扫描（pos 指向开头 '"'）：合法返回消费后的下一位置，非法 None
/// ——转义八式 + \uXXXX 四 hex + 裸控制字符（< 0x20）禁放。
fn j_scan_string(text : String, pos : Int32) -> Int32? {
  let n = text.length()
  let mut p = pos + 1 // 跳过开头引号
  while p < n {
    let c = text[p].to_int()
    if c == 34 {
      // '"'
      return Some(p + 1)
    }
    if c == 92 {
      // '\'
      p += 1
      if p >= n {
        return None
      }
      match text[p].to_int() {
        34 | 92 | 47 | 98 | 102 | 110 | 114 | 116 => p += 1
        117 => {
          // 'u' 四 hex
          p += 1
          let mut k = 0
          while k < 4 {
            if p >= n {
              return None
            }
            let h = text[p].to_int()
            let ok = (h >= 48 && h <= 57) ||
              (h >= 97 && h <= 102) ||
              (h >= 65 && h <= 70)
            if !ok {
              return None
            }
            p += 1
            k += 1
          }
        }
        _ => return None
      }
    } else if c < 0x20 {
      return None
    } else {
      p += 1
    }
  }
  None
}

///|
/// 数字扫描（pos 指向 '-' 或数字首字符）：字符集段截取后走
/// @util.valid_json_number 单源文法。
fn j_scan_number(text : String, pos : Int32) -> Int32? {
  let n = text.length()
  let mut p = pos
  while p < n {
    match text[p].to_int() {
      45 | 43 | 46 | 101 | 69 | 48..<=57 => p += 1
      _ => break
    }
  }
  let seg = text[pos:p].to_owned()
  if @util.valid_json_number(seg) {
    Some(p)
  } else {
    None
  }
}

///|
/// 字面量精确匹配（true/false/null）。
fn j_scan_lit(text : String, pos : Int32, word : String) -> Int32? {
  let wn = word.length()
  if pos + wn > text.length() {
    return None
  }
  for i = 0; i < wn; i = i + 1 {
    if text[pos + i] != word[i] {
      return None
    }
  }
  Some(pos + wn)
}

///|
/// dump 族成功帧出口（#418，2026-11-03）：emitter 文本 → 响应帧串。
/// 浅文本（结构深度 ≤ 128）：现行为——json_parse 自检后经 Json 值
/// stringify（紧凑口径，emitter bug 真 fail loud）。
/// 深文本（> 128）：**文本直拼**——合法深 AST 的 dump JSON 深度可达
/// 数百层（unary_chain 十万层语料数十万层），Json 值中转两处递归
/// （parse_value / core stringify）在 wasm 栈上不可持续；深路径以
/// `json_structural_depth` 的结构校验（配平 + 字符串闭合）替代全量
/// 自检，原文直拼进帧（帧内空白与浅路径的紧凑化形态分叉——JSON
/// 语义等值，消费方一律经 JSON 解析）。结构坏 = 真 emitter bug，
/// 深浅两路径一致 fail loud。
fn dump_frame_ok(id : Json, emitter_text : String) -> String {
  let d = json_structural_depth(emitter_text)
  if d < 0 {
    abort(
      "dump JSON 拼装失败（emitter bug，结构不配平）：\{emitter_text[0:80].to_owned()}",
    )
  }
  // #466 审阅 P1（2026-11-04）：json_parse 的 depth 是递归栈深（末层标量
  // 也占一层）——结构深度 k 的文本栈深 k+1，上限 128 只容 k ≤ 127 走浅
  // 路径；`d <= 128` 会把 k=128 的合法帧送进浅路径必然超限 abort（越界
  // 一格——审阅实测 56 项合法加法链包 if 即落此档，rc=0xC0000409）。
  if d < 128 {
    serve_ok(id, dump_parse_or_abort(emitter_text)).stringify()
  } else {
    "{\"id\":\{id.stringify()},\"ok\":true,\"result\":\{emitter_text}}"
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
      serve_param_err(
        id, "ast.dump 需要 params.source:string", "source:string",
      ).stringify(),
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
    return (dump_frame_ok(id, buf.to_string()), false)
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
  (dump_frame_ok(id, buf.to_string()), false)
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
  // files 面（2026-11-13 DEF-1）：files:[{filename,source}] → 走
  // assemble_units 同款装配（头文件进 vfs、.c 拼接 + #364 不动点）——
  // 与 compile 通道单源；单文件形态 params.source 原语义不变（空 vfs，
  // quote-include 集合外 E1021 宁诊断不静默）。旧形态只收 source：
  // mcp 的 overview 对 quote-include 工程喂主文件原文 → E1021 →
  // typed_ast:null → funcs 静默空（DEF-1「编译成功但 overview 空」）。
  // params→units 解析 = units_from_params 单源（PR #509 审阅 P3-1——
  // 与 serve_compile_frame 原逐字重复）。
  let units = match units_from_params(params, "typeck.dump") {
    Ok(u) => u
    Err(msg) =>
      return (
        serve_param_err(
          id, msg, "files:[{filename?,source}] | source:string[,filename:string]",
        ).stringify(),
        false,
      )
  }
  let (_, _, lexed) = assemble_units(units)
  let buf = StringBuilder()
  if !lexed.errors.is_empty() {
    buf.write_string(
      "{\"ok\": false, \"lex_error_count\": \{lexed.errors.length()}, \"typed_ast\": null, \"parse_errors\": [], \"type_errors\": [], \"type_warnings\": [], \"type_hints\": []}",
    )
    return (dump_frame_ok(id, buf.to_string()), false)
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
    return (dump_frame_ok(id, buf.to_string()), false)
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
  (dump_frame_ok(id, buf.to_string()), false)
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
      serve_param_err(
        id, "symbols.dump 需要 params.source:string", "source:string",
      ).stringify(),
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
    m.set("name", Json(sym.name))
    m.set("addr", Json::number(sym.addr.to_double()))
    m.set("is_local", Json(sym.is_local))
    m.set("decl_line", Json(sym.decl_line))
    arr.push(Json::object(m))
  }
  let m : Map[String, Json] = Map([])
  m.set("ok", Json(compiled))
  m.set("symbols", Json::array(arr))
  m.set("count", Json(symbols.length()))
  (serve_ok(id, Json::object(m)).stringify(), false)
}

///|
/// codegen.dump（#52 结构面①，2026-10-17）：编译产物转储出口——字节码
/// 跳转图 + 每指令源码行号（流程图原料）。**复用既有单源 emitter**
/// `@bytecode.compile_output_dump_json`（codegen_diff 逐字节对拍锁定的
/// 同一份 14 键产物形状，B 级锚），不造第二份转储器；wire 侧把 emitter
/// 文本 parse 回 Json 嵌入 result（协议帧结构要求，非二次发射）。
/// 只读语义：独立单遍管线（params.source），零会话态写入——dump 族纪律。
/// 命名：对齐 dump 族形态（ast/typeck/symbols/diagnostics_probe 同族），
/// issue #52 建议命名即 codegen.dump（不另设 codegen_dump 别名）。
fn serve_codegen_dump_frame(
  _s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  guard json_field(params, "source").as_string() is Some(source) else {
    return (
      serve_param_err(
        id, "codegen.dump 需要 params.source:string", "source:string",
      ).stringify(),
      false,
    )
  }
  let filename = match json_field(params, "filename").as_string() {
    Some(f) => f
    None => "main.c"
  }
  let units : Array[@session.CompileUnit] = [{ filename, source, }]
  let (full_source, _) = merge_units(units)
  let lexed = lex_full_source(full_source, units)
  if !lexed.errors.is_empty() {
    return (
      serve_err(
        id, "compile", "codegen.dump：词法错误，无产物可转储",
      ).stringify(),
      false,
    )
  }
  let r = @parser.parse(lexed.tokens)
  guard r.program is Some(program) else {
    return (
      serve_err(
        id, "compile", "codegen.dump：语法错误，无产物可转储",
      ).stringify(),
      false,
    )
  }
  if !r.errors.is_empty() {
    return (
      serve_err(
        id, "compile", "codegen.dump：语法错误，无产物可转储",
      ).stringify(),
      false,
    )
  }
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, _w, _h) = tc.check(program)
  if !type_errors.is_empty() {
    return (
      serve_err(
        id, "compile", "codegen.dump：类型错误，无产物可转储",
      ).stringify(),
      false,
    )
  }
  match @codegen.compile(typed).0 {
    Some(output) => {
      let dump_text = @bytecode.compile_output_dump_json(output)
      // #418（2026-11-03）：emitter 文本 → 帧出口统一走 dump_frame_ok
      //（浅路径 json_parse 自检 fail loud——原 catch { Json::null() } 把
      // emitter bug 静默吞成 null 帧，违反全域 fail loud 纪律；深产物
      // 结构校验后直拼——原 parse 在深度 128 处把合法深产物降级 null）
      (dump_frame_ok(id, dump_text), false)
    }
    None =>
      (
        serve_err(
          id, "compile", "codegen.dump：字节码生成失败，无产物可转储",
        ).stringify(),
        false,
      )
  }
}
