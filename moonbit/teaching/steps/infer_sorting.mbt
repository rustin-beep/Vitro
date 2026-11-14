// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

// teaching/steps·infer sorting 族（S8 teaching 批一号）：九算法步骤
// 推断照搬 vitro_algorithm_steps/src/sorting.rs:1-507（含全部用户审阅
// 修复语义：j 合法上界越界描述拦截 / minIdx 别名表 / 插入收紧
// arr[j+1]=key 形态 + prev_vars 行入口兜底 / 子数组错字 / 空区间递归基
// 拦截 / 枢轴落位文案 / 位权位序 / count[...]++ 收紧——逐条注释照搬）。

///|
/// 裸赋值 = 位置（PR #347 审阅 P1 v2 抽公共段）：返回首个非比较
///（==/<=/>=/!=）非复合（+= 等）赋值 = 的下标；无则 -1。s[i] 是
/// UInt16 码元（陷阱 24）——与 Char 字面量的 == 比较合法、绑定赋值
/// 不合法，故全部内联比较。
fn bare_assign_eq(line : String) -> Int32 {
  let n = line.length()
  let mut i = 0
  while i < n {
    if line[i] == '=' {
      let compound = (i + 1 < n && line[i + 1] == '=') ||
        (
          i > 0 &&
          (
            line[i - 1] == '=' ||
            line[i - 1] == '<' ||
            line[i - 1] == '>' ||
            line[i - 1] == '!' ||
            line[i - 1] == '+' ||
            line[i - 1] == '-' ||
            line[i - 1] == '*' ||
            line[i - 1] == '/' ||
            line[i - 1] == '%' ||
            line[i - 1] == '&' ||
            line[i - 1] == '|' ||
            line[i - 1] == '^'
          )
        )
      if !compound {
        return i
      }
      i = i + 2
    } else {
      i = i + 1
    }
  }
  -1
}

///|
/// 交换赋值行判定 v2（PR #347 审阅 P1 处置，2026-10-28：v1「某一侧
/// 下标」放宽出 7/16 误报面——单向读 `x=a[j]`/极值初值 `int min=arr[i]`/
/// 求和 `sum=a[j]+a[j+1]`/字符串内 `=`/注释行/三目全被误标 swap）。
/// **收紧为左侧下标写**：行非注释且含裸赋值 =（比较/复合算子排除）且
/// **左侧**为下标访问——三行交换的主行（a[j]=a[j+1]）与回写行
///（a[j+1]=t）命中（@swap:N 帧序完整），暂存读行（int t=a[j]）不命中
///（单向读无交换语义）。PR #463 审阅 P3-4 勘正头注：v3 的 RHS 暂存名
/// 判定**就是**字面量白名单（temp/tmp/t/hold/swap 五名——v2 头注的
///「不再字面量依赖」只描述 LHS 侧；RHS 侧白名单是有意的窄面：教科书
/// 暂存名域收敛，白名单外形态（如 insertion 的 key）不冒充交换）。
/// v3（#436 翻面 M30-A1）：**左侧下标写 ≠ 交换**——再要求 RHS 为
/// ①下标访问（同数组互赋主行）或②教科书暂存名（t/tmp/temp/hold/swap
/// 的回写行）。`visited[i]=0`（常量清零）/ `arr[i]=i`（初始化）/
/// `next[j]=k`（建表）/ `queue[rear++]=v`（入队）等单向下标写全排除
/// ——交换须有双向数据流动证据。
pub fn is_swap_assign_line(line : String) -> Bool {
  let trimmed = line.trim()
  if trimmed.has_prefix("//") ||
    trimmed.has_prefix("/*") ||
    trimmed.has_prefix("*") {
    return false
  }
  let eq = bare_assign_eq(line)
  if eq < 0 {
    return false
  }
  let left = line[0:eq].trim().to_owned()
  if !is_index_text(left) {
    return false
  }
  // RHS（去 ; 与空白）判定：下标访问 或 暂存名
  let rhs_raw = line[eq + 1:line.length()].trim().to_owned()
  let rhs = if rhs_raw.length() > 0 && rhs_raw[rhs_raw.length() - 1] == ';' {
    rhs_raw[0:rhs_raw.length() - 1].trim().to_owned()
  } else {
    rhs_raw
  }
  if rhs.is_empty() {
    return false
  }
  if is_index_text(rhs) {
    // v4（#517 P2-7，2026-11-14）：RHS 下标访问臂**再要求纯下标整体 +
    // 与 LHS 同数组名**——跨数组拷贝（`tmp[k]=a[i]` 的 merge 暂存）与前缀
    // 和表达式（`pre[i]=pre[i-1]+dp[i]`）无交换语义（A2/B7 实录 338/225
    // 帧误标「交换」）。v3 的 is_index_text 只查含 []，表达式拼接照命中。
    // 交换 = 同数组两下标互换（双向数据流动证据）。
    match (index_access_name(left), index_access_name(rhs)) {
      (Some(l), Some(r)) => l == r
      _ => false
    }
  } else {
    rhs == "temp" ||
    rhs == "tmp" ||
    rhs == "t" ||
    rhs == "hold" ||
    rhs == "swap"
  }
}

