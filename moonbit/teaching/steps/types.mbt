// teaching/steps·骨架（S8 teaching 批一号，2026-10-01）：类型 + 共享
// 工具 + 步骤推断主口。照搬源 vitro_algorithm_steps/src/lib.rs:1-202
//（AlgorithmMatch 消费 session 预埋形态；VariableSnapshot/InferEnv/
// VarMap/is_signature_line/is_comparison_line/build_step 逐字照搬）。

///|
/// 变量快照（轻量形态——value 已格式化为字符串；与帧上下文解耦，
/// Rust crate 同款非 FRB 版）。
pub(all) struct VarSnapshot {
  name : String
  value : String
} derive(Debug)

///|
/// 帧上下文（U1#1 管道批：单行源码判据够不到的三类信息，由 collector
/// 构造注入——`prev_vars` 行入口变量快照〔"展示运算过程"的 phase 用它
/// 拼算式，行末帧的 b 已被本语句赋值〕/ `at_callee_entry`+`caller_is_main`
/// 被调函数入口帧与顶层启动调用的区分 / `lookahead` 下 3 行源码
//〔多行/嵌套 for 的循环体不在 for 行内，初始化循环判定需要看体〕）。
pub(all) struct InferEnv {
  prev_vars : Array[VarSnapshot]
  at_callee_entry : Bool
  caller_is_main : Bool
  lookahead : String
} derive(Debug)

///|
/// 变量名→值查找（Rust VarMap 同款三读口：整型解析失败视无值）。
pub struct VarMap {
  vars : Array[VarSnapshot]
}

///|
pub fn VarMap::new(vars : Array[VarSnapshot]) -> VarMap {
  { vars, }
}

///|
/// 整型读（首个同名；parse 失败 = None——Rust `parse::<i32>().ok()`）。
pub fn VarMap::get_int(self : VarMap, name : String) -> Int? {
  for v in self.vars {
    if v.name == name {
      return parse_int(v.value)
    }
  }
  None
}

///|
/// 多别名整型读（按序首个命中——`["n","len","size","length"]` 族）。
pub fn VarMap::get_int_any(self : VarMap, names : Array[String]) -> Int? {
  for name in names {
    guard self.get_int(name) is Some(v) else { continue }
    return Some(v)
  }
  None
}

///|
/// 字符串读（首个同名，不解析）。
pub fn VarMap::get_str(self : VarMap, name : String) -> String? {
  for v in self.vars {
    if v.name == name {
      return Some(v.value)
    }
  }
  None
}

///|
/// 整数解析（Rust `str::parse::<i32>()`——首尾空白容忍度对齐：Rust
/// parse **不容忍**空白，本侧同样严格；infer 消费面 value 均为引擎
/// 格式化产物无空白）。可选正负号 + 数字序列；溢出/非数字 = None。
fn parse_int(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut idx = 0
  let mut neg = false
  let first = s[0]
  if first == '+' {
    idx = 1
  } else if first == '-' {
    neg = true
    idx = 1
  }
  if idx >= s.length() {
    return None
  }
  let mut n : Int = 0
  while idx < s.length() {
    let c = s[idx]
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
    idx = idx + 1
  }
  if neg {
    Some(-n)
  } else {
    Some(n)
  }
}

///|
/// 比较行判定（Rust is_comparison_line：四运算符包含性）。
fn is_comparison_line(line : String) -> Bool {
  line.contains(">") ||
  line.contains("<") ||
  line.contains("==") ||
  line.contains("!=")
}

///|
/// 步骤快照构造（Rust build_step——algorithm_name/display_name 取自
/// 匹配，phase/description 为判据产出）。
fn build_step(
  algorithm : @session.AlgorithmMatch,
  phase : String,
  description : String,
) -> @protocol.AlgorithmStepSnapshot {
  {
    algorithm_name: algorithm.name,
    display_name: algorithm.display_name,
    phase,
    description,
  }
}

