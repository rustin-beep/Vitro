// teaching/steps·infer search 族（S8 teaching 批二号，2026-10-01）：
// 四算法照搬 vitro_algorithm_steps/src/search.rs:1-225——含全部审阅修复
// 语义：mid_calc 收紧（三分支不可达修复——比较行不再被短路）/ narrow
// 实际边界值（差一修复）/ nextval 表优先序（§6-7 v4 #35）/ 下标从行文本
// 解析（v5 ✗1——nextval[0]=-1 下标位不再被填成值）/ getNext 调用点无数值
//（U1#1 P1-19/96）。

///|
/// 二分查找。
fn infer_binary_search(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let left = match vars.get_int_any(["left", "low", "l"]) {
    Some(v) => v
    None => -1
  }
  let right = match vars.get_int_any(["right", "high", "r"]) {
    Some(v) => v
    None => -1
  }
  let mid = match vars.get_int_any(["mid", "m"]) {
    Some(v) => v
    None => -1
  }
  let target = match vars.get_str("target") {
    Some(t) => t
    None =>
      match vars.get_str("key") {
        Some(k) => k
        None => "?"
      }
  }
  if starts_with(line_lower, "while ") {
    let l = if left >= 0 { "\{left}" } else { "?" }
    let r = if right >= 0 { "\{right}" } else { "?" }
    return Some(build_step(algorithm, "loop", "搜索范围 [\{l}, \{r}]"))
  }
  // mid_calc 收紧（U1#1：旧 contains("mid")&&(=||/) 过宽——compare/
  // narrow 三分支全被短路，循环体里学生只看得到"计算中点"）
  if (starts_with(line_lower, "int mid") || starts_with(line_lower, "mid =")) &&
    line_lower.contains("/") {
    let m = if mid >= 0 { "\{mid}" } else { "?" }
    return Some(build_step(algorithm, "mid_calc", "计算中点 mid=\{m}"))
  }
  if starts_with(line_lower, "if ") &&
    is_comparison_line(line_lower) &&
    (line_lower.contains("arr[") || line_lower.contains("a[")) {
    let m = if mid >= 0 { "\{mid}" } else { "?" }
    return Some(
      build_step(
        algorithm,
        "compare",
        "arr[\{m}] 与目标值 \{target} 比较",
      ),
    )
  }
  if line_lower.contains("right") &&
    line_lower.contains("=") &&
    line_lower.contains("mid") {
    // 打印 right 实际值（差一修复：`right = mid - 1` 与 `right = mid`
    // 两种约定都正确）
    let r_now = if right >= 0 { "\{right}" } else { "?" }
    return Some(
      build_step(
        algorithm,
        "narrow_left",
        "目标值在左半区，调整右边界 right=\{r_now}",
      ),
    )
  }
  if line_lower.contains("left") &&
    line_lower.contains("=") &&
    line_lower.contains("mid") {
    let l_now = if left >= 0 { "\{left}" } else { "?" }
    return Some(
      build_step(
        algorithm,
        "narrow_right",
        "目标值在右半区，调整左边界 left=\{l_now}",
      ),
    )
  }
  if starts_with(line_lower, "return ") && line_lower.contains("mid") {
    let m = if mid >= 0 { "\{mid}" } else { "?" }
    return Some(
      build_step(algorithm, "found", "找到目标值，返回索引 \{m}"),
    )
  }
  if starts_with(line_lower, "return ") &&
    (line_lower.contains("-1") || line_lower.contains("0")) {
    return Some(
      build_step(algorithm, "not_found", "搜索结束，未找到目标值"),
    )
  }
  None
}

///|
/// 字符串反转。
fn infer_string_reverse(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let len = match vars.get_int_any(["len", "length"]) {
    Some(v) => v
    None => -1
  }
  let i = match vars.get_int("i") {
    Some(v) => v
    None => -1
  }
  if starts_with(line_lower, "while ") && line_lower.contains("\\0") {
    return Some(
      build_step(algorithm, "measure", "扫描字符串，计算长度"),
    )
  }
  if starts_with(line_lower, "for ") && line_lower.contains("len") {
    let other = if len >= 0 { "\{len - i - 1}" } else { "-1" }
    return Some(build_step(algorithm, "swap", "交换位置 \{i} 和 \{other}"))
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "字符串反转完成"))
  }
  None
}

///|
/// 朴素模式匹配。
fn infer_string_match_bf(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let i = match vars.get_int_any(["i"]) {
    Some(v) => v
    None => -1
  }
  let j = match vars.get_int_any(["j"]) {
    Some(v) => v
    None => -1
  }
  if line_lower.contains("s[") &&
    line_lower.contains("t[") &&
    line_lower.contains("==") {
    return Some(build_step(algorithm, "compare", "比较 S[\{i}] 与 T[\{j}]"))
  }
  if line_lower.contains("i - j + 1") {
    return Some(
      build_step(algorithm, "backtrack", "字符不匹配，主串回溯"),
    )
  }
  if starts_with(line_lower, "return") && line_lower.contains("-1") {
    return Some(build_step(algorithm, "not_found", "模式匹配失败"))
  }
  None
}

