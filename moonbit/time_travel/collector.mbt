///| L9 time_travel·**StepCollector**（S8 批一号三段-b，2026-10-01）——
/// StepPayload 十四字段的采集器 + `infer_semantic_label` 全库唯一语义
/// 分类器。照搬 native/src/unified/collector.rs（478 行）。
///
/// **依赖反转落地**（§4 L9 行硬约束：不依赖 session）：
/// - 源码行：`SourceLineProvider` trait（session 的 source_line_at 由
///   编排层〔gateway/serve〕实现注入——多文件全局行号语义由实现方携带）；
/// - 热力图计数：`heatmap_count` 传值（编排层从会话运行态取）；
/// - freed 堆判定：走 `vm.mem_map`（MoonBit 侧内存本就在 vm 上——比
///   Rust 侧少一处 session.memory 依赖）；
/// - **algorithm_step 已接线**（2026-10-01 批四号）：teaching/steps 的
///   `infer_algorithm_step` + U1#1 管道三状态（row_entry_vars/last_line/
///   last_frame_vars）——Rust 侧在 session 上（collector 拿 &Session），
///   本侧 session import time_travel 成环，状态内聚 `AlgoInferCtx`
///   （编排层直供 matches，moon.pkg 头注「AlgorithmContext 不迁——编排层
///   直供」先例的落地形态）。

///|
/// 算法步骤推断上下文（Rust session.unified_{row_entry_vars,last_line,
/// last_frame_vars} 三字段 + algorithm_matches 的引擎侧内聚；批四号接线
/// 裁定——跨 seek 不回滚，与 Rust session 字段「重放连续演化」同语义）。
pub struct AlgoInferCtx {
  /// 编译期检测产物（编排层 compile 时注入；空 = 全部帧无标注降级）。
  mut matches : Array[@protocol.AlgorithmMatch]
  /// 行入口变量快照（U1#1 P0-4——「展示运算过程」的 phase 用它拼算式：
  /// 行末帧的 b 已被本语句赋值）。
  mut row_entry_vars : Array[@steps.VarSnapshot]
  /// 上一帧行号（行变化检测）。
  mut last_line : Int
  /// 上一帧变量快照（行末固化，供下一行的 row_entry_vars）。
  mut last_frame_vars : Array[@steps.VarSnapshot]
}

///|
pub fn AlgoInferCtx::new() -> AlgoInferCtx {
  { matches: [], row_entry_vars: [], last_line: 0, last_frame_vars: [], }
}

///|
/// 按 func_name 查匹配（Rust session find_algorithm——首中，大小写敏感）。
fn find_algo_match(
  algo : AlgoInferCtx,
  func_name : String,
) -> @protocol.AlgorithmMatch? {
  for m in algo.matches {
    if m.func_name == func_name {
      return Some(m)
    }
  }
  None
}
///
/// **判定顺序契约**（Rust collector.rs:405-412 修订注释照搬）：具体语句
/// 模式优先于循环上下文——旧序把 loop_depth 置前导致循环后的
/// printf/free/return 全被标"循环 i=3"（词汇表条目形同虚设的实测缺陷）；
/// 现序：循环行首（降级形态）→ 交换 → 递归 → printf/scanf → return →
/// 内存分配/释放 → IO → qsort → 普通调用 → 循环上下文 → 行号兜底。

///|
/// 源码行供给者（依赖反转——L9 不依赖 session，编排层实现注入；
/// 行号 = 多文件全局行号〔P0-4 口径，映射由实现方携带〕）。
pub(open) trait SourceLineProvider {
  /// 行号取源码行文本；越界/无映射返回 None。
  fn source_line_at(Self, line : Int) -> String?
}

