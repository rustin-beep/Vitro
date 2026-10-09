// M14 根因提示（S8 analysis 批，2026-10-03）：trap 帧的 root_cause_hint
// 接线——此前 StepPayload.root_cause_hint 恒 None（gateway serve_step 头注
// 分叉登记）。照搬源 = native/src/unified/trace_analyzer/ 六件
//（mod 55 / bounds ~230 / div_zero 40 / double_free 36 / null_deref 36 /
// use_after_free 33 / utils 213 行）→ 本单文件。
//
// **session 依赖形态**：Rust 侧 bounds/div_zero 取 session.source_line_at
// 查源码——本侧经 `get_line : (Int) -> String` 闭包注入（engine 接线处
// 包装 SourceLineProvider，诊断域零 session 依赖）。
//
// 分派按 trap_message 文案子串分流（oracle mod.rs 逐分支照搬）——文案
// 是 vm trap 渲染单源的产物（两侧同文案），子串判据稳定。

///|
/// 循环构造信息（源码扫描产物——utils.rs LoopInfo 照搬）。
priv struct LoopInfo {
  lines : Array[Int]
  mut has_le : Bool
  mut increment : Int?
}

///|
fn LoopInfo::new() -> LoopInfo {
  // has_ge/start_val 已删（病 5，#47 2026-10-09——oracle utils.rs 同形死字段，
  // 照搬期注释登记后随死字段清理批摘除；bounds 判定消费的是局部 start_val）
  { lines: [], has_le: false, increment: None, }
}

///|
/// 子串首现位（码元单位；core String 无 find——自写字节序兼容扫描）。
fn str_find(s : String, pat : String) -> Int? {
  let n = s.length()
  let m = pat.length()
  if m == 0 || m > n {
    return None
  }
  for i in 0..<=(n - m) {
    if s[i:i + m] == pat {
      return Some(i)
    }
  }
  None
}

///|
/// marker 之后到串尾的子串（"只有 X 个元素" 类抽取的基础件）。
fn after_marker(s : String, marker : String) -> String? {
  guard str_find(s, marker) is Some(i) else { return None }
  Some(s[i + marker.length():].to_owned())
}

///|
/// 子串截取（marker 起至 end_marker 前，不含两者）。
fn between_markers(
  s : String,
  start_marker : String,
  end_marker : String,
) -> String? {
  guard after_marker(s, start_marker) is Some(rest) else { return None }
  guard str_find(rest, end_marker) is Some(e) else { return None }
  Some(rest[0:e].to_owned())
}

///|
/// 数字解析（"5"/"-3" → Int；空/非数字 → None）。
fn parse_int_opt(s : String) -> Int? {
  let t = s.trim()
  if t == "" {
    return None
  }
  Some(@string.parse_int(t)) catch {
    _ => None
  }
}

///|
/// 变量历史切片（utils.rs slice_variable_history 照搬）：trap_step 前
/// lookback 步（含）内名为 var_name 的局部变量快照序列。
fn slice_variable_history(
  steps : Array[@protocol.StepPayload],
  var_name : String,
  trap_step : Int,
  lookback : Int,
) -> Array[@protocol.ApiVariableSnapshot] {
  let start = if trap_step - lookback > 0 { trap_step - lookback } else { 0 }
  let result : Array[@protocol.ApiVariableSnapshot] = []
  for i in start..<=trap_step {
    if i >= steps.length() {
      break
    }
    for v in steps[i].local_vars {
      if v.name == var_name {
        result.push(v)
      }
    }
  }
  result
}

///|
/// 越界文案解析（utils.rs parse_bounds_message）："你访问了 arr[5]" →
/// (数组名, 下标)。
fn parse_bounds_message(msg : String) -> (String, Int)? {
  guard after_marker(msg, "你访问了 ") is Some(rest) else { return None }
  guard str_find(rest, "[") is Some(bo) else { return None }
  guard str_find(rest, "]") is Some(bc) else { return None }
  if bc <= bo {
    return None
  }
  let array_name = rest[0:bo].to_owned().trim().to_owned()
  guard parse_int_opt(rest[bo + 1:bc].to_owned()) is Some(index) else {
    return None
  }
  Some((array_name, index))
}

