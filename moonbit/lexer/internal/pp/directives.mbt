///|
/// 指令消费（行级——勘察 ⑥-7 修复：include 路径在**行内**解析，未闭合不再
/// 把余下全文当路径）。`rest` 为 `#` 之后的整行文本；`line` 为该行仿古主坐标
/// 行号；活跃行的 token 追加进 `out`。
fn[P : @token.SourceProvider] Pp::handle_directive(
  self : Pp[P],
  rest : String,
  line : Int32,
  out : Array[@token.Token],
) -> Unit {
  let rest = leading_trim(rest)
  // 指令名
  let mut n = 0
  while n < rest.length() {
    let c = rest[n].to_int()
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
      n += 1
    } else {
      break
    }
  }
  let directive = rest[0:n].to_owned()
  let after = rest[n:].to_owned()
  // `#if` / `#elif` 需要整行原始文本（__has_include 的路径无法从 token 还原）
  if directive == "if" || directive == "elif" {
    if directive == "if" {
      self.handle_if(after, line)
    } else {
      self.handle_elif(after, line)
    }
    return
  }
  match directive {
    "define" => if !self.is_skipping() { self.parse_define(after, line) }
    "undef" =>
      if !self.is_skipping() {
        // 病 73（2026-10-13）：缺宏名显式诊断（clang "macro name missing"
        // error；旧 read_ident("") 返回空串 → remove("") 静默 no-op）
        let name = read_ident(after)
        if name == "" {
          self.err("#undef 缺少宏名", line, code=E1006_UnsupportedFeature)
        }
        ignore(self.macros.remove(name))
      }
    "ifdef" => {
      let ident = read_ident(after)
      // 病 73（2026-10-13）：缺宏名显式诊断并按未定义处理（块内容跳过
      // ——clang 同形：error 后该组按假分支走；旧 contains("") 恒假
      // 静默吞掉整块代码，零诊断）
      if ident == "" && !self.is_skipping() {
        self.err("#ifdef 缺少宏名", line, code=E1006_UnsupportedFeature)
      }
      let parent_skipping = self.is_skipping()
      let active = if parent_skipping {
        false
      } else {
        self.macros.contains(ident)
      }
      self.cond_stack.push({
        active,
        has_else: false,
        taken: active,
        open_line: line,
      })
    }
    "ifndef" => {
      let ident = read_ident(after)
      // 病 73 同款：缺宏名显式诊断（旧静默按「未定义」取真分支吞代码）
      if ident == "" && !self.is_skipping() {
        self.err("#ifndef 缺少宏名", line, code=E1006_UnsupportedFeature)
      }
      let parent_skipping = self.is_skipping()
      let active = if parent_skipping {
        false
      } else {
        !self.macros.contains(ident)
      }
      self.cond_stack.push({
        active,
        has_else: false,
        taken: active,
        open_line: line,
      })
    }
    "else" => self.handle_else(line)
    "endif" => self.handle_endif(line)
    // C23（修复 ⑥-11：Rust 静默当未知指令跳过 → 选错分支零诊断）
    "elifdef" => self.handle_elifdef(after, line, negated=false)
    "elifndef" => self.handle_elifdef(after, line, negated=true)
    "include" =>
      if !self.is_skipping() {
        self.handle_include(after, line, out)
      }
    // #212（2026-10-21 报 / 2026-10-23 修）：#pragma/#line 整族不再落
    // 未知指令 E1006 硬拒——`#pragma once` 是学生代码/教材高频惯用法
    //（在线题解、模板库广泛使用）；旧文案「已跳过该行」与 err 终止
    // 编译的实际行为矛盾（说谎文案）。处置：once 零诊断跳过（重复
    // 包含防护由 resolver 环检测天然承接）；其余 pragma/#line 降
    // W1023 警告跳过——语义未实现，按默认口径编译（布局/行号与真实
    // 编译器的差异登记《已知限制与差异》），对齐 clang 对未知
    // pragma 的忽略倾向（默认不启 -Wunknown-pragmas）
    "pragma" => if !self.is_skipping() { self.handle_pragma(after, line) }
    "line" =>
      if !self.is_skipping() {
        self.warnings.push({
          message: "#line 指令已忽略（行号映射按原文件行号，未随指令改写）",
          loc: { line, column: 0, file_id: self.current_file_id(), },
          code: W1023_PreprocDirectiveIgnored,
        })
      }
    // 标准指令：显式诊断（修复 ⑥-12：Rust 落未知分支静默跳过、零诊断——
    // 决议记载"已支持"与代码不符；W 级码表暂缺，severity 精确化随码表扩容裁定）
    "error" =>
      if !self.is_skipping() {
        self.err(
          "#error 指令: \{leading_trim(after)}",
          line,
          code=E1006_UnsupportedFeature,
        )
      }
    "warning" =>
      if !self.is_skipping() {
        self.err(
          "#warning 指令: \{leading_trim(after)}",
          line,
          code=E1006_UnsupportedFeature,
        )
      }
    // 空指令 `#`：C 标准 no-op（Rust 落未知分支静默跳过——行为等价）
    "" => ()
    // 未知指令：显式诊断（修复 ⑥-11——Rust `_ =>` 静默跳行使 `#elifdef` 类
    // 拼写错误静默选错分支；教学引擎对"静默选错分支"零容忍）
    _ =>
      if !self.is_skipping() {
        self.err(
          "无法识别的预处理指令 '#\{directive}'（已跳过该行）",
          line,
          code=E1006_UnsupportedFeature,
        )
      }
  }
}