///|
/// 采集一帧（Rust StepCollector::collect 照搬；纯函数形态——状态在调用
/// 方 engine/编排层，本侧无采集器状态故不设 struct 壳；算法推断三状态
/// 经 AlgoInferCtx 由调用方持入）。
pub fn[P : SourceLineProvider] collect(
  vm : @vm.VitroVM,
  src : P,
  heatmap_count : UInt64,
  step_index : Int,
  algo : AlgoInferCtx,
  code_line? : Int? = None,
) -> @protocol.StepPayload {
  // issue #34 销案（2026-10-06）：code_line 与语义 label 同源（engine
  // 循环顶的步进前行）——旧 vm.get_current_line()（步进后）与 label
  //（步进前）同帧错位一步（帧报 N 语义在 N+1）；None 时自取（旧调用
  // 兼容——语义为「最近 StepEvent 行」）
  let code_line = match code_line {
    Some(l) => l
    None => vm.get_current_line()
  }
  let cs_len = vm.call_stack_len()
  let func_name : String = if cs_len > 0 {
    vm.call_stack_at(cs_len - 1).func_name
  } else {
    ""
  }
  // 数组元素快照（条形图 + local_vars 摘要共用一次采集）
  let vm_arrays = vm.get_array_snapshots()
  let array_snapshots : Array[@protocol.ArraySnapshot] = []
  // 数组"值"摘要：{e1, e2, …}（16 上限 + 省略号——P2-7b：数组条目
  // 显示首元素会被误读成"数组的值"）
  let array_summaries : Map[String, String] = Map([])
  for a in vm_arrays {
    let max_shown = 16
    let buf = StringBuilder()
    buf.write_string("{")
    let mut k = 0
    let mut first = true
    while k < a.elements.length() && k < max_shown {
      if !first {
        buf.write_string(", ")
      }
      buf.write_string(a.elements[k])
      first = false
      k = k + 1
    }
    if a.elements.length() > max_shown {
      buf.write_string(", …")
    }
    buf.write_string("}")
    array_summaries.set(a.name, buf.to_string())
    array_snapshots.push({
      name: a.name,
      element_ty: a.element_ty,
      elements: a.elements,
      truncated: a.truncated,
    })
  }
  // local_vars（ty 显示名走 ast 单源；数组条目用元素摘要）
  let local_vars : Array[@protocol.ApiVariableSnapshot] = []
  for v in vm.get_variable_snapshot() {
    let ty_name = @ast.type_display_name(v.ty)
    let value_str = if v.ty.kind() is TK_Array {
      match array_summaries.get(v.name) {
        Some(s) => s
        None => format_value(v.ty, v.value)
      }
    } else {
      format_value(v.ty, v.value)
    }
    local_vars.push({
      name: v.name,
      addr: v.addr,
      is_local: v.is_local,
      ty_name,
      value: value_str,
    })
  }
  // 调用栈（return_line=0 MVP 简化照搬）
  let call_stack : Array[@protocol.ApiFrameInfo] = []
  let mut fi = 0
  while fi < cs_len {
    let f = vm.call_stack_at(fi)
    call_stack.push({ func_name: f.func_name, return_line: 0, })
    fi = fi + 1
  }
  // 可视化事件（取出即清）
  let vis_events : Array[@protocol.VisEvent] = []
  for e in vm.take_vis_events() {
    vis_events.push({
      ty: e.ty,
      line: e.line,
      extra0: e.extra0,
      extra1: e.extra1,
      extra2: e.extra2,
      context: e.context,
    })
  }
  let heatmap_line = code_line
  // callee 入口判定（S3 观测 #3：进入被调函数首步的行归因于调用点行）
  let at_callee_entry = if cs_len > 0 {
    vm.call_stack_at(cs_len - 1).caller_line == code_line
  } else {
    false
  }
  let source_line = match src.source_line_at(code_line) {
    Some(l) => l.trim().to_owned()
    None => ""
  }
  let semantic_label = infer_semantic_label(
    code_line,
    Some(local_vars),
    func_name,
    source_line,
    at_callee_entry,
  )
  // 算法步骤推断（Rust collector.rs:83-118 照搬）：行入口快照维护（行变
  // 化时把上一行末帧固化）→ 变量映射（name/value 两字段）→ env 三类帧
  // 上下文 → 推断；last_frame_vars 无条件固化（find 失败也维护——Rust
  // 同形）。
  if code_line != algo.last_line {
    algo.row_entry_vars = algo.last_frame_vars.copy()
    algo.last_line = code_line
  }
  let algo_vars : Array[@steps.VarSnapshot] = []
  for v in local_vars {
    algo_vars.push({ name: v.name, value: v.value, })
  }
  let algorithm_step : @protocol.AlgorithmStepSnapshot? = match
    find_algo_match(algo, func_name) {
    None => None
    Some(am) => {
      // caller_is_main：栈深 ≥2 且倒数第二层是 main（Rust
      // eq_ignore_ascii_case——ASCII 域 to_lower 等价）
      let caller_is_main = cs_len >= 2 &&
        vm.call_stack_at(cs_len - 2).func_name.to_lower() == "main"
      // lookahead：下 3 行源码（trim——Rust ctx.source_line 口径；多行
      // for 的体不在 for 行内，+1 行不够——U1#1 P1-1）
      let lab = StringBuilder()
      for dl = 1; dl <= 3; dl = dl + 1 {
        match src.source_line_at(code_line + dl) {
          Some(l) => {
            lab.write_string(l.trim().to_owned())
            lab.write_char('\n')
          }
          None => ()
        }
      }
      let env : @steps.InferEnv = {
        prev_vars: algo.row_entry_vars,
        at_callee_entry,
        caller_is_main,
        lookahead: lab.to_string(),
      }
      let step = @steps.infer_algorithm_step(
        code_line,
        algo_vars,
        func_name,
        source_line,
        Some(am),
        env,
      )
      step
    }
  }
  algo.last_frame_vars = algo_vars
  // 最近访问变量（Read/Write 文本形态——保持 Rust String 形态不造枚举）
  let accessed_vars : Array[@protocol.AccessedVar] = []
  let mut ai = 0
  while ai < vm.accessed_len() {
    let a = vm.accessed_at(ai)
    accessed_vars.push({
      name: a.name,
      access_type: match a.access_type {
        Read => "Read"
        Write => "Write"
      },
    })
    ai = ai + 1
  }
  let pointer_snapshots = collect_pointer_snapshots(vm, local_vars)
  {
    step_index,
    code_line,
    func_name,
    semantic_label,
    algorithm_step,
    local_vars,
    call_stack,
    vis_events,
    heatmap_line,
    heatmap_count,
    accessed_vars,
    array_snapshots,
    pointer_snapshots,
    root_cause_hint: None, // trap 帧由 run_batch 回填（M14 已接线 2026-10-03，六分析器）
  }
}