///|
/// 数组大小抽取（utils.rs extract_array_size）："只有 N 个元素"。
fn extract_array_size(msg : String) -> Int? {
  guard between_markers(msg, "只有 ", " 个元素") is Some(s) else {
    return None
  }
  parse_int_opt(s)
}

///|
/// UAF/Double-Free 文案的 (alloc_line, freed_line) 抽取（utils.rs
/// parse_alloc_freed_lines）： freed = 首个「第 N 行」（被 free 处），
/// alloc =「由第 N 行的 malloc」。
fn parse_alloc_freed_lines(msg : String) -> (Int, Int)? {
  guard between_markers(msg, "第 ", " 行") is Some(fs) else { return None }
  guard parse_int_opt(fs) is Some(freed_line) else { return None }
  guard between_markers(msg, "由第 ", " 行的") is Some(as_) else {
    return None
  }
  guard parse_int_opt(as_) is Some(alloc_line) else { return None }
  Some((alloc_line, freed_line))
}

///|

///|
/// 步长抽取（utils.rs extract_increment）："i++"/"i += 2"/"i = i + 2"。
fn extract_increment(line : String, v : String) -> Int? {
  let t = line.trim().to_owned()
  if t == v + "++;" || t == "++" + v + ";" {
    return Some(1)
  }
  guard after_marker(t, v + " += ") is Some(rest) else {
    guard after_marker(t, v + " = " + v + " + ") is Some(rest2) else {
      return None
    }
    return take_digits(rest2)
  }
  take_digits(rest)
}

///|
fn take_digits(s : String) -> Int? {
  let buf = StringBuilder()
  for c in s {
    if c >= '0' && c <= '9' {
      buf.write_char(c)
    } else {
      break
    }
  }
  parse_int_opt(buf.to_string())
}

///|
/// trap 行 ±6 行的循环构造扫描（utils.rs scan_loop_info 照搬）。
fn scan_loop_info(
  get_line : (Int) -> String,
  trap_line : Int,
  var_name : String,
  array_name : String,
) -> LoopInfo {
  let info = LoopInfo::new()
  for offset in -6..<=6 {
    let line_no = trap_line + offset
    if line_no <= 0 {
      continue
    }
    let text = get_line(line_no)
    if text == "" {
      continue
    }
    let looks_like_loop = text.contains("for(") || text.contains("for (")
    let looks_like_while = text.contains("while(") || text.contains("while (")
    let refers_var = text.contains(var_name)
    let refers_array = text.contains(array_name)
    if (looks_like_loop || looks_like_while) && (refers_var || refers_array) {
      if !info.lines.contains(line_no) {
        info.lines.push(line_no)
      }
      if text.contains("<=") {
        info.has_le = true
      }
    }
    if refers_var && !looks_like_loop && !looks_like_while {
      if extract_increment(text, var_name) is Some(inc) {
        info.increment = Some(inc)
        if !info.lines.contains(line_no) {
          info.lines.push(line_no)
        }
      }
    }
  }
  info.lines.sort_by(fn(a, b) { a - b })
  info
}

///|
/// 变量历史短串（utils.rs format_history_vals）：≤4 全列，否则首尾省略。
fn format_history_vals(vals : Array[Int]) -> String {
  let n = vals.length()
  if n == 0 {
    return ""
  }
  if n <= 4 {
    let buf = StringBuilder()
    for i, v in vals {
      if i > 0 {
        buf.write_string(" → ")
      }
      buf_write_int(buf, v)
    }
    return buf.to_string()
  }
  let buf = StringBuilder()
  buf_write_int(buf, vals[0])
  buf.write_string(" → ... → ")
  buf_write_int(buf, vals[n - 1])
  buf.to_string()
}

///|
fn buf_write_int(buf : StringBuilder, v : Int) -> Unit {
  buf.write_string(v.to_string())
}

///|
/// 常用循环/下标变量名（utils.rs is_likely_loop_var 照搬）。
fn is_likely_loop_var(name : String) -> Bool {
  [
    "i", "j", "k", "idx", "index", "m", "n", "left", "right", "mid", "low", "high",
    "pivot", "gap", "l", "r",
  ].contains(name)
}

