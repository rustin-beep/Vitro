///|
/// 展开深度保险丝（U1#6：检查点在**每层递归入口**——不同名对象宏链
/// `A0→A1→…→A5000` 不触发自引用查重，此前 5000 层实测栈溢出）。
const EXPAND_DEPTH_FUSE : Int32 = 64

///|
/// 展开规模保险丝：深度限深不限宽（`REP(x) x x` 嵌套 64 层 = 2^64 token），
/// 计费口径 = **累计字节数**（token 文本 UTF-8 字节长 +1 分隔；U1#6——
/// 旧 token 个数口径下 4KB 字面量 ×14 层 = 16384 token 不触预算但实际 67MB）。
const EXPAND_BYTE_BUDGET : Int32 = 16 * 1024 * 1024

///|
/// 展开链/分支原因教学记录的容量上限。
const TEACHING_TRACE_CAP : Int32 = 64

///|
/// 单条教学追踪记录的长度上限（U1#6：条数封顶不防单条）。
const TRACE_ENTRY_MAX_CHARS : Int32 = 2048

///|
/// 展开上下文（宏表 + 诊断/教学通道 + 双保险丝熔断记账）。
priv struct ExpandCtx {
  macros : Map[String, @token.MacroDef]
  errors : Array[@token.LexError]
  warnings : Array[@token.LexWarning]
  trace : Array[@token.TraceEntry]
  /// `#if` 表达式求值场景：展开链噪声不记录。
  expr_mode : Bool
  mut emitted : Int32
  mut budget_exhausted : Bool
  mut depth_exceeded : Bool
}

///|
/// 全量宏展开入口（tokenize 收尾；expr_mode=false）。
fn[P] Pp::expand_tokens_all(
  self : Pp[P],
  tokens : Array[@token.Token],
) -> Array[@token.Token] {
  let ctx : ExpandCtx = {
    macros: self.macros,
    errors: self.errors,
    warnings: self.warnings,
    trace: self.trace,
    expr_mode: false,
    emitted: 0,
    budget_exhausted: false,
    depth_exceeded: false,
  }
  expand_tokens(ctx, tokens, 0)
}

///|
fn expand_tokens(
  ctx : ExpandCtx,
  tokens : Array[@token.Token],
  depth : Int32,
) -> Array[@token.Token] {
  expand_inner(ctx, tokens, depth, [])
}

///|
/// 展开栈（等价 Rust `HashSet<String>`——蓝漆教学子集实现；深度 ≤64，
/// 线性查重成本可忽略，换来不可变共享与路径回溯的简单性）。
fn expanding_contains(list : Array[String], name : String) -> Bool {
  list.contains(name)
}