///|
/// `#pragma` 处置（#212，2026-10-23）：`once` 零诊断跳过——重复包含
/// 防护由宿主 include-once 能力旗标承接（`include_once_implicit`——
/// 同文件重复 include 隐式去重，diff_ledger 17 键在册；非环检测通道
/// ——PR #284 审阅 P3 勘误：`include_cycle_detect` 是另一条独立旗标）；
/// 其余 pragma（pack/STDC/Pack 等）降 W1023 警告跳过——语义未实现按
/// 默认口径编译，不再 E1006 硬拒。
/// PR #284 审阅 P1-1（2026-10-24）：once 匹配前 `trailing_trim` 剥
/// 尾随空白（\r/空格/制表）——CRLF 检出态（行尾 `\r` 系
/// split_physical_lines 刻意保留、靠 scanner 消化）、注释剥除残留
/// 空格、编辑器尾随空格三形态与 LF 裸行统一判零诊断（旧精确比较
/// 只认 1/4 形态，自家语料在本机 CRLF 检出态即中招报 W1023 'once\r'）。
fn[P] Pp::handle_pragma(self : Pp[P], after : String, line : Int32) -> Unit {
  let arg = trailing_trim(leading_trim(after))
  if arg == "once" {
    return
  }
  // 参数截断显示（教学源码 pragma 参数均短；防病态长串撑爆文案）
  let shown = if arg.length() > 32 { "\{arg[0:32]}…" } else { arg }
  self.warnings.push({
    message: "#pragma 已忽略（'\{shown}' 的语义未实现——布局/对齐类 pragma 与真实编译器可能存在差异，程序按默认口径编译）",
    loc: { line, column: 0, file_id: self.current_file_id(), },
    code: W1023_PreprocDirectiveIgnored,
  })
}

///|
/// 行内读标识符（跳过前导空白后取 [A-Za-z0-9_]+）。
fn read_ident(s : String) -> String {
  let s = leading_trim(s)
  let mut n = 0
  while n < s.length() {
    let c = s[n].to_int()
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' {
      n += 1
    } else {
      break
    }
  }
  s[0:n].to_owned()
}

///|
// ---------- 条件组 ----------