///|
/// 交换对与数组名提取（#436 翻面 M30-A1——collector label 与 bubble
/// infer 单源共享）：从行内容提取交换数组名与下标对。
/// · 主行（行内 ≥2 个下标访问）→ 首两个下标求值
/// · 回写行（单下标）→ 对侧取同表达式减一（相邻形态 `arr[j+1]=temp`）
///   或另一侧循环变量（裸 j 形态由 fallback_var 提供——bubble 语境 i）
/// 求值不可得 / 下标越界（n>0 时）返回 None——无据不拼。
pub fn swap_index_pair(
  source_line : String,
  prev_vars : Array[VarSnapshot],
  vars : VarMap,
  fallback_var : String,
  n : Int32,
  allow_fallback~ : Bool = true,
) -> (String, Int32, Int32)? {
  let exprs = line_index_exprs(source_line)
  if exprs.length() == 0 {
    return None
  }
  let arr_name = first_array_name(source_line)
  guard arr_name is Some(an) else { return None }
  let in_bounds = fn(v : Int32) -> Bool {
    if n > 0 {
      v >= 0 && v < n
    } else {
      v >= 0
    }
  }
  if exprs.length() >= 2 {
    match
      (
        eval_index_expr(exprs[0], prev_vars, vars),
        eval_index_expr(exprs[1], prev_vars, vars),
      ) {
      (Some(l), Some(r)) =>
        if in_bounds(l) && in_bounds(r) {
          return Some((an, l, r))
        }
      _ => ()
    }
    return None
  }
  // 单下标回写行
  match eval_index_expr(exprs[0], prev_vars, vars) {
    Some(e1) => {
      let unified = strip_spaces(exprs[0])
      let is_offset = unified.contains("+") || unified.contains("-")
      if !is_offset && !allow_fallback {
        // 回写行对侧无行内证据——调用方声明不信任 fallback 变量
        //（collector：跨算法对侧变量不定——bubble=i/quick=i+1/heap=
        // largest，单帧不可辨；无据不产）
        return None
      }
      let l = if is_offset {
        e1 - 1
      } else {
        match vars.get_int_any([fallback_var]) {
          Some(v) => v
          None => return None
        }
      }
      if in_bounds(l) && in_bounds(e1) {
        return Some((an, l, e1))
      }
    }
    None => ()
  }
  None
}