///|
fn expand_inner(
  ctx : ExpandCtx,
  tokens : Array[@token.Token],
  depth : Int32,
  expanding : Array[String],
) -> Array[@token.Token] {
  if budget_hit(ctx, tokens) {
    return []
  }
  // U1#6：深度保险丝移入每层递归入口（此前只在 depth=0 检查 = 死代码）
  if depth >= EXPAND_DEPTH_FUSE {
    if !ctx.depth_exceeded {
      ctx.depth_exceeded = true
      ctx.errors.push({
        message: "宏展开深度超过保险丝（\{EXPAND_DEPTH_FUSE} 层）。请检查是否存在过长的宏展开链（如 #define A0 A1、#define A1 A2 依次接力）",
        loc: {
          line: if tokens.length() > 0 {
            tokens[0].loc.line
          } else {
            0
          },
          column: 0,
          file_id: 0,
        },
        code: E1017_ExpandDepthExceeded,
      })
    }
    return tokens
  }
  let result : Array[@token.Token] = []
  let mut i = 0
  while i < tokens.length() {
    let tok = tokens[i]
    if !(tok.ty is Identifier) {
      result.push(tok)
      i += 1
      continue
    }
    let mdef = match ctx.macros.get(tok.text) {
      Some(d) => d
      None => {
        result.push(tok)
        i += 1
        continue
      }
    }
    if expanding_contains(expanding, tok.text) {
      // 自引用停止（蓝漆等价物）：C99 6.10.3.1
      result.push(tok)
      i += 1
      continue
    }
    match mdef {
      Object(body~) => {
        expanding.push(tok.text)
        let sub = substitute_params(body, [], None)
        if sub.paste_err is Some(msg) {
          ctx.errors.push({
            message: msg,
            loc: {
              line: tok.loc.line,
              column: tok.loc.column,
              file_id: tok.loc.file_id,
            },
            code: E1016_TokenPasteInvalid,
          })
        }
        let expanded = expand_inner(ctx, sub.tokens, depth + 1, expanding)
        record_trace(ctx, tok.text, None, expanded, depth)
        ignore(expanding.pop())
        for mt in expanded {
          result.push(pin_to_call_site(mt, tok))
        }
        i += 1
      }
      Function(params~, ..) => {
        // 参数化宏：下一个 token 必须是 '('，否则按普通标识符保留
        if i + 1 >= tokens.length() || !(tokens[i + 1].ty is LParen) {
          result.push(tok)
          i += 1
          continue
        }
        // 捕获实参（平衡括号内按逗号切分）
        let captured = capture_args(tokens, i)
        let args = captured.args
        let j = captured.end_index // RParen 位置
        // 病 41 修复（#71 第二梯队，2026-10-11）：实参捕获扫到文件尾仍未
        // 平衡（j 越界且 depth>0）——此前静默把后续全部 token 吞进末实参
        // 继续展开（expander 零诊断，根因由 parser 级联错位兜底不可见；
        // clang = "unterminated function-like macro invocation" 单诊断
        // 病根位）。显式诊断 + fail-fast 跳尾（报错即文档——不再展开）。
        if j >= tokens.length() {
          ctx.errors.push({
            message: "未闭合的函数式宏调用 '\{tok.text}'——缺少匹配的右括号（实参捕获扫到文件尾）。请补全调用括号。",
            loc: {
              line: tok.loc.line,
              column: tok.loc.column,
              file_id: tok.loc.file_id,
            },
            code: E1005_InvalidDefine,
          })
          i = tokens.length()
          continue
        }
        // C 语义：`FOO()`（唯一空实参）匹配零参数函数式宏（修复 ⑥-9 的
        // 配套捕获口径——空实参表归一为零实参）
        let arg_count = if args.length() == 1 &&
          args[0].length() == 0 &&
          params.length() == 0 {
          0
        } else {
          args.length()
        }
        // #164（2026-10-21，C99 §6.10.3）：变参宏——多余实参绑定到隐式
        // `__VA_ARGS__`（join 逗号）；命名实参数不足仍报错（变参下限 =
        // 命名形参数，文案区分「期望 N」vs「期望至少 N」）
        let variadic = match mdef {
          Function(variadic~, ..) => variadic
          Object(_) => false
        }
        if (!variadic && arg_count != params.length()) ||
          (variadic && arg_count < params.length()) {
          // 修复 ⑥-10：Rust 静默保留（后续 E3023"未声明的变量"错位到使用点，
          // 真因在宏定义处）——改为预处理阶段显式诊断 + fail-soft 保留原 token。
          // 差异登记：与 Rust 的 L2 token 流一致（fail-soft 行为同），仅多一条诊断
          let expect = if variadic {
            "至少 \{params.length()}"
          } else {
            "\{params.length()}"
          }
          ctx.errors.push({
            message: "宏 '\{tok.text}' 调用参数个数不匹配（期望 \{expect}，实得 \{arg_count}）",
            loc: {
              line: tok.loc.line,
              column: tok.loc.column,
              file_id: tok.loc.file_id,
            },
            code: E1005_InvalidDefine,
          })
          result.push(tok)
          i += 1
          continue
        }
        // W1019：宏参数副作用检测
        warn_side_effects(ctx, tok.text, mdef, args, tok)
        // C99 §6.10.3.1：实参先行完整展开（同宏嵌套 MAX(MAX(1,5),3) 正确工作）；
        // 体含 `#`/`##` 时例外——操作数用未展开实参（C99 §6.10.3.3）
        let body = match mdef {
          Function(body~, ..) => body
          Object(body~) => body
        }
        let body_has_operators = body
          .iter()
          .any(t => t.ty is Hash || t.ty is HashHash)
        let subst_args : Array[Array[@token.Token]] = []
        for a in args {
          if body_has_operators {
            subst_args.push(a)
          } else {
            subst_args.push(expand_inner(ctx, a, depth + 1, expanding))
          }
        }
        // #164：变参绑定——eff 参数表追加 __VA_ARGS__；命名段截断后
        // 变参段（raw 与已展开两轨）以调用点定位的逗号 token join 成单段
        //（旧全量段 + push(join) 段数错位：arg_of 按 params 下标取到第二
        // 实参段，第三实参起全丢——ADD3(1,2,3,4) 展开成 add4(1,2) 实锤）
        let eff_params : Array[String] = params.copy()
        let eff_args : Array[Array[@token.Token]] = []
        let eff_subst : Array[Array[@token.Token]] = []
        for k = 0; k < params.length(); k = k + 1 {
          if k < args.length() {
            eff_args.push(args[k])
          }
          if k < subst_args.length() {
            eff_subst.push(subst_args[k])
          }
        }
        if variadic && arg_count > params.length() {
          eff_params.push("__VA_ARGS__")
          let va_raw : Array[@token.Token] = []
          let va_sub : Array[@token.Token] = []
          for k = params.length(); k < args.length(); k = k + 1 {
            if k > params.length() {
              // 切出 args[k] 的顶层逗号原件（seps[k-1]，#164 补）——
              // byte_off/loc 用真实源码位置：`#__VA_ARGS__` 字符串化按
              // 源码空白拼空格（`SV(1 , 2)` → `1 , 2`）；合成逗号钉调用
              // 点会丢逗号前空白
              let sep_tok = captured.seps.get(k - 1).unwrap_or(tok)
              va_raw.push(@token.Token::{
                ty: Comma,
                text: ",",
                loc: (if args[k].length() > 0 { args[k][0] } else { tok }).loc,
                byte_off: sep_tok.byte_off,
                real_line: sep_tok.real_line,
              })
              va_sub.push(@token.Token::{
                ty: Comma,
                text: ",",
                loc: (if subst_args[k].length() > 0 {
                  subst_args[k][0]
                } else {
                  tok
                }).loc,
                byte_off: sep_tok.byte_off,
                real_line: sep_tok.real_line,
              })
            }
            for t in args[k] {
              va_raw.push(t)
            }
            for t in subst_args[k] {
              va_sub.push(t)
            }
          }
          eff_args.push(va_raw)
          eff_subst.push(va_sub)
        } else if variadic {
          // 零变参实参：__VA_ARGS__ 绑定空序列（标准 C 下 `LOG("x")` 的
          // `fmt, __VA_ARGS__` 残留逗号是已知语法坑——GNU `, ##__VA_ARGS__`
          // 扩展不支持，P0 不做）
          eff_params.push("__VA_ARGS__")
          eff_args.push([])
          eff_subst.push([])
        }
        expanding.push(tok.text)
        let sub = substitute_params_ext(
          body,
          eff_params,
          Some(eff_args),
          Some(eff_subst),
        )
        if sub.paste_err is Some(msg) {
          ctx.errors.push({
            message: msg,
            loc: {
              line: tok.loc.line,
              column: tok.loc.column,
              file_id: tok.loc.file_id,
            },
            code: E1016_TokenPasteInvalid,
          })
        }
        // H01 行为契约：宏体为大括号块且调用后紧跟分号 → 包装 do{...}while(0)
        let substituted = sub.tokens
        let body_is_brace_block = body.length() > 0 &&
          body[0].ty is LBrace &&
          body[body.length() - 1].ty is RBrace
        let followed_by_semicolon = j + 1 < tokens.length() &&
          tokens[j + 1].ty is Semicolon
        if body_is_brace_block && followed_by_semicolon {
          substituted.insert(0, synth_token(Do, "do").pin(tok))
          substituted.push(synth_token(While, "while").pin(tok))
          substituted.push(synth_token(LParen, "(").pin(tok))
          substituted.push(synth_token(Number, "0").pin(tok))
          substituted.push(synth_token(RParen, ")").pin(tok))
        }
        let expanded = expand_inner(ctx, substituted, depth + 1, expanding)
        record_trace_ctx(ctx, tok.text, Some(args), expanded, depth)
        ignore(expanding.pop())
        for mt in expanded {
          result.push(pin_to_call_site(mt, tok))
        }
        i = j + 1
      }
    }
  }
  // U1#6：按累计字节计费
  for t in result {
    ctx.emitted += utf8_text_len(t.text) + 1
  }
  result
}