fn[P : @token.SourceProvider] Pp::handle_if(
  self : Pp[P],
  raw : String,
  line : Int32,
) -> Unit {
  let parent_skipping = self.is_skipping()
  let state : CondState = if parent_skipping {
    // 外层已跳过：不求值（短路语义），组内永不激活
    { active: false, has_else: false, taken: true, open_line: line, }
  } else {
    let outcome = self.evaluate_cond(raw, line)
    { active: outcome, has_else: false, taken: outcome, open_line: line, }
  }
  self.cond_stack.push(state)
}

///|
fn[P : @token.SourceProvider] Pp::handle_elif(
  self : Pp[P],
  raw : String,
  line : Int32,
) -> Unit {
  let parent_skipping = self.parent_skipping()
  let n = self.cond_stack.length()
  if n == 0 {
    self.err(
      "没有匹配的 #if/#ifdef/#ifndef 就出现 #elif",
      line,
      code=E1011_UnmatchedConditional,
    )
    return
  }
  if self.cond_stack[n - 1].has_else {
    self.err("#elif 出现在 #else 之后", line, code=E1012_DuplicateElse)
    return
  }
  if parent_skipping || self.cond_stack[n - 1].taken {
    self.cond_stack[n - 1].active = false
    return
  }
  let outcome = self.evaluate_cond(raw, line)
  self.cond_stack[n - 1].active = outcome
  self.cond_stack[n - 1].taken = outcome
}

///|
/// `#elifdef` / `#elifndef`（C23；clang 22 支持——语义 = defined 判定版 #elif）。
fn[P] Pp::handle_elifdef(
  self : Pp[P],
  after : String,
  line : Int32,
  negated~ : Bool,
) -> Unit {
  let parent_skipping = self.parent_skipping()
  let n = self.cond_stack.length()
  if n == 0 {
    self.err(
      "没有匹配的 #if/#ifdef/#ifndef 就出现 #elifndef/#elifdef",
      line,
      code=E1011_UnmatchedConditional,
    )
    return
  }
  if self.cond_stack[n - 1].has_else {
    self.err("#elifdef 出现在 #else 之后", line, code=E1012_DuplicateElse)
    return
  }
  if parent_skipping || self.cond_stack[n - 1].taken {
    self.cond_stack[n - 1].active = false
    return
  }
  let ident = read_ident(after)
  let mut active = self.macros.contains(ident)
  if negated {
    active = !active
  }
  // trace 不记（#if/#elif 之外的新指令形状——Rust wire format 未覆盖，
  // 保持 trace 输出与 Rust 逐字节一致）
  self.cond_stack[n - 1].active = active
  self.cond_stack[n - 1].taken = active
}

///|
fn[P] Pp::handle_else(self : Pp[P], line : Int32) -> Unit {
  let parent_skipping = self.parent_skipping()
  let n = self.cond_stack.length()
  if n == 0 {
    self.err(
      "没有匹配的 #if/#ifdef/#ifndef 就出现 #else",
      line,
      code=E1011_UnmatchedConditional,
    )
    return
  }
  if self.cond_stack[n - 1].has_else {
    self.err("重复的 #else", line, code=E1012_DuplicateElse)
    return
  }
  self.cond_stack[n - 1].has_else = true
  // 父级跳过态下保持不激活（显式化以便后续 #elif 正确）
  self.cond_stack[n - 1].active = !self.cond_stack[n - 1].taken &&
    !parent_skipping
}

///|
fn[P] Pp::handle_endif(self : Pp[P], line : Int32) -> Unit {
  // U1#11：include 边界记账——头文件内多余的 #endif 不得弹掉包含者的条件组
  if self.include_stack.length() > 0 {
    let boundary = self.include_stack[self.include_stack.length() - 1].cond_boundary
    if self.cond_stack.length() <= boundary {
      self.err(
        "头文件中的 #endif 没有匹配的 #if/#ifdef/#ifndef（将弹掉包含文件的条件编译组，已忽略该 #endif）",
        line,
        code=E1011_UnmatchedConditional,
      )
      return
    }
  }
  if self.cond_stack.length() == 0 {
    self.err(
      "没有匹配的 #if/#ifdef/#ifndef 就出现 #endif",
      line,
      code=E1011_UnmatchedConditional,
    )
    return
  }
  ignore(self.cond_stack.pop())
}