// ─────────────────────────────────────────────────────────────────────
// 分析器五件 + bounds 细分类
// ─────────────────────────────────────────────────────────────────────

///|
/// 数组越界细分类（bounds.rs BoundsCategory 照搬）。
priv enum BoundsCategory {
  OffByOne // i <= n 应为 i < n
  WrongInit // 初值错（i=1 起）
  WrongIncrement // 步长跳越（i += 2）
  UninitializedIndex // 未初始化/外部输入
  Generic // 兜底
}

///|
fn BoundsCategory::as_str(self : BoundsCategory) -> String {
  match self {
    OffByOne => "OffByOne"
    WrongInit => "WrongInit"
    WrongIncrement => "WrongIncrement"
    UninitializedIndex => "UninitializedIndex"
    Generic => "GenericBounds"
  }
}

///|
/// NULL 解引用分析（null_deref.rs 照搬）。
fn analyze_null_deref(
  _trap_message : String,
  steps : Array[@protocol.StepPayload],
  trap_step : Int,
) -> @protocol.RootCauseHint? {
  guard trap_step < steps.length() else { return None }
  let trap_payload = steps[trap_step]
  let null_ptrs : Array[String] = []
  for p in trap_payload.pointer_snapshots {
    if p.status is Null {
      null_ptrs.push(p.name)
    }
  }
  let mut one_liner = "试图解引用一个 NULL 指针。NULL 指针不指向任何有效内存。"
  if null_ptrs.length() > 0 {
    one_liner = one_liner +
      " 当前为 NULL 的指针: " +
      str_join(null_ptrs, ", ") +
      "。请在使用前确保指针已被正确初始化（如通过 malloc 或赋值）。"
  }
  // 首个 NULL 指针的历史切片：曾指向有效地址后被置 NULL 的形态提示
  let related_lines = [trap_payload.code_line]
  if null_ptrs.length() > 0 {
    let first = null_ptrs[0]
    let history = slice_variable_history(steps, first, trap_step, 5)
    for h in history {
      if h.value != "0" && h.value != "0x0" && h.value != "NULL" {
        one_liner = one_liner +
          " 注意：'" +
          first +
          "' 之前指向过地址 " +
          h.value +
          "，后来变成了 NULL。"
        break
      }
    }
  }
  Some({
    category: "NullDeref",
    one_liner,
    related_lines,
    suggested_fix_kind: "AddNullCheck",
    suggested_fix_line: Some(trap_payload.code_line),
    suggested_fix_desc: Some("使用指针前检查是否为 NULL"),
  })
}

///|
fn str_join(parts : Array[String], sep : String) -> String {
  let buf = StringBuilder()
  for i, p in parts {
    if i > 0 {
      buf.write_string(sep)
    }
    buf.write_string(p)
  }
  buf.to_string()
}

///|
/// UAF 分析（use_after_free.rs 照搬）。
fn analyze_use_after_free(
  trap_message : String,
  steps : Array[@protocol.StepPayload],
  trap_step : Int,
) -> @protocol.RootCauseHint? {
  guard parse_alloc_freed_lines(trap_message) is Some((alloc_line, freed_line)) else {
    return None
  }
  guard trap_step < steps.length() else { return None }
  let trap_payload = steps[trap_step]
  let suspect : Array[String] = []
  for p in trap_payload.pointer_snapshots {
    if p.status is Freed {
      suspect.push(p.name)
    }
  }
  let mut one_liner = "这块内存在第 " +
    alloc_line.to_string() +
    " 行被分配，在第 " +
    freed_line.to_string() +
    " 行被释放，现在又被访问了。free 后请立即将指针置为 NULL，避免继续使用。"
  if suspect.length() > 0 {
    one_liner = one_liner + " 相关指针: " + str_join(suspect, ", ") + "。"
  }
  let related = dedup_sorted([alloc_line, freed_line, trap_payload.code_line])
  Some({
    category: "UseAfterFree",
    one_liner,
    related_lines: related,
    suggested_fix_kind: "SetNullAfterFree",
    suggested_fix_line: Some(freed_line),
    suggested_fix_desc: Some("free 后执行 p = NULL"),
  })
}