///|
/// 展开产物钉宏调用点（line/column/byte_off/file_id 整体钉点——复刻 Rust
/// `mt.line = tok.line` 行为；file_id 是本侧新增的归属字段，一并钉点保持一致）。
fn pin_to_call_site(mt : @token.Token, tok : @token.Token) -> @token.Token {
  {
    ty: mt.ty,
    text: mt.text,
    loc: tok.loc,
    byte_off: tok.byte_off,
    real_line: tok.real_line,
  }
}

///|
/// 合成 token 钉调用点。
fn @token.Token::pin(self : @token.Token, tok : @token.Token) -> @token.Token {
  {
    ty: self.ty,
    text: self.text,
    loc: tok.loc,
    byte_off: tok.byte_off,
    real_line: tok.real_line,
  }
}

///|
priv struct CapturedArgs {
  args : Array[Array[@token.Token]]
  end_index : Int32
  /// 顶层切分逗号原件（与 args 段一一对应：seps[k] 切出 args[k+1]）——
  /// `#__VA_ARGS__` 字符串化按源码空白拼空格（#164 补），byte_off 须真实
  seps : Array[@token.Token]
}

///|
/// 捕获实参：从 `i+2`（跳过宏名与 `(`）到平衡 `)`；顶层逗号切分。
fn capture_args(tokens : Array[@token.Token], i : Int32) -> CapturedArgs {
  let args : Array[Array[@token.Token]] = []
  let seps : Array[@token.Token] = []
  let mut current : Array[@token.Token] = []
  let mut depth_paren = 1
  let mut j = i + 2
  while j < tokens.length() && depth_paren > 0 {
    match tokens[j].ty {
      LParen => {
        depth_paren += 1
        current.push(tokens[j])
      }
      RParen => {
        depth_paren -= 1
        if depth_paren == 0 {
          break
        }
        current.push(tokens[j])
      }
      Comma =>
        if depth_paren == 1 {
          seps.push(tokens[j])
          args.push(current)
          current = [] // 换新数组（push 的是引用，clear 会连带清空已存实参）
        } else {
          current.push(tokens[j])
        }
      _ => current.push(tokens[j])
    }
    j += 1
  }
  args.push(current)
  { args, end_index: j, seps, }
}