///|
/// 行内首个数组访问名（`arr[i] > arr[j]` → "arr"；`visited[v] = 1` →
/// "visited"——#436：文案数组名与行内容同源，禁硬编码 arr）。
fn first_array_name(line : String) -> String? {
  let n = line.length()
  let mut k = 0
  while k < n {
    if line[k] == '[' {
      let mut s = k - 1
      while s >= 0 {
        let c = line[s]
        let idc = (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '_'
        if !idc {
          break
        }
        s = s - 1
      }
      if s + 1 < k {
        return Some(line[s + 1:k].to_owned())
      }
    }
    k = k + 1
  }
  None
}

///|
/// 声明暂存读判定（shell sort 的 insert 相位专用，PR #347 审阅 P2-c
/// 连坐）：`int temp = arr[i];` 形——裸赋值 + **左侧为类型声明**（无
/// 下标）+ **右侧下标访问**。shell 语境内该形态 = 保存当前元素准备同组
/// 插入（教科书 shell 模板真实写法）；`x = a[j]` 纯赋值读不命中（须
/// 显式类型前缀——与极值初值的区分靠 shell_matcher 语境隔离）。
fn is_decl_index_read_line(line : String) -> Bool {
  let trimmed = line.trim()
  if trimmed.has_prefix("//") ||
    trimmed.has_prefix("/*") ||
    trimmed.has_prefix("*") {
    return false
  }
  let eq = bare_assign_eq(line)
  if eq < 0 {
    return false
  }
  let left = line[0:eq].trim().to_owned()
  let right_raw = line[eq + 1:line.length()].trim().to_owned()
  let right = if right_raw.length() > 0 &&
    right_raw[right_raw.length() - 1] == ';' {
    right_raw[0:right_raw.length() - 1].trim().to_owned()
  } else {
    right_raw
  }
  // 左侧为类型声明（int/long/char/short/float/double/unsigned 前缀）且
  // 无下标；右侧下标访问
  let decl_types = [
    "int", "long", "char", "short", "float", "double", "unsigned",
  ]
  let mut is_decl = false
  for ty in decl_types {
    if left.has_prefix(ty) {
      is_decl = true
      break
    }
  }
  is_decl && !is_index_text(left) && is_index_text(right)
}

///|
/// 下标访问文本形态（含 [...]——is_swap_assign_line 的侧判定）。
fn is_index_text(s : String) -> Bool {
  s.contains("[") && s.contains("]")
}

///|
/// 纯下标访问整体形态 + 数组名提取（#517 P2-7，2026-11-14）：`name[expr]`
/// /`name[a][b]` 整体（标识符 + 一层以上下标层，层外无任何余字符）——
/// 返回数组名；非纯（含表达式拼接 `pre[i-1] + dp[i]`、含取址/调用等）
/// 返回 None。is_swap_assign_line v4 的 RHS 同名判据消费（跨数组拷贝
/// `tmp[k]=a[i]` 与前缀和表达式赋值无交换语义——A2/B7 实录 338/225 帧
/// 误标「交换」形态的根因：v3 的 is_index_text 只查含 []）。
fn index_access_name(s : String) -> String? {
  let st = s.trim().to_owned()
  let t = st.to_array()
  let n = t.length()
  let mut i = 0
  while i < n && is_ident_char_v4(t[i]) {
    i = i + 1
  }
  if i == 0 || i >= n || t[i] != '[' {
    return None
  }
  let name = st[0:i].to_owned()
  let mut layers = 0
  while i < n && t[i] == '[' {
    layers = layers + 1
    i = i + 1
    let mut depth = 0
    let mut closed = false
    while i < n {
      if t[i] == '[' {
        depth = depth + 1
      } else if t[i] == ']' {
        if depth == 0 {
          closed = true
          i = i + 1
          break
        }
        depth = depth - 1
      }
      i = i + 1
    }
    if !closed {
      return None
    }
  }
  if layers == 0 || i != n {
    return None
  }
  Some(name)
}

///|
fn is_ident_char_v4(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// 行内下标表达式提取（#436 翻面 M34b A7）：`if (arr[i] > arr[j + 1])`
/// → ["i", "j + 1"]——文案下标必须与行内容同源，禁硬编码 j+1。
/// 注释行不提取（is_swap_assign_line 同款排除）。
fn line_index_exprs(line : String) -> Array[String] {
  let trimmed = line.trim()
  if trimmed.has_prefix("//") ||
    trimmed.has_prefix("/*") ||
    trimmed.has_prefix("*") {
    return []
  }
  let out : Array[String] = []
  let n = line.length()
  let mut k = 0
  while k < n {
    // 找 '['，向左扫标识符字符，向右取到匹配 ']' 的表达式文本
    if line[k] == '[' {
      let mut s = k - 1
      while s >= 0 {
        let c = line[s]
        let idc = (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '_'
        if !idc {
          break
        }
        s = s - 1
      }
      // 左侧须有标识符（数组名）——`(arr[` / `= arr[` 等形态；裸 `[` 跳过
      if s + 1 < k {
        let mut e = k + 1
        while e < n && line[e] != ']' && line[e] != ';' {
          e = e + 1
        }
        if e < n && line[e] == ']' {
          out.push(line[k + 1:e].trim().to_owned())
        }
      }
    }
    k = k + 1
  }
  out
}

///|
/// 首个指定字符分割（两段；无该字符返回 None）。c 为 ASCII（'+'/'-'），
/// 码元直比（陷阱 24：s[k] 是 UInt16）。
fn split_first(s : String, c : Char) -> (String, String)? {
  let n = s.length()
  let mut k = 0
  while k < n {
    if s[k].to_int() == c.to_int() {
      return Some((s[0:k].to_owned(), s[k + 1:n].to_owned()))
    }
    k = k + 1
  }
  None
}

///|
/// 去全部空格（陷阱 37：replace 只替换首个——逐字符重建）。
fn strip_spaces(s : String) -> String {
  let b = StringBuilder()
  let n = s.length()
  let mut k = 0
  while k < n {
    let cu = s[k].to_int()
    if cu != 32 && cu != 9 {
      b.write_char(Char::from_int(cu))
    }
    k = k + 1
  }
  b.to_string()
}

///|
/// 下标表达式求值（#436 翻面 M34b A2/A7）：支持 纯数字 / 裸变量 /
/// 变量±数字 形态。求值次序（PR #463 审阅 P3-3 照实写）：
/// **帧 vars 优先，行入口快照（prev_vars）兜底**——主行/回写行的行末
/// 帧循环变量未推进（帧值即语句执行态真值）；偏移表达式基名不在帧
/// vars 时（假比较帧 j 已被 for 增量推进的窗口）才落行入口。
/// 不可求值返回 None。
fn eval_index_expr(
  expr : String,
  prev_vars : Array[VarSnapshot],
  vars : VarMap,
) -> Int32? {
  let t = expr.trim().to_owned()
  if t.is_empty() {
    return None
  }
  // 纯数字
  match parse_int(t) {
    Some(v) => return Some(v)
    None => ()
  }
  // 变量 ± 偏移（含空格形态 "j + 1"）
  let unified = strip_spaces(t)
  for off in ['+', '-'] {
    match split_first(unified, off) {
      Some((base, delta)) =>
        if base.length() > 0 && delta.length() > 0 {
          match (parse_int(delta), vars.get_int_any([base])) {
            (Some(d), Some(b)) =>
              return Some(if off == '+' { b + d } else { b - d })
            _ => ()
          }
          // 基名不在帧 vars——试行入口快照
          match (parse_int(delta), prev_get_int(prev_vars, base)) {
            (Some(d), Some(b)) =>
              return Some(if off == '+' { b + d } else { b - d })
            _ => ()
          }
        }
      None => ()
    }
  }
  // 裸变量：帧 vars 优先（回写行/主行的行末帧循环变量未推进），行入口兜底
  match vars.get_int_any([unified]) {
    Some(v) => return Some(v)
    None => ()
  }
  prev_get_int(prev_vars, unified)
}

///|
/// 比较行/交换主行的下标对求值：行内下标表达式 ≥2 个时取前两个
///（`if (arr[i] > arr[j])` → (i,j)；`arr[j] = arr[j + 1]` → (j, j+1)）。
fn pair_from_line(
  source_line : String,
  prev_vars : Array[VarSnapshot],
  vars : VarMap,
) -> (Int32, Int32)? {
  let exprs = line_index_exprs(source_line)
  if exprs.length() < 2 {
    return None
  }
  match
    (
      eval_index_expr(exprs[0], prev_vars, vars),
      eval_index_expr(exprs[1], prev_vars, vars),
    ) {
    (Some(l), Some(r)) => Some((l, r))
    _ => None
  }
}

///|
/// 基名提取（下标表达式的首个标识符 token：`j + 1` → `j`）。
fn index_base_name(expr : String) -> String {
  let unified = strip_spaces(expr)
  let n = unified.length()
  let mut k = 0
  let acc = StringBuilder()
  while k < n {
    let c = unified[k]
    let idc = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_'
    if !idc {
      break
    }
    acc.write_char(Char::from_int(c.to_int()))
    k = k + 1
  }
  acc.to_string()
}

///|
/// 行内下标基名是否自行入口以来被推进（幽灵帧判定——基名在帧 vars 与
/// 行入口快照的值不同 ⇒ 帧串跨过 for 增量 ⇒ 本帧非该语句执行态）。
fn loop_over_exprs(
  exprs : Array[String],
  prev_vars : Array[VarSnapshot],
  vars : VarMap,
) -> Bool {
  for e in exprs {
    let base = index_base_name(e)
    if base.is_empty() {
      continue
    }
    match (prev_get_int(prev_vars, base), vars.get_int_any([base])) {
      (Some(pv), Some(fv)) => if pv != fv { return true }
      _ => ()
    }
  }
  false
}

///|
/// 冒泡排序。
fn infer_bubble_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let i = match vars.get_int("i") {
    Some(v) => v
    None => -1
  }
  let j = match vars.get_int("j") {
    Some(v) => v
    None => -1
  }
  let n = match vars.get_int_any(["n", "len", "size", "length"]) {
    Some(v) => v
    None => -1
  }
  // 文案下标值域守卫（数组界语义——#436 翻面 M34b A2：文案要报的每个
  // 下标 ∈ [0, n-1]。原守卫 `j < n - 1 - i` 绑定「内层界 n-1-i」模板
  // 假设，无 -i 变体（内层 `j < n - 1`）i≥1 后半程合法比较/交换帧被吞；
  // 且非相邻变体（`arr[i] > arr[j]`，j 域到 n-1）的末位合法帧也被
  // j+1≤n-1 误拦——守卫跟着**文案实际要报的下标**走，不再预设法形态。
  let idx_in_bounds = fn(l : Int32, r : Int32) -> Bool {
    if n > 0 {
      l >= 0 && l < n && r >= 0 && r < n
    } else {
      l >= 0 && r >= 0
    }
  }
  if starts_with(line_lower, "for ") || starts_with(line_lower, "while ") {
    if line_lower.contains("i") && !line_lower.contains("j") {
      let pass = if i >= 0 { "\{i + 1}" } else { "?" }
      // 第 pass 趟确定"第 pass 大"的元素（此前 n-i 写法把概念教反了）
      let kth = if n > 0 && i >= 0 && i < n { "\{i + 1}" } else { "?" }
      return Some(
        build_step(
          algorithm,
          "outer_loop",
          "第 \{pass} 趟：将第 \{kth} 大的元素放到正确位置",
        ),
      )
    }
    if line_lower.contains("j") {
      let j_str = if j >= 0 { "\{j}" } else { "?" }
      return Some(
        build_step(
          algorithm,
          "inner_loop",
          "内层循环 j=\{j_str}，比较相邻元素",
        ),
      )
    }
  }
  if starts_with(line_lower, "if ") && is_comparison_line(line_lower) {
    // #436 翻面（M34b A2/A7）：下标对从行内容提取（原恒拼 j/j+1 与
    // `arr[i] > arr[j]` 行脱钩）；求值用行入口 vars——假比较的行末帧
    // j 已被 for 增量推进（serve 一帧发布缓冲把 compare 帧挂行末帧），
    // 比较时刻真值在行入口快照。
    match pair_from_line(source_line, env.prev_vars, vars) {
      Some((l, r)) =>
        if idx_in_bounds(l, r) {
          return Some(
            build_step(algorithm, "compare", "比较 arr[\{l}] 与 arr[\{r}]"),
          )
        }
      None => ()
    }
    return None
  }
  if is_swap_assign_line(source_line) {
    // #436 翻面（M34b A7 + M30-A1）：交换对从行内容提取（单源
    // swap_index_pair——双下标主行取前两个；单下标回写行对侧取同表达式
    // 减一〔相邻 `arr[j+1]=temp`〕或另一侧循环变量 i〔非相邻裸 j 形态〕）。
    //
    // 幽灵帧守卫（#436 落闸发现）：交换组行帧串若跨过 for 增量（行入口
    // 快照的基名值 ≠ 帧值——j 已推进），末帧的行归属是「块尾跳转」而非
    // 回写语句本身——此时产 swap 帧=给未发生的交换报文案（错位一档的
    // 幽灵交换）。真交换组帧（主行/回写行执行中）恒无推进。
    let exprs = line_index_exprs(source_line)
    let advanced = loop_over_exprs(exprs, env.prev_vars, vars)
    if advanced {
      return None
    }
    match swap_index_pair(source_line, env.prev_vars, vars, "i", n) {
      Some((an, l, r)) =>
        return Some(
          build_step(
            algorithm,
            "swap",
            "交换 \{an}[\{l}]↔\{an}[\{r}]，较大的元素向右移动",
          ),
        )
      None => ()
    }
    return None
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "排序完成"))
  }
  None
}