///|
/// 指针四态快照（Rust collect_pointer_snapshots 照搬）：Null（addr=0）/
/// Dangling（NULL 区与 MEM_SIZE 之外）/ Freed（freed 堆命中）/ Valid；
/// target_name 两级（当前帧优先 → vm 跨帧解析——`swap(&x,&y)` 体内取
/// 调用者名字的场景，D3）。
fn collect_pointer_snapshots(
  vm : @vm.VitroVM,
  local_vars : Array[@protocol.ApiVariableSnapshot],
) -> Array[@protocol.PointerSnapshot] {
  let result : Array[@protocol.PointerSnapshot] = []
  for v in local_vars {
    if !is_pointer_type(v.ty_name) {
      continue
    }
    let target_addr = match parse_addr(v.value) {
      Some(a) => a
      None => continue
    }
    let status : @protocol.PointerStatus = if target_addr == 0U {
      Null
    } else if target_addr < @bytecode.NULL_TRAP_SIZE ||
      target_addr >= @bytecode.MEM_SIZE {
      Dangling
    } else if is_freed_heap(vm, target_addr) {
      Freed
    } else {
      Valid
    }
    let target_name = {
      let same_frame = find_var_name_in_frame(local_vars, target_addr)
      if same_frame == "" {
        match vm.find_variable_name_at_addr(target_addr) {
          Some(n) => n
          None => ""
        }
      } else {
        same_frame
      }
    }
    result.push({
      name: v.name,
      addr: v.addr,
      ty_name: v.ty_name,
      target_addr,
      target_name,
      status,
    })
  }
  result
}

///|
/// freed 堆命中（Rust is_freed_heap 等价——region(addr) 按址键查，
/// Rust 的 `r.addr == addr` 条件内含于键查询）。
fn is_freed_heap(vm : @vm.VitroVM, addr : UInt) -> Bool {
  match vm.mem_map.region(addr) {
    Some(r) => r.is_heap && r.is_freed
    None => false
  }
}

///|
fn find_var_name_in_frame(
  local_vars : Array[@protocol.ApiVariableSnapshot],
  addr : UInt,
) -> String {
  for v in local_vars {
    if v.addr == addr {
      return v.name
    }
  }
  ""
}