///|
// ---------- include ----------

///|
/// 解析 include 路径与定界形式：`(路径, 是否 <> 形式)`。
/// 行内解析（修复 ⑥-7：扫描不到定界符即止，不吞后续行）。
fn parse_include_path(after : String) -> (String, Bool)? {
  let s = leading_trim(after)
  if s.length() == 0 {
    return None
  }
  let delimiter = s[0].to_int()
  if delimiter != '<' && delimiter != '"' {
    return None
  }
  let end_char : Int32 = if delimiter == '<' { '>' } else { '"' }
  let mut i = 1
  while i < s.length() {
    if s[i].to_int() == end_char {
      return Some((s[1:i].to_owned(), delimiter == '<'))
    }
    i += 1
  }
  // 未闭合：路径截到行尾（不再消费余下全文——Rust E1021 消息内嵌多行源码）
  Some((s[1:].to_owned(), delimiter == '<'))
}

///|
fn[P : @token.SourceProvider] Pp::handle_include(
  self : Pp[P],
  after : String,
  line : Int32,
  out : Array[@token.Token],
) -> Unit {
  let path_info = parse_include_path(after)
  if path_info is None {
    return
  }
  let (path, is_angle) = path_info.unwrap()
  // 动态嵌套深度保险丝（U1#11；文案照搬）
  if self.include_stack.length() >= MAX_INCLUDE_DEPTH {
    self.err(
      "#include 嵌套过深（上限 \{MAX_INCLUDE_DEPTH} 层，已跳过 '\{path}'）",
      line,
      code=E1015_IncludeCycle,
    )
    return
  }
  let is_stub = @host.stub_lookup(path) is Some(_)
  // 病 74（2026-10-13）：quote 形态本地目录优先（C11 §6.10.2p3/clang——
  // 「include "stddef.h"」本地有同名头时不得被存根遮蔽；旧存根优先致
  // 本地头静默失效）。angle 维持 H-3 存根-only 不搜文件系统。
  let local_resolved : String? = if is_angle {
    None
  } else {
    self.resolve_path(path)
  }
  let use_stub = is_stub && !(local_resolved is Some(_))
  // H-3（U1#11 收紧）：`<>` 只匹配标准库存根，不搜索文件系统（与 Clang 对齐；
  // 存量 655 处 `<>` include 全为标准头名，零存量依赖）
  if is_angle && !is_stub {
    self.err(
      "<> 形式只匹配标准库头文件（未收录 '\{path}'）；自定义头文件请使用 #include \"\{path}\"",
      line,
      code=E1021_IncludeNotFound,
    )
    return
  }
  // include-once / 环检测（病 74：use_stub=quote 本地 miss 后才落存根）
  let resolved : String? = if use_stub {
    None
  } else {
    match local_resolved {
      Some(r) => Some(r)
      None => self.resolve_path(path) // angle 已早退；此处仅 quote 非 stub 路径
    }
  }
  let key = if use_stub {
    "stub:\{path}"
  } else {
    match resolved {
      Some(r) => r
      None => {
        // H-1（U1#11）：找不到头文件必须定位报错（E1021，include 行）
        self.err(
          "找不到头文件 '\{path}'（已搜索：当前文件目录、源文件目录；标准库存根未收录该名字）",
          line,
          code=E1021_IncludeNotFound,
        )
        return
      }
    }
  }
  if self.processed.contains(key) {
    return // include-once：静默跳过（守卫语义内置）
  }
  if !use_stub {
    match self.detect_cycle(key) {
      Some(cycle) => {
        self.err(
          "检测到 #include 依赖环：\{cycle}（已跳过该 include）",
          line,
          code=E1015_IncludeCycle,
        )
        return
      }
      None => ()
    }
  }
  self.processed.add(key)
  // 内容读取（存根 or provider；缓存单源）
  let content : String = if use_stub {
    @host.stub_lookup(path).unwrap()
  } else {
    match self.read_cached(key) {
      Some(c) => c
      None => {
        self.err(
          "找不到头文件 '\{path}'（已搜索：当前文件目录、源文件目录；标准库存根未收录该名字）",
          line,
          code=E1021_IncludeNotFound,
        )
        return
      }
    }
  }
  // file_id 分配（同路径同 id——诊断归属单源）
  let file_id = match self.file_ids.get(key) {
    Some(id) => id
    None => {
      let id = self.next_file_id
      self.next_file_id += 1
      self.file_ids[key] = id
      self.file_names[id] = display_name_of(key)
      id
    }
  }
  // 仿古行号基准（逐字节复刻 Rust splice 补偿后的主坐标系行号；负行号是
  // ③-3 行号补偿缺陷的忠实复刻，L2 对拍口径故意保留——真实归属由
  // file_id + LineMap 携带）：
  // - 存根：Rust 不做哨兵包装，直接 splice——line = L + 1 - N，
  //   内容第 k 行 token line = L + 1 - N + (k-1)；
  // - 自定义头：Rust 以哨兵指令包裹（inserted = N + 3）——line = L - N - 2，
  //   内容第 k 行 token line = L - N - 2 + k（哨兵行不产 token）。
  //（N = 内容换行数）
  let content_newlines = count_char(content, '\n')
  let line_base = if is_stub {
    line - content_newlines + 1
  } else {
    line - content_newlines - 2 + 1
  }
  let span_first = line_base
  // include 栈（quote 相对解析的"包含者目录" + 条件栈边界）
  let frame_dir = if is_stub { "" } else { dirname_of(key) }
  self.include_stack.push({
    dir: frame_dir,
    cond_boundary: self.cond_stack.length(),
    file_id,
  })
  let content_tokens = self.run_pp(
    content,
    main_line_base=line_base,
    main_byte_base=0,
    main_file_id=file_id,
    span_main_first=Some(span_first),
    span_file_line=1,
  )
  // U1#11：头文件末尾条件组闭合校验（pop_include_frame 内，文案照搬）
  ignore(self.pop_include_frame())
  for t in content_tokens {
    out.push(t)
  }
}