///|
/// 选择排序。
fn infer_selection_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let i = match vars.get_int("i") {
    Some(v) => v
    None => -1
  }
  let j = match vars.get_int("j") {
    Some(v) => v
    None => -1
  }
  // minIdx 驼峰别名（U1#1 P1-84：模板变量名是 minIdx——别名表漏它导致
  // min_idx=? / arr[?]）
  let min_idx = match
    vars.get_int_any(["min_idx", "minIndex", "min", "minindex", "minIdx"]) {
    Some(v) => v
    None => -1
  }
  if starts_with(line_lower, "for ") || starts_with(line_lower, "while ") {
    if line_lower.contains("i") && !line_lower.contains("j") {
      let pass = if i >= 0 { "\{i}" } else { "?" }
      return Some(
        build_step(
          algorithm,
          "outer_loop",
          "第 \{pass} 趟：从第 \{pass} 个位置开始找最小值",
        ),
      )
    }
    if line_lower.contains("j") {
      let j_str = if j >= 0 { "\{j}" } else { "?" }
      let min_str = if min_idx >= 0 { "\{min_idx}" } else { "?" }
      return Some(
        build_step(
          algorithm,
          "inner_loop",
          "扫描 j=\{j_str}，当前最小值在 min_idx=\{min_str}",
        ),
      )
    }
  }
  if starts_with(line_lower, "if ") && is_comparison_line(line_lower) {
    // 越界守卫（U1#1 P1-84：arr[5]（n=5 越界）与 j==n 收尾帧不产出）
    let n_val = match vars.get_int("n") {
      Some(v) => v
      None => -1
    }
    if n_val >= 0 && j >= n_val {
      return None
    }
    let j_str = if j >= 0 { "\{j}" } else { "?" }
    let min_str = if min_idx >= 0 { "\{min_idx}" } else { "?" }
    return Some(
      build_step(
        algorithm,
        "compare",
        "比较 arr[\{j_str}] 与当前最小值 arr[\{min_str}]",
      ),
    )
  }
  if is_swap_assign_line(source_line) {
    let i_str = if i >= 0 { "\{i}" } else { "?" }
    return Some(
      build_step(algorithm, "swap", "将最小元素交换到位置 \{i_str}"),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "排序完成"))
  }
  None
}