///|
/// 变量值文本化（Rust format_value 照搬）：Double/Float 按位还原后定点
/// 15/7 位并剪尾零（`1.500` → `1.5`、`2.0` → `2`）；其余整值直出。
fn format_value(ty : @ast.Type, value : Int64) -> String {
  match ty.kind() {
    TK_Double => {
      let f = value.reinterpret_as_uint64().reinterpret_as_double()
      trim_trailing_zeros(@host.format_fixed(f, 15))
    }
    TK_Float => {
      let bits = value.reinterpret_as_uint64() & 0xFFFFFFFFUL
      let f = Float::reinterpret_from_uint(bits.to_uint())
      trim_trailing_zeros(@host.format_fixed(f.to_double(), 7))
    }
    _ => "\{value}"
  }
}

///|
/// 剪尾零与尾小数点（Rust trim_end_matches('0').trim_end_matches('.')
/// 等价——"1.500"→"1.5"、"2.0"→"2"、"3.000"→"3"；无小数点不动
/// （防 "20" 被剪成 "2" 的形态——Rust 同序先剪 0 再剪 '.'，纯整数串
/// 无 '.' 时 trim 零不发生，此处以"见到 '.' 才剪"等价实现）。
fn trim_trailing_zeros(s : String) -> String {
  if !s.contains(".") {
    return s
  }
  let cs = s.to_array()
  let mut end = cs.length()
  while end > 0 && cs[end - 1] == '0' {
    end = end - 1
  }
  if end > 0 && cs[end - 1] == '.' {
    end = end - 1
  }
  let out = StringBuilder()
  let mut i = 0
  while i < end {
    out.write_char(cs[i])
    i = i + 1
  }
  out.to_string()
}

///|
fn is_pointer_type(ty_name : String) -> Bool {
  ty_name.contains("*") || ty_name.contains("Pointer")
}

///|
/// 地址解析（Rust parse_addr：0x 前缀十六进制 / 十进制非负）。
///
/// **形态分叉登记（2026-10-01 审阅 P3，域内不可达不修）**：Rust 侧
/// `u32::from_str_radix` / `i64::parse` 拒绝 `+` 前缀与溢出；本实现
/// 十六进制分支溢出 wrap（`n * 16U + d` 无检）。入参源 = 引擎文本化的
/// 地址（≤1MB，probe 实测域内两种形态均不可达）——若未来入参来源变为
/// 非引擎文本化（如宿主直传用户串），须复刻拒溢出语义。
fn parse_addr(value : String) -> UInt? {
  if value.length() > 2 && (value.has_prefix("0x") || value.has_prefix("0X")) {
    let hex = value[2:].to_owned()
    let mut n : UInt = 0U
    for c in hex {
      let d = match c {
        '0' => 0
        '1' => 1
        '2' => 2
        '3' => 3
        '4' => 4
        '5' => 5
        '6' => 6
        '7' => 7
        '8' => 8
        '9' => 9
        'a' | 'A' => 10
        'b' | 'B' => 11
        'c' | 'C' => 12
        'd' | 'D' => 13
        'e' | 'E' => 14
        'f' | 'F' => 15
        _ => return None
      }
      n = n * 16U + d.reinterpret_as_uint()
    }
    return Some(n)
  }
  // 十进制（负值 None）
  let mut n : UInt = 0U
  if value.length() == 0 {
    return None
  }
  for c in value {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10U + (c.to_int() - '0'.to_int()).reinterpret_as_uint()
  }
  Some(n)
}