///|
/// KMP 模式匹配。
fn infer_string_match_kmp(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let j = match vars.get_int_any(["j"]) {
    Some(v) => v
    None => -1
  }
  let k = match vars.get_int_any(["k"]) {
    Some(v) => v
    None => -1
  }
  // nextval 优先于 next（§6-7 v4 #35：两张表——nextval 行同时含 "next["
  // 会被 next 分支吞掉）
  if line_lower.contains("nextval[") && line_lower.contains("=") {
    // 下标/值从行文本解析（v5 ✗1：nextval[0] = -1 的下标位是字面量，
    // 不再用变量 j 填——j 取到的是右侧的值）
    let desc = match parse_array_assign(source_line, "nextval", vars) {
      Some((idx, Some(val))) => "构建 nextval 数组，nextval[\{idx}]=\{val}"
      Some((idx, None)) => "构建 nextval 数组，nextval[\{idx}]"
      None => "构建 nextval 数组"
    }
    return Some(build_step(algorithm, "build_nextval", desc))
  }
  if line_lower.contains("getnextval") {
    return Some(
      build_step(algorithm, "build_nextval", "调用构建 nextval 数组"),
    )
  }
  if line_lower.contains("getnext") ||
    (line_lower.contains("next[") && line_lower.contains("=")) {
    // U1#1 P1-19/96：main 里的 getNext(T, next) 调用行命中 getnext——
    // 调用点产出无数值启动描述；函数体内（next[..] = 赋值形态）才带数值
    if !line_lower.contains("next[") {
      return Some(
        build_step(algorithm, "build_next", "调用构建 next 数组"),
      )
    }
    return Some(
      build_step(
        algorithm,
        "build_next",
        "构建 next 数组，next[\{j}]=\{k}",
      ),
    )
  }
  if line_lower.contains("s[") &&
    line_lower.contains("t[") &&
    line_lower.contains("==") {
    return Some(
      build_step(algorithm, "compare", "比较主串与模式串字符"),
    )
  }
  if line_lower.contains("next[j]") {
    return Some(build_step(algorithm, "skip", "j 回溯到 next[\{j}]=\{k}"))
  }
  None
}

///|
/// 解析 `<name>[<idx>] = <rhs>;` 形态（v5 ✗1）——(下标显示, 右侧纯字面量
/// 值)。下标字面量直取、标识符取变量当前值；右侧仅纯整数（可负）返回
/// 值，复杂右式 None。
fn parse_array_assign(
  line : String,
  name : String,
  vars : VarMap,
) -> (String, String?)? {
  let lower = line.to_lower()
  let open = "\{name}["
  let start0 = find_sub(lower, open, 0)
  guard start0 is Some(s0) else { return None }
  let start = s0 + open.length()
  let end0 = find_char(lower, ']', start)
  guard end0 is Some(e0) else { return None }
  let end = e0
  let idx_text = line[start:end].trim().to_owned()
  let idx = if idx_text != "" && all_digits(idx_text) {
    idx_text
  } else {
    match vars.get_int_any([idx_text]) {
      Some(v) => "\{v}"
      None => idx_text
    }
  }
  // 右侧：`=` 之后（取最后一个 = —— RHS 位）剥 ; 与空白
  let rhs_raw = if end + 1 < line.length() {
    line[end + 1:].to_owned()
  } else {
    ""
  }
  let eq0 = find_char_reverse(rhs_raw, '=')
  guard eq0 is Some(eq) else { return Some((idx, None)) }
  let rhs = rhs_raw[eq + 1:].trim().to_owned()
  let rhs = strip_trailing_semicolon(rhs).trim().to_owned()
  if rhs != "" && is_int_literal(rhs) {
    return Some((idx, Some(rhs)))
  }
  Some((idx, None))
}

///|
fn find_sub(s : String, sub : String, from : Int) -> Int? {
  let n = s.length()
  let m = sub.length()
  if m == 0 || n < m {
    return None
  }
  let mut i = if from < 0 { 0 } else { from }
  while i + m <= n {
    if s[i:i + m].to_owned() == sub {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn find_char(s : String, c : Char, from : Int) -> Int? {
  let n = s.length()
  let mut i = if from < 0 { 0 } else { from }
  while i < n {
    if s[i].to_int() == c.to_int() {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn find_char_reverse(s : String, c : Char) -> Int? {
  let mut i = s.length() - 1
  while i >= 0 {
    if s[i].to_int() == c.to_int() {
      return Some(i)
    }
    i = i - 1
  }
  None
}

///|
fn all_digits(s : String) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
/// 纯整数字面量（可选首 +/-，其余数字——Rust `enumerate().all` 同形）。
fn is_int_literal(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c >= '0' && c <= '9' {
      continue
    }
    if i == 0 && (c == '-' || c == '+') {
      continue
    }
    return false
  }
  true
}

///|
fn strip_trailing_semicolon(s : String) -> String {
  let t = s.trim_end().to_owned()
  let n = t.length()
  if n > 0 && t[n - 1] == ';' {
    return t[0:n - 1].to_owned()
  }
  t
}