///|
/// 插入排序。
fn infer_insertion_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let i = match vars.get_int("i") {
    Some(v) => v
    None => -1
  }
  let j = match vars.get_int("j") {
    Some(v) => v
    None => -1
  }
  let key = match vars.get_str("key") {
    Some(v) => v
    None => "?"
  }
  if starts_with(line_lower, "for ") || starts_with(line_lower, "while ") {
    if line_lower.contains("i") && !line_lower.contains("j") {
      let pass = if i >= 0 { "\{i}" } else { "?" }
      return Some(
        build_step(
          algorithm,
          "outer_loop",
          "第 \{pass} 个元素：准备插入到已排序部分",
        ),
      )
    }
    if line_lower.contains("j") && line_lower.contains("[") {
      let j_str = if j >= 0 { "\{j}" } else { "?" }
      return Some(
        build_step(
          algorithm,
          "inner_loop",
          "元素后移 j=\{j_str}，为插入腾出位置",
        ),
      )
    }
  }
  if starts_with(line_lower, "if ") && is_comparison_line(line_lower) {
    let j_str = if j >= 0 { "\{j}" } else { "?" }
    return Some(
      build_step(algorithm, "compare", "比较 arr[\{j_str}] 与 key=\{key}"),
    )
  }
  // 写回形态收紧（U1#1 P1-60：`arr[j + 1] = key`——读操作行与后移行
  // 不误命中）
  if line_lower.contains("key") &&
    (source_line.contains("[j + 1]") || source_line.contains("[j+1]")) &&
    source_line.contains("=") &&
    !source_line.contains("= arr") {
    // j 作用域收回时试行入口快照 prev_vars 的 j（§6-4/v4 #77 两态矛盾
    // 修复）；两处都取不到才降级（降级文案不带位置数字）
    let j_entry = env_prev_int(env, "j")
    let j_eff = if j >= 0 { Some(j) } else { j_entry }
    match j_eff {
      Some(jj) =>
        return Some(
          build_step(
            algorithm,
            "insert",
            "将 key=\{key} 插入到正确位置 \{jj + 1}",
          ),
        )
      None =>
        return Some(build_step(algorithm, "insert", "将 key=\{key} 插入"))
    }
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "排序完成"))
  }
  None
}