///|
/// 规模保险丝：累计产出字节数超预算即熔断——错误只报一次。
fn budget_hit(ctx : ExpandCtx, tokens : Array[@token.Token]) -> Bool {
  if ctx.emitted <= EXPAND_BYTE_BUDGET {
    return false
  }
  if !ctx.budget_exhausted {
    ctx.budget_exhausted = true
    ctx.errors.push({
      message: "宏展开规模超过预算（累计产出超过 \{EXPAND_BYTE_BUDGET} 字节）。请检查是否存在指数级展开的宏（如 #define REP(x) x x 的深层嵌套，或大字面量被反复复制）",
      loc: {
        line: if tokens.length() > 0 {
          tokens[0].loc.line
        } else {
          0
        },
        column: 0,
        file_id: 0,
      },
      code: E1017_ExpandDepthExceeded,
    })
  }
  true
}

///|
/// 展开链教学追踪（仅最外层调用、非表达式模式记录；容量封顶在 push 处）。
fn record_trace(
  ctx : ExpandCtx,
  name : String,
  args : Array[Array[@token.Token]]?,
  result : Array[@token.Token],
  depth : Int32,
) -> Unit {
  record_trace_ctx(ctx, name, args, result, depth)
}

///|
fn record_trace_ctx(
  ctx : ExpandCtx,
  name : String,
  args : Array[Array[@token.Token]]?,
  result : Array[@token.Token],
  depth : Int32,
) -> Unit {
  if depth != 0 || ctx.expr_mode {
    return
  }
  let args_str : String? = match args {
    Some(a) => {
      let parts : Array[String] = []
      for arg in a {
        parts.push(spelling(arg))
      }
      Some(parts.join(", "))
    }
    None => None
  }
  push_trace(
    ctx.trace,
    Expand(name~, args=args_str, result=spelling(result), depth~),
  )
}