///|
/// Double-Free 分析（double_free.rs 照搬）。
fn analyze_double_free(
  trap_message : String,
  steps : Array[@protocol.StepPayload],
  trap_step : Int,
) -> @protocol.RootCauseHint? {
  guard parse_alloc_freed_lines(trap_message) is Some((alloc_line, freed_line)) else {
    return None
  }
  guard trap_step < steps.length() else { return None }
  let trap_payload = steps[trap_step]
  // 病 4 修复（#47，2026-10-09）：行号语义改口——freed_line 是首次 free 行、
  // code_line 是第二次 free 行（旧文案把 alloc_line 说成「第一次释放」，
  // 与 analyze_use_after_free 的 alloc/free 分清口径对齐，系漏改）。
  let one_liner = "同一块内存在第 " +
    freed_line.to_string() +
    " 行已被释放，现在第 " +
    trap_payload.code_line.to_string() +
    " 行又 free 了一次。每次 free(p) 后请立刻执行 p = NULL;，因为对 NULL 重复 free 是安全的。"
  let related = dedup_sorted([alloc_line, freed_line, trap_payload.code_line])
  Some({
    category: "DoubleFree",
    one_liner,
    related_lines: related,
    suggested_fix_kind: "SetNullAfterFree",
    suggested_fix_line: Some(freed_line),
    suggested_fix_desc: Some("free 后执行 p = NULL"),
  })
}

///|
/// 除零分析（div_zero.rs 照搬）。
fn analyze_div_zero(
  trap_message : String,
  steps : Array[@protocol.StepPayload],
  trap_step : Int,
) -> @protocol.RootCauseHint? {
  guard trap_step < steps.length() else { return None }
  let trap_payload = steps[trap_step]
  let dividend = match
    between_markers(trap_message, "你试图用 ", " 除以") {
    Some(s) => parse_int_opt(s)
    None => None
  }
  let mut one_liner = "发生了除零错误。除数变成了 0，这在数学上没有定义。"
  let zero_vars : Array[String] = []
  for v in trap_payload.local_vars {
    if v.value == "0" && !is_likely_loop_var(v.name) {
      zero_vars.push(v.name)
    }
  }
  if zero_vars.length() > 0 {
    one_liner = one_liner +
      " 当前值为 0 的变量: " +
      str_join(zero_vars, ", ") +
      "。请检查这些变量是否在除法前被正确初始化或保护。"
  } else if dividend is Some(d) {
    one_liner = one_liner +
      " 被除数是 " +
      d.to_string() +
      "，但除数变成了 0。请确认除法前检查了除数是否为零。"
  }
  Some({
    category: "DivZero",
    one_liner,
    related_lines: [trap_payload.code_line],
    suggested_fix_kind: "AvoidDivZero",
    suggested_fix_line: Some(trap_payload.code_line),
    suggested_fix_desc: Some("除法前检查除数是否为 0"),
  })
}

///|
/// 越界细分类推断（bounds.rs infer_bounds_category 照搬）。
fn infer_bounds_category(
  hist_vals : Array[Int],
  accessed_index : Int,
  array_size : Int,
  loop_info : LoopInfo,
) -> BoundsCategory {
  if hist_vals.length() < 2 {
    return UninitializedIndex
  }
  let start_val = hist_vals[0]
  let mut is_mono = true
  let mut max_step = 0
  for i in 1..<hist_vals.length() {
    if hist_vals[i] < hist_vals[i - 1] {
      is_mono = false
    }
    let d = hist_vals[i] - hist_vals[i - 1]
    if d > max_step {
      max_step = d
    }
  }
  if accessed_index == array_size &&
    is_mono &&
    max_step == 1 &&
    start_val == 0 &&
    loop_info.has_le {
    return OffByOne
  }
  if start_val > 0 && is_mono && max_step == 1 && accessed_index >= array_size {
    return WrongInit
  }
  if max_step > 1 && is_mono {
    return WrongIncrement
  }
  if accessed_index == array_size && loop_info.has_le {
    return OffByOne
  }
  Generic
}