///|
/// 快速排序。
fn infer_quick_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
  env : InferEnv,
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
  let pivot = match vars.get_int_any(["pivot", "p"]) {
    Some(v) => v
    None => -1
  }
  let i = match vars.get_int("i") {
    Some(v) => v
    None => -1
  }
  // 递归调用自身
  if source_line.contains("\{func_name}(") {
    // callee entry + caller_is_main 区分顶层启动（U1#1 P1-3 收口）
    if env.at_callee_entry && env.caller_is_main {
      // #224：callee 入口首帧形参尚未落局部（store 指令未执行），
      // left/right 读出哨兵 -1——此前文案直接拼出「区间 [left=-1,
      // right=-1]」垃圾值；读不到时降级为不带数字的启动文案
      if left >= 0 && right >= 0 {
        return Some(
          build_step(
            algorithm,
            "recursive",
            "启动快速排序：处理区间 [left=\{left}, right=\{right}]",
          ),
        )
      }
      return Some(
        build_step(
          algorithm, "recursive", "启动快速排序：处理整个数组",
        ),
      )
    }
    // side 空串默认（P1-79「子子数组」错字修复）
    let side = if i >= 0 && pivot >= 0 {
      if i < pivot {
        "左"
      } else {
        "右"
      }
    } else {
      ""
    }
    // 空区间/反区间递归基帧不产出（P1-79）
    if left >= 0 && right >= 0 && left <= right {
      return Some(
        build_step(
          algorithm,
          "recursive",
          "递归调用 \{func_name}，处理\{side}子数组 [left=\{left}, right=\{right}]",
        ),
      )
    }
    return None
  }
  // #436 翻面（M34b A5，#93 收口补修）：落位语义只在 **RHS 含 partition(
  // 调用**形态（`int pivot = partition(arr, low, high);`——pivot 变量是
  // 分区返回的落位下标）。原 contains(pivot)&&contains(=) 宽判据对内联
  // 形态的取枢轴行（`int pivot = arr[high]`——pivot 是**值**）与分区
  // 判断行（`if (arr[j] <= pivot)`——<= 含 =）双双误命中，文案把值 50
  // 当落位下标报「pivot=50」（越出下标域）。
  if line_lower.contains("pivot") &&
    line_lower.contains("=") &&
    line_lower.contains("partition(") &&
    !starts_with(line_lower, "for ") {
    let p_str = if pivot >= 0 { "\{pivot}" } else { "?" }
    // §6-6（v4 #93）：pivot 值是分区后落位下标非枢轴值——文案修正
    return Some(
      build_step(
        algorithm,
        "partition_init",
        "分区完成，枢轴落位下标 pivot=\{p_str}",
      ),
    )
  }
  if (starts_with(line_lower, "while ") || starts_with(line_lower, "for ")) &&
    (line_lower.contains("i") || line_lower.contains("j")) {
    return Some(
      build_step(
        algorithm, "partition_scan", "分区扫描：将小于枢轴的元素放到左侧",
      ),
    )
  }
  if is_swap_assign_line(source_line) {
    return Some(
      build_step(
        algorithm, "partition_swap", "交换元素，调整分区位置",
      ),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "快速排序完成"))
  }
  None
}