///|
/// 是否为函数签名/定义行（二审 P1-5：以类型关键字开头且以 `{` 结尾——
/// `int mid = (left + right) / 2;` 以分号结尾不受影响；函数入口帧的
/// code_line 归因到定义行，彼时局部变量尚未初始化、数值是哨兵值，
/// 不产出算法步骤）。
fn is_signature_line(source_line : String) -> Bool {
  let t = source_line.trim_start()
  let type_kw : Array[String] = [
    "void ", "int ", "char ", "long ", "double ", "float ", "unsigned ", "static ",
    "struct ", "bool ", "_Bool ",
  ]
  let mut hit = false
  for k in type_kw {
    if t.length() >= k.length() && t[:k.length()].to_string() == k {
      hit = true
      break
    }
  }
  if not(hit) {
    return false
  }
  // 尾部首个非空白字符是 '{'（trim_end 语义的手工扫描——StringView
  // 无 substring，CodeUnit 直判）
  let mut last = -1
  let n = t.length()
  let mut k = n - 1
  while k >= 0 {
    let c = t[k]
    if c != ' ' && c.to_int() != 9 && c.to_int() != 13 && c.to_int() != 10 {
      last = c.to_int()
      break
    }
    k = k - 1
  }
  last == 123
}

///|
/// 步骤推断主口（Rust infer_algorithm_step——判据分派；批一号仅
/// sorting 族九算法已迁移，其余族 `_ => None` 段登记进度随批补齐）。
pub fn infer_algorithm_step(
  code_line : Int,
  local_vars : Array[VarSnapshot],
  func_name : String,
  source_line : String,
  algorithm : @session.AlgorithmMatch?,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  if code_line <= 0 || func_name.is_empty() {
    return None
  }
  guard algorithm is Some(alg) else { return None }
  // 二审 P1-5：函数签名/定义行不产出算法步骤
  if is_signature_line(source_line) {
    return None
  }
  let vars = VarMap::new(local_vars)
  match alg.name {
    "bubble_sort" => infer_bubble_sort(source_line, vars, alg)
    "selection_sort" => infer_selection_sort(source_line, vars, alg)
    "insertion_sort" => infer_insertion_sort(source_line, vars, alg, env)
    "quick_sort" => infer_quick_sort(source_line, vars, alg, func_name, env)
    "merge_sort" => infer_merge_sort(source_line, vars, alg, func_name, env)
    "heap_sort" => infer_heap_sort(source_line, vars, alg, func_name)
    "shell_sort" => infer_shell_sort(source_line, vars, alg)
    "counting_sort" => infer_counting_sort(source_line, vars, alg)
    "radix_sort" => infer_radix_sort(source_line, vars, alg)
    // 批二号（search + string 族）
    "binary_search" => infer_binary_search(source_line, vars, alg)
    "string_reverse" => infer_string_reverse(source_line, vars, alg)
    "string_match_bf" => infer_string_match_bf(source_line, vars, alg)
    "string_match_kmp" => infer_string_match_kmp(source_line, vars, alg)
    // 批三号（tree 族）
    "bst_insert" => infer_bst_insert(source_line, vars, alg, func_name)
    "bst_validate" => infer_bst_validate(source_line, vars, alg, func_name, env)
    "bst_delete" => infer_bst_delete(source_line, vars, alg, func_name)
    "bst_search" => infer_bst_search(source_line, vars, alg, func_name)
    "level_order" => infer_level_order(source_line, vars, alg)
    "threaded_binary_tree" => infer_threaded_binary_tree(source_line, vars, alg)
    "huffman_tree" => infer_huffman_tree(source_line, vars, alg)
    "avl_tree" => infer_avl_tree(source_line, vars, alg)
    // —— 未迁移族（批四号+逐族补齐，None 降级是协议合法形态）——
    // bfs/dfs/dp/linked_list_delete/gcd/is_prime/hanoi/seq_list/
    // linked_list_append/circular_queue/linked_stack/linked_queue/
    // hash_table/josephus/circular_linked_list/static_linked_list/
    // union_find/prim_mst/kruskal_mst/dijkstra/floyd/topological_sort
    _ => None
  }
}