///|
/// 越界分析（bounds.rs analyze_bounds 照搬——含细分类与文案构造）。
fn analyze_bounds(
  trap_message : String,
  steps : Array[@protocol.StepPayload],
  trap_step : Int,
  get_line : (Int) -> String,
) -> @protocol.RootCauseHint? {
  guard parse_bounds_message(trap_message) is Some((array_name, accessed_index)) else {
    return None
  }
  guard trap_step < steps.length() else { return None }
  let trap_payload = steps[trap_step]
  let array_size = match extract_array_size(trap_message) {
    Some(s) => s
    None => 0
  }
  // 疑似循环变量：当前值恰为越界下标的常用下标名
  let mut suspect_var : String? = None
  for v in trap_payload.local_vars {
    if suspect_var is Some(_) {
      break
    }
    if parse_int_opt(v.value) is Some(x) {
      if x == accessed_index && is_likely_loop_var(v.name) {
        suspect_var = Some(v.name)
      }
    }
  }
  let related : Array[Int] = []
  if suspect_var is Some(var_name) {
    let history = slice_variable_history(steps, var_name, trap_step, 20)
    let hist_vals : Array[Int] = []
    for h in history {
      if parse_int_opt(h.value) is Some(x) {
        hist_vals.push(x)
      }
    }
    let loop_info = scan_loop_info(
      get_line,
      trap_payload.code_line,
      var_name,
      array_name,
    )
    for l in loop_info.lines {
      related.push(l)
    }
    if !related.contains(trap_payload.code_line) {
      related.push(trap_payload.code_line)
    }
    related.sort_by(fn(a, b) { a - b })
    let cat = infer_bounds_category(
      hist_vals, accessed_index, array_size, loop_info,
    )
    let (one_liner, fix_kind, fix_line, fix_desc) = build_bounds_hint(
      cat, var_name, array_name, accessed_index, array_size, loop_info, hist_vals,
    )
    Some({
      category: cat.as_str(),
      one_liner,
      related_lines: dedup_sorted(related),
      suggested_fix_kind: fix_kind,
      suggested_fix_line: fix_line,
      suggested_fix_desc: fix_desc,
    })
  } else {
    related.push(trap_payload.code_line)
    Some({
      category: Generic.as_str(),
      one_liner: "数组 '" +
      array_name +
      "' 访问了越界索引 " +
      accessed_index.to_string() +
      "。请检查数组声明大小和所有使用该数组的循环条件。",
      related_lines: related,
      suggested_fix_kind: "None",
      suggested_fix_line: None,
      suggested_fix_desc: None,
    })
  }
}