///|
/// 归并排序。
fn infer_merge_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let left = match vars.get_int_any(["left", "low", "l", "start"]) {
    Some(v) => v
    None => -1
  }
  let right = match vars.get_int_any(["right", "high", "r", "end"]) {
    Some(v) => v
    None => -1
  }
  if source_line.contains("\{func_name}(") {
    // caller_is_main 区分顶层启动（U1#1 P1-4 收口）
    if env.at_callee_entry && env.caller_is_main {
      // #224：与快排同款——入口首帧形参未落局部时降级（不拼 [-1, -1]）
      if left >= 0 && right >= 0 {
        return Some(
          build_step(
            algorithm,
            "recursive_split",
            "启动归并：处理区间 [\{left}, \{right}]",
          ),
        )
      }
      return Some(
        build_step(
          algorithm, "recursive_split", "启动归并：处理整个数组",
        ),
      )
    }
    if left >= 0 && right >= 0 && left < right {
      return Some(
        build_step(
          algorithm,
          "recursive_split",
          "将数组区间 [\{left}, \{right}] 递归分成两半",
        ),
      )
    }
    return None
  }
  if line_lower.contains("merge") && line_lower.contains("(") {
    return Some(build_step(algorithm, "merge", "合并两个有序子数组"))
  }
  if (starts_with(line_lower, "while ") || starts_with(line_lower, "for ")) &&
    (
      line_lower.contains("i") ||
      line_lower.contains("j") ||
      line_lower.contains("k")
    ) {
    return Some(build_step(algorithm, "merge", "合并两个有序子数组"))
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "归并排序完成"))
  }
  None
}