///|
/// 弹出 include 帧并校验条件栈边界（U1#11 文案照搬）。
/// 返回弹出的帧（供调用方读 dir）。
fn[P] Pp::pop_include_frame(self : Pp[P]) -> IncludeFrame? {
  if self.include_stack.length() == 0 {
    return None
  }
  let frame = self.include_stack.pop().unwrap()
  if self.cond_stack.length() > frame.cond_boundary {
    let hint = if self.cond_stack.length() > 0 {
      self.cond_stack[self.cond_stack.length() - 1].open_line
    } else {
      0
    }
    self.err(
      "头文件内未闭合的 #if/#ifdef/#ifndef（已在头文件末尾自动闭合，请检查头文件的条件编译配对）",
      hint,
      code=E1013_UnclosedConditional,
    )
    while self.cond_stack.length() > frame.cond_boundary {
      ignore(self.cond_stack.pop())
    }
  }
  Some(frame)
}

///|
// ---------- define ----------

fn[P] Pp::parse_define(self : Pp[P], after : String, line : Int32) -> Unit {
  let after = leading_trim(after)
  if after.length() == 0 {
    self.err("#define 后预期宏名称", line, code=E1005_InvalidDefine)
    return
  }
  let c0 = after[0].to_int()
  if !((c0 >= 'a' && c0 <= 'z') || (c0 >= 'A' && c0 <= 'Z') || c0 == '_') {
    self.err("#define 后预期宏名称", line, code=E1005_InvalidDefine)
    return
  }
  let name = read_ident(after)
  let rest = after[name.length():].to_owned()
  // 参数列表：宏名后**紧跟** '('（中间无空白——C 标准）
  let params : Array[String] = []
  let mut variadic = false
  let mut body_text = rest
  if rest.length() > 0 && rest[0].to_int() == '(' {
    let mut i = 1
    let mut ok = false
    for ;; {
      // skip 空白
      while i < rest.length() && (rest[i] == ' ' || rest[i] == '\t') {
        i += 1
      }
      if i < rest.length() && rest[i].to_int() == ')' {
        i += 1
        ok = true
        break
      }
      // #164（2026-10-21，C99 §6.10.3）：`...` 变参形参位——必须是最后一个
      // 形参（后随仅许 `)`）；`__VA_ARGS__` 为隐式附加名由 expander 绑定
      if i + 2 < rest.length() &&
        rest[i] == '.' &&
        rest[i + 1] == '.' &&
        rest[i + 2] == '.' {
        i += 3
        while i < rest.length() && (rest[i] == ' ' || rest[i] == '	') {
          i += 1
        }
        if i < rest.length() && rest[i].to_int() == ')' {
          i += 1
          variadic = true
          ok = true
          break
        }
        self.err(
          "`...` 必须是宏的最后一个参数（C99 变参宏）",
          line,
          code=E1005_InvalidDefine,
        )
        return
      }
      if i >= rest.length() || !is_ident_start(rest[i].to_int()) {
        self.err("宏参数必须是标识符", line, code=E1005_InvalidDefine)
        return
      }
      let pstart = i
      while i < rest.length() && is_ident_char(rest[i].to_int()) {
        i += 1
      }
      params.push(rest[pstart:i].to_owned())
      // skip 空白
      while i < rest.length() && (rest[i] == ' ' || rest[i] == '\t') {
        i += 1
      }
      if i < rest.length() && rest[i].to_int() == ',' {
        i += 1
      } else if i < rest.length() && rest[i].to_int() == ')' {
        i += 1
        ok = true
        break
      } else {
        self.err("宏参数列表格式错误", line, code=E1005_InvalidDefine)
        return
      }
    }
    if !ok {
      return
    }
    body_text = rest[i:].to_owned()
  }
  // 宏名与 body 之间的空白（不吞下一行）
  let body_text = leading_trim(body_text)
  // 宏体以 macro_body 模式词法化（`#`/`##` 是操作符）；子扫描错误**丢弃**
  //（复刻 Rust `let (body_tokens, _) = body_lexer.tokenize()` 的静默口径）
  let scratch : Array[@token.LexError] = []
  let body = @scanner.scan_fragment(
    body_text,
    base_byte_off=0,
    base_line=line,
    base_column=1,
    file_id=self.current_file_id(),
    cpp_mode=self.cpp_mode,
    body_mode=true,
    errors=scratch,
  )
  // 宏名后紧跟 `(` = 函数式（含零参数 `FOO()`——修复 ⑥-9：Rust `params.is_empty()`
  // 无法区分两者，`#define FOO() 42` 被误当对象宏，调用报 E3066 错位到 typeck）
  let def : @token.MacroDef = if rest.length() > 0 && rest[0].to_int() == '(' {
    Function(params~, body~, variadic~)
  } else {
    Object(body~)
  }
  self.define_macro(name, def, line)
}

///|
fn is_ident_start(c : Int32) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_ident_char(c : Int32) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
fn count_char(s : String, target : Char) -> Int32 {
  let mut n = 0
  for c in s {
    if c == target {
      n += 1
    }
  }
  n
}

///|
/// 路径的目录部分（最后一个 '/' 之前；无 '/' 返回 ""——同目录相对语义）。
fn dirname_of(path : String) -> String {
  let mut last : Int32? = None
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '/' {
      last = Some(i)
    }
  }
  match last {
    Some(i) => path[0:i].to_owned()
    None => ""
  }
}