///|
/// 细分类文案/修复建议构造（bounds.rs build_bounds_hint 照搬）。
fn build_bounds_hint(
  category : BoundsCategory,
  var_name : String,
  array_name : String,
  accessed_index : Int,
  array_size : Int,
  loop_info : LoopInfo,
  hist_vals : Array[Int],
) -> (String, String, Int?, String?) {
  let first_line = if loop_info.lines.length() > 0 {
    Some(loop_info.lines[0])
  } else {
    None
  }
  match category {
    OffByOne => {
      let last_ok = array_size - 1
      let msg = match first_line {
        Some(l) =>
          "数组越界是因为第 " +
          l.to_string() +
          " 行的循环条件使用了 '<='。数组 '" +
          array_name +
          "' 大小为 " +
          array_size.to_string() +
          "，最后一个有效索引是 " +
          last_ok.to_string() +
          "。建议将 '<=' 改为 '<'。"
        None =>
          "数组越界是因为循环条件使用了 '<='。数组 '" +
          array_name +
          "' 大小为 " +
          array_size.to_string() +
          "，最后一个有效索引是 " +
          last_ok.to_string() +
          "。建议将 '<=' 改为 '<'。"
      }
      (msg, "ChangeLeToLt", first_line, Some("将 <= 改为 <"))
    }
    WrongInit => {
      let start_val = if hist_vals.length() > 0 { hist_vals[0] } else { 0 }
      let msg = match first_line {
        Some(l) =>
          "数组 '" +
          array_name +
          "' 访问了越界索引 " +
          accessed_index.to_string() +
          "。循环变量 '" +
          var_name +
          "' 从 " +
          start_val.to_string() +
          " 开始，导致最终访问到索引 " +
          accessed_index.to_string() +
          "。建议将第 " +
          l.to_string() +
          " 行的初始值改为 0。"
        None =>
          "数组 '" +
          array_name +
          "' 访问了越界索引 " +
          accessed_index.to_string() +
          "。循环变量 '" +
          var_name +
          "' 从 " +
          start_val.to_string() +
          " 开始，导致最终访问到索引 " +
          accessed_index.to_string() +
          "。建议将初始值改为 0。"
      }
      (
        msg,
        "FixLoopStart",
        first_line,
        Some(
          "将 " +
          var_name +
          " 的初始值 " +
          start_val.to_string() +
          " 改为 0",
        ),
      )
    }
    WrongIncrement => {
      let step = match loop_info.increment {
        Some(s) => s
        None => 2
      }
      let msg = match first_line {
        Some(l) =>
          "数组 '" +
          array_name +
          "' 访问了越界索引 " +
          accessed_index.to_string() +
          "。循环变量 '" +
          var_name +
          "' 的步长是 " +
          step.to_string() +
          "，导致跳过了边界检查。建议将第 " +
          l.to_string() +
          " 行的步长改为 1，或调整循环条件。"
        None =>
          "数组 '" +
          array_name +
          "' 访问了越界索引 " +
          accessed_index.to_string() +
          "。循环变量 '" +
          var_name +
          "' 的步长是 " +
          step.to_string() +
          "，导致跳过了边界检查。建议将步长改为 1，或调整循环条件。"
      }
      (
        msg,
        "FixLoopIncrement",
        first_line,
        Some("将步长 " + step.to_string() + " 改为 1"),
      )
    }
    UninitializedIndex => {
      let msg = "索引变量 '" +
        var_name +
        "' 的值是 " +
        accessed_index.to_string() +
        "，但执行历史太短，可能是变量未初始化或从外部输入读取了非法值。建议在使用前初始化 '" +
        var_name +
        "'。"
      (msg, "InitVariable", None, Some("初始化 '" + var_name + "'"))
    }
    Generic => {
      let msg = if hist_vals.length() >= 2 {
        "数组 '" +
        array_name +
        "' 访问了越界索引 " +
        accessed_index.to_string() +
        "。请检查 '" +
        var_name +
        "' 的最近变化：" +
        format_history_vals(hist_vals) +
        "。"
      } else {
        "数组 '" +
        array_name +
        "' 访问了越界索引 " +
        accessed_index.to_string() +
        "。请检查循环边界或索引计算。"
      }
      (msg, "None", None, None)
    }
  }
}

///|
/// 三元组去重排序（Rust sort+dedup 对应物）。
fn dedup_sorted(arr : Array[Int]) -> Array[Int] {
  let a : Array[Int] = []
  for v in arr {
    a.push(v)
  }
  a.sort_by(fn(x, y) { x - y })
  let out : Array[Int] = []
  for v in a {
    if out.length() == 0 || out[out.length() - 1] != v {
      out.push(v)
    }
  }
  out
}

///|
/// trap 根因分析总入口（mod.rs TraceAnalyzer::analyze_trap 照搬）：
/// 按 trap_message 文案子串分流。steps = 全历史（含 trap 帧）。
fn analyze_trap(
  steps : Array[@protocol.StepPayload],
  trap_step : Int,
  trap_message : String,
  get_line : (Int) -> String,
) -> @protocol.RootCauseHint? {
  if trap_message.contains("数组越界") {
    return analyze_bounds(trap_message, steps, trap_step, get_line)
  }
  if trap_message.contains("Use-After-Free") || trap_message.contains("E3060") {
    return analyze_use_after_free(trap_message, steps, trap_step)
  }
  if trap_message.contains("Double-Free") || trap_message.contains("E3061") {
    return analyze_double_free(trap_message, steps, trap_step)
  }
  if trap_message.contains("除零") || trap_message.contains("除以零") {
    return analyze_div_zero(trap_message, steps, trap_step)
  }
  if trap_message.contains("NULL") || trap_message.contains("null") {
    return analyze_null_deref(trap_message, steps, trap_step)
  }
  None
}