///|
/// 堆排序。
fn infer_heap_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  ignore(vars)
  if source_line.contains("\{func_name}(") && func_name != "heapSort" {
    return Some(
      build_step(
        algorithm, "heapify", "递归堆化：确保子树满足堆性质",
      ),
    )
  }
  if starts_with(line_lower, "for ") || starts_with(line_lower, "while ") {
    if line_lower.contains("n / 2") || line_lower.contains("mid") {
      return Some(
        build_step(
          algorithm, "build_heap", "建堆：自底向上将数组调整为最大堆",
        ),
      )
    }
    if line_lower.contains("i") && line_lower.contains("n - 1") {
      return Some(
        build_step(algorithm, "extract", "取出堆顶元素并重新堆化"),
      )
    }
  }
  if is_swap_assign_line(source_line) {
    return Some(build_step(algorithm, "swap", "交换元素，调整堆结构"))
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "堆排序完成"))
  }
  None
}

///|
/// 希尔排序。
fn infer_shell_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let gap = match vars.get_int_any(["gap"]) {
    Some(v) => v
    None => -1
  }
  if starts_with(line_lower, "for ") && line_lower.contains("gap") {
    return Some(
      build_step(
        algorithm,
        "outer_loop",
        "取增量 gap=\{gap}，分组进行插入排序",
      ),
    )
  }
  if is_decl_index_read_line(source_line) && !starts_with(line_lower, "for ") {
    return Some(
      build_step(
        algorithm, "insert", "保存当前元素，准备在同组内插入",
      ),
    )
  }
  if line_lower.contains("j") &&
    line_lower.contains("gap") &&
    line_lower.contains("[") {
    return Some(
      build_step(
        algorithm, "inner_loop", "同组内元素后移，腾出插入位置",
      ),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "希尔排序完成"))
  }
  None
}

///|
/// 计数排序。
fn infer_counting_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  ignore(vars)
  if starts_with(line_lower, "for ") &&
    line_lower.contains("count") &&
    line_lower.contains("++") {
    return Some(
      build_step(algorithm, "count", "统计每个数值的出现次数"),
    )
  }
  // place 判据收紧 index++ 形态（U1#1 P1-21：`int index = 0;` 声明行
  // 不判 place）
  if line_lower.contains("index++") {
    return Some(
      build_step(algorithm, "place", "将数值放回原数组的正确位置"),
    )
  }
  if starts_with(line_lower, "for ") &&
    line_lower.contains("i") &&
    line_lower.contains("10") {
    return Some(
      build_step(algorithm, "collect", "按数值从小到大收集元素"),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "计数排序完成"))
  }
  None
}

///|
/// 基数排序。
fn infer_radix_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let exp = match vars.get_int_any(["exp"]) {
    Some(v) => v
    None => -1
  }
  if line_lower.contains("exp") &&
    line_lower.contains("max") &&
    line_lower.contains("/") {
    // 位序 = log10(exp)+1（U1#1 P1-81：exp 是位权非位序——"第 10 位"
    // 错文案修复）。exp ∈ {1,10,100,...} 域内：逐位除 10 计数。
    let mut digit = 0
    let mut e = exp
    if exp > 0 {
      digit = 1
      while e >= 10 {
        e = e / 10
        digit = digit + 1
      }
    }
    return Some(
      build_step(
        algorithm,
        "digit_loop",
        "按第 \{digit} 位进行分配-收集",
      ),
    )
  }
  // count[…]++ 自增形态（二审 P1-2：`++` 会被 for 头 i++ 满足——
  // 清零行误命中，收紧 `]++`）
  if line_lower.contains("count[") &&
    line_lower.contains("]++") &&
    !line_lower.contains("+=") {
    return Some(
      build_step(algorithm, "count", "统计当前位各数字出现次数"),
    )
  }
  if line_lower.contains("count[i]") && line_lower.contains("count[i - 1]") {
    return Some(
      build_step(algorithm, "prefix", "计算前缀和，确定位置"),
    )
  }
  if line_lower.contains("output[") &&
    line_lower.contains("count[") &&
    line_lower.contains("=") {
    return Some(build_step(algorithm, "place", "按前缀和放置元素"))
  }
  None
}

///|
/// 前缀工具：行首匹配。
fn starts_with(s : String, prefix : String) -> Bool {
  s.length() >= prefix.length() && s[0:prefix.length()].to_owned() == prefix
}

///|
/// prev_vars 行入口整型读（Rust `find + trim().parse()`——本侧 value
/// 严格解析，trim 容忍 Rust trim 语义）。
fn env_prev_int(env : InferEnv, name : String) -> Int32? {
  for v in env.prev_vars {
    if v.name == name {
      return parse_int(v.value.trim().to_owned())
    }
  }
  None
}