///|
/// 推断语义标签——**全库唯一分类器**（Rust infer_semantic_label 照搬；
/// 纯函数化：源码行由调用方取好传入，判据链零会话依赖）。
///
/// local_vars：Some = 全量形态（值敏感分支可用）；None = 降级形态
/// （检查点保存路径——同词汇表同判定顺序，值敏感分支退化为行首形态）。
pub fn infer_semantic_label(
  code_line : Int,
  local_vars : Array[@protocol.ApiVariableSnapshot]?,
  func_name : String,
  source_line : String,
  at_callee_entry : Bool,
) -> String {
  if code_line <= 0 {
    return ""
  }
  // trim 在本函数内（照搬 Rust collector.rs:341 的 .trim() 位——collect
  // 层的 trim 是幂等的第二道；判定链 starts_with 全部作用于去缩进行）
  let source_line = source_line.trim().to_owned()
  // 循环变量白名单（i/j/k/idx/index/m/n/left/right/mid/low/high/pivot/gap）
  let loop_vars : Array[(String, Int)] = []
  match local_vars {
    Some(vars) =>
      for v in vars {
        if is_loop_var_name(v.name) {
          match parse_i32(v.value) {
            Some(val) => loop_vars.push((v.name, val))
            None => ()
          }
        }
      }
    None => ()
  }
  let loop_depth = loop_vars.length()
  // 降级形态：循环行首直接判"循环"（同词汇表）
  let is_loop_headline = local_vars is None &&
    (source_line.has_prefix("for ") || source_line.has_prefix("while "))
  // 交换模式：temp + arr[/a[ + 赋值
  let is_swap = source_line.contains("temp") &&
    (source_line.contains("arr[") || source_line.contains("a[")) &&
    source_line.contains("=")
  // 递归调用（排除 callee 入口首步〔S3 观测 #3：行归因调用点〕与定义行）
  let is_recursive = !at_callee_entry &&
    func_name != "" &&
    func_name != "main" &&
    source_line.contains("\{func_name}(") &&
    !is_function_definition_line(source_line, func_name)
  // 普通调用（排除控制流关键字/注释行首）
  let is_func_call = source_line.contains("(") &&
    !source_line.has_prefix("if ") &&
    !source_line.has_prefix("while ") &&
    !source_line.has_prefix("for ") &&
    !source_line.has_prefix("switch ") &&
    !source_line.has_prefix("return ") &&
    !source_line.has_prefix("//") &&
    !source_line.has_prefix("/*")
  // ── 判定顺序（顺序敏感——具体模式优先于循环上下文，模块头注契约）──
  if is_loop_headline {
    return "循环"
  }
  if is_swap && loop_depth >= 1 {
    // P0-3：下标从源码行取（first() 会取到 n 这类规模量——曾致
    // label 与 algorithm_step 同时一对一错）
    let idx_val = pick_inner_index(loop_vars, source_line)
    return "交换 arr[\{idx_val}]↔arr[\{idx_val + 1}]"
  }
  if is_recursive {
    return "递归调用 \{func_name}"
  }
  if source_line.has_prefix("printf") || source_line.has_prefix("scanf") {
    let func = if source_line.has_prefix("printf") { "printf" } else { "scanf" }
    return "调用 \{func}"
  }
  if source_line.has_prefix("return") {
    return "返回"
  }
  if source_line.contains("malloc") || source_line.contains("calloc") {
    return "内存分配"
  }
  if source_line.contains("free(") {
    return "释放内存"
  }
  if source_line.contains("getchar") || source_line.contains("putchar") {
    return "IO 操作"
  }
  if source_line.contains("qsort(") {
    return "调用 qsort"
  }
  if is_func_call {
    match extract_called_func(source_line) {
      Some(func) => return "调用 \{func}"
      None => return "函数调用"
    }
  }
  if loop_depth >= 1 {
    let buf = StringBuilder()
    let mut first = true
    for pair in loop_vars {
      if !first {
        buf.write_string(", ")
      }
      buf.write_string("\{pair.0}=\{pair.1}")
      first = false
    }
    return "循环 \{buf.to_string()}"
  }
  "第 \{code_line} 行"
}

///|
fn is_loop_var_name(name : String) -> Bool {
  match name {
    "i"
    | "j"
    | "k"
    | "idx"
    | "index"
    | "m"
    | "n"
    | "left"
    | "right"
    | "mid"
    | "low"
    | "high"
    | "pivot"
    | "gap" => true
    _ => false
  }
}

///|
/// 十进制整数解析（Rust value.parse::<i32>().ok()；负数也收——循环变量
/// 值可为负）。
fn parse_i32(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let cs = s.to_array()
  let mut idx = 0
  let mut neg = false
  if cs[0] == '-' {
    neg = true
    idx = 1
    if cs.length() == 1 {
      return None
    }
  }
  let mut n : Int = 0
  while idx < cs.length() {
    if cs[idx] < '0' || cs[idx] > '9' {
      return None
    }
    n = n * 10 + (cs[idx].to_int() - '0'.to_int())
    idx = idx + 1
  }
  Some(if neg { -n } else { n })
}