///|
/// 教学追踪封顶推送（展开链 / `#if` 分支原因共用）。
fn push_trace(
  trace : Array[@token.TraceEntry],
  entry : @token.TraceEntry,
) -> Unit {
  if trace.length() < TEACHING_TRACE_CAP {
    trace.push(entry)
  }
}

///|
/// token 序列拼写（单条 2048 字节封顶——按 UTF-8 安全前缀截断，避免劈开
/// 多字节字符；Rust `String::truncate` 在非字符边界会 panic，教学语料以
/// ASCII 为主，边界形状差异登记）。
fn spelling(toks : Array[@token.Token]) -> String {
  let parts : Array[String] = []
  for t in toks {
    parts.push(t.text)
  }
  let s = parts.join(" ")
  if utf8_text_len(s) > TRACE_ENTRY_MAX_CHARS {
    truncate_utf8(s, TRACE_ENTRY_MAX_CHARS) + " …(截断)"
  } else {
    s
  }
}

///|
/// UTF-8 安全前缀截断（≤ limit 字节的最长合法前缀）。
fn truncate_utf8(s : String, limit : Int32) -> String {
  let bytes = @utf8.encode(s)
  if bytes.length() <= limit {
    return s
  }
  let mut end_ = limit
  while end_ > 0 && (bytes[end_].to_int() & 0xC0) == 0x80 {
    end_ -= 1 // 回退到序列首字节
  }
  @utf8.decode(bytes[:end_]) catch {
    _ => ""
  }
}

///|
/// text 的 UTF-8 字节数（Rust `text.len()` 口径——预算计费/列号反推共用）。
fn utf8_text_len(s : String) -> Int32 {
  @util.utf8_len(s)
}

///|
/// W1019：参数在宏体出现 ≥2 次且实参含副作用运算符（文案逐字照搬；
/// 副作用 token 集合照 Rust：Increment/Decrement/Assign/Plus/Minus/Star/Slash/PercentAssign）。
fn warn_side_effects(
  ctx : ExpandCtx,
  macro_name : String,
  mdef : @token.MacroDef,
  args : Array[Array[@token.Token]],
  call : @token.Token,
) -> Unit {
  let params = match mdef {
    Function(params~, ..) => params
    Object(..) => return
  }
  for idx in 0..<params.length() {
    let param = params[idx]
    let occurrences = count_param_occurrences(mdef, param)
    if occurrences < 2 {
      continue
    }
    if idx >= args.length() {
      continue
    }
    let has_side_effect = args[idx]
      .iter()
      .any(t => {
        t.ty is Increment ||
        t.ty is Decrement ||
        t.ty is Assign ||
        t.ty is PlusAssign ||
        t.ty is MinusAssign ||
        t.ty is StarAssign ||
        t.ty is SlashAssign ||
        t.ty is PercentAssign
      })
    if has_side_effect {
      ctx.warnings.push({
        message: "宏 '\{macro_name}' 的参数 '\{param}' 在宏体中出现 \{occurrences} 次，而实参含副作用运算符（++/--/赋值）——展开后该副作用会执行多次，结果可能与预期不符（C 宏经典陷阱）",
        loc: {
          line: call.loc.line,
          column: call.loc.column,
          file_id: call.loc.file_id,
        },
        code: W1019_MacroArgSideEffect,
      })
    }
  }
}

///|
fn count_param_occurrences(mdef : @token.MacroDef, param : String) -> Int32 {
  let body = match mdef {
    Function(body~, ..) => body
    Object(body~) => body
  }
  let mut n = 0
  for bt in body {
    if bt.ty is Identifier && bt.text == param {
      n += 1
    }
  }
  n
}