///|
/// 函数定义行判定（`int helper(int x) {` 形态——把定义行从递归判定排除，
/// 此前把定义行标成"递归调用 helper"是直接呈现给学生的错误描述）。
fn is_function_definition_line(line : String, func_name : String) -> Bool {
  line.has_suffix("{") && line.contains("\{func_name}(")
}

///|
/// 从源码行提取数组下标标识符（`temp = arr[j];` → j；只认简单下标，
/// 表达式下标〔arr[i + 1]〕返回 None）。
fn array_index_var(line : String) -> String? {
  let cs = line.to_array()
  let mut search_from = 0
  while search_from < cs.length() {
    if cs[search_from] != '[' {
      search_from = search_from + 1
      continue
    }
    let open = search_from
    // 向左找标识符（name[ 的 name 非空）
    let mut name_start = open - 1
    while name_start >= 0 && is_ident_char(cs[name_start]) {
      name_start = name_start - 1
    }
    name_start = name_start + 1
    if name_start < open {
      // 向右找 ]
      let mut close = open + 1
      while close < cs.length() && cs[close] != ']' {
        close = close + 1
      }
      if close < cs.length() {
        // 内部必须是纯标识符
        let mut inner_ok = close > open + 1
        let mut k = open + 1
        while k < close {
          if !is_ident_char(cs[k]) {
            inner_ok = false
            break
          }
          k = k + 1
        }
        if inner_ok {
          let buf = StringBuilder()
          let mut w = open + 1
          while w < close {
            buf.write_char(cs[w])
            w = w + 1
          }
          return Some(buf.to_string())
        }
      }
    }
    search_from = open + 1
  }
  None
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// 当前最内层迭代变量值（P0-3）：源码行下标优先 → j/i/k/idx/index 命名
/// 回退 → 列表末位；**不用 first()**（首位可能是 n/len 规模量）。
fn pick_inner_index(
  loop_vars : Array[(String, Int)],
  source_line : String,
) -> Int {
  match array_index_var(source_line) {
    Some(name) =>
      for pair in loop_vars {
        if pair.0 == name {
          return pair.1
        }
      }
    None => ()
  }
  for cand in ["j", "i", "k", "idx", "index"] {
    for pair in loop_vars {
      if pair.0 == cand {
        return pair.1
      }
    }
  }
  if loop_vars.length() > 0 {
    loop_vars[loop_vars.length() - 1].1
  } else {
    0
  }
}

///|
/// 从调用语句提取函数名（"x = foo(bar)" → foo；跳过赋值段，名字须纯
/// 标识符）。
fn extract_called_func(line : String) -> String? {
  let cs = line.trim().to_array()
  // 跳过赋值部分：找 '=' 后段
  let start = {
    let mut eq = -1
    let mut i = 0
    while i < cs.length() {
      // 跳过 == / <= / >= 的次 '='（简单形态：找首个单 '='——Rust find('=')
      // 同款首命中，'==' 次字符由提取段的标识符校验兜底）
      if cs[i] == '=' {
        eq = i
        break
      }
      i = i + 1
    }
    if eq >= 0 {
      eq + 1
    } else {
      0
    }
  }
  // 找 '('
  let mut paren = -1
  let mut j = start
  while j < cs.length() {
    if cs[j] == '(' {
      paren = j
      break
    }
    j = j + 1
  }
  if paren < 0 {
    return None
  }
  // 名字 = '(' 前整段 trim（Rust after_assign[..paren].trim() 同形）——
  // **全段必须纯标识符**（"int fact" 含空格 → None——定义行由此外落
  // "函数调用"；此前实现取末词属私改，探针对拍实锤纠正）
  let mut name_start = start
  while name_start < paren && cs[name_start] == ' ' {
    name_start = name_start + 1
  }
  let mut name_end = paren - 1
  while name_end >= name_start && cs[name_end] == ' ' {
    name_end = name_end - 1
  }
  if name_start > name_end {
    return None
  }
  let mut w = name_start
  while w <= name_end {
    if !is_ident_char(cs[w]) {
      return None
    }
    w = w + 1
  }
  let buf = StringBuilder()
  w = name_start
  while w <= name_end {
    buf.write_char(cs[w])
    w = w + 1
  }
  Some(buf.to_string())
}
