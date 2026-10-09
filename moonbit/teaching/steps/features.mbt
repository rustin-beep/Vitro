// teaching/steps·features（S8 teaching 批一号）：函数级特征提取——
// 判据各族共享的 FuncFeatures + AST 遍历。照搬源
// algorithm_detector/features.rs:1-644（CFG 四特征分叉登记见 moon.pkg
// 头注——恒默认值）；has_word 的驼峰切分含 U1#1 P0-1 连续大写缩写
// 合并修复与二审 §7.4 表锚（21 例）。

///|
/// 函数级特征集合（供各算法判据消费——cfg_* 四项恒默认：分叉登记）。
pub(all) struct FuncFeatures {
  mut loop_depth : Int
  mut max_loop_depth : Int
  mut has_nested_loops : Bool
  mut has_single_loop : Bool
  mut has_array_compare : Bool
  mut has_swap : Bool
  mut has_swap_in_inner_loop : Bool
  mut has_min_max_track : Bool
  mut has_shift_pattern : Bool
  mut is_recursive : Bool
  mut has_partition_pattern : Bool
  mut has_merge_pattern : Bool
  mut has_mid_calculation : Bool
  mut has_left_right_update : Bool
  mut has_adjacent_index_compare : Bool
  /// U1#1 P1-a：函数体含 `dp[` 数组访问（动态规划状态表特征）。
  mut has_dp_array : Bool
  /// 二审 P0-B：BST 语境特征——参数/返回类型 pointee 为 `TreeNode`
  /// 结构（整名匹配，穿透包装层）。
  mut is_treenode_ctx : Bool
  /// (line, type, context) 比较行序（保序——VisEvent 投影源）。
  mut compare_lines : Array[(Int, Int, String)]
}

///|
pub fn FuncFeatures::default() -> FuncFeatures {
  {
    loop_depth: 0,
    max_loop_depth: 0,
    has_nested_loops: false,
    has_single_loop: false,
    has_array_compare: false,
    has_swap: false,
    has_swap_in_inner_loop: false,
    has_min_max_track: false,
    has_shift_pattern: false,
    is_recursive: false,
    has_partition_pattern: false,
    has_merge_pattern: false,
    has_mid_calculation: false,
    has_left_right_update: false,
    has_adjacent_index_compare: false,
    has_dp_array: false,
    is_treenode_ctx: false,
    compare_lines: [],
  }
}

///|
const TEACHING_MAX_WALK_DEPTH : Int = 512

///|
/// 词边界 + 驼峰感知的整词匹配（大小写不敏感；U1#1 P0-1 连续大写缩写
/// 合并——isValidBST 含 "bst"、subString 不含；边界规则见 Rust
/// features.rs:70-101 注释，照搬）。
pub fn has_word(name : String, word : String) -> Bool {
  let chars = name
  let n = name.length()
  let words : Array[String] = []
  let cur = StringBuilder()
  for idx in 0..<n {
    let ch = chars[idx]
    if ch == '_' || ch == '-' || (ch >= '0' && ch <= '9') {
      if cur.to_string() != "" {
        words.push(cur.to_string())
        cur.reset()
      }
      continue
    }
    if ch >= 'A' && ch <= 'Z' {
      let prev_is_lower = idx > 0 &&
        chars[idx - 1] >= 'a' &&
        chars[idx - 1] <= 'z'
      let next_is_lower = idx + 1 < n &&
        chars[idx + 1] >= 'a' &&
        chars[idx + 1] <= 'z'
      if cur.to_string() != "" && (prev_is_lower || next_is_lower) {
        words.push(cur.to_string())
        cur.reset()
      }
    }
    // 小写化压栈（ASCII 域——s[i] 是 UInt16 码元，统一转 Char 写入）
    let ci = ch.to_int()
    let lower = if ci >= 65 && ci <= 90 {
      (ci + 32).unsafe_to_char()
    } else {
      ci.unsafe_to_char()
    }
    cur.write_char(lower)
  }
  if cur.to_string() != "" {
    words.push(cur.to_string())
  }
  for w in words {
    if w == word {
      return true
    }
  }
  false
}

///|
/// 特征提取主口（walk 全函数体 + 派生布尔；Rust extract_features——
/// CFG 四特征分叉不迁）。
pub fn extract_features(func : @ast.FuncDecl, body : @ast.Stmt) -> FuncFeatures {
  let f = FuncFeatures::default()
  // is_recursive 需真实函数名（Rust 同位修复注释在案）
  walk_stmt(body, f, 0, func.name, 0)
  f.has_nested_loops = f.max_loop_depth >= 2
  f.has_single_loop = f.max_loop_depth >= 1
  // TreeNode 语境（穿透包装层整名匹配）
  let mut tn = false
  for p in func.params {
    if type_is_treenode(p.ty) {
      tn = true
      break
    }
  }
  f.is_treenode_ctx = tn || type_is_treenode(func.return_type)
  f
}

///|
fn walk_stmt(
  stmt : @ast.Stmt,
  f : FuncFeatures,
  loop_depth : Int,
  func_name : String,
  depth : Int,
) -> Unit {
  if depth > TEACHING_MAX_WALK_DEPTH {
    return
  }
  match stmt {
    Block(stmts, _) =>
      for s in stmts {
        walk_stmt(s, f, loop_depth, func_name, depth + 1)
      }
    If(cond, then_stmt, else_stmt, _) => {
      check_compare_expr(cond, f, loop_depth)
      // min/max 追踪模式（循环内比较 + 分支体含 min/max 赋值）
      if loop_depth >= 1 &&
        is_comparison_expr(cond) &&
        (
          stmt_has_min_max_assign(then_stmt) ||
          (else_stmt is Some(s) && stmt_has_min_max_assign(s))
        ) {
        f.has_min_max_track = true
      }
      walk_stmt(then_stmt, f, loop_depth, func_name, depth + 1)
      match else_stmt {
        Some(e) => walk_stmt(e, f, loop_depth, func_name, depth + 1)
        None => ()
      }
    }
    While(cond, body, _) => {
      check_compare_expr(cond, f, loop_depth)
      let new_depth = loop_depth + 1
      if new_depth > f.max_loop_depth {
        f.max_loop_depth = new_depth
      }
      walk_stmt(body, f, new_depth, func_name, depth + 1)
    }
    DoWhile(body, cond, _) => {
      let new_depth = loop_depth + 1
      if new_depth > f.max_loop_depth {
        f.max_loop_depth = new_depth
      }
      walk_stmt(body, f, new_depth, func_name, depth + 1)
      check_compare_expr(cond, f, loop_depth)
    }
    For(init, cond, step, body, _) => {
      let new_depth = loop_depth + 1
      if new_depth > f.max_loop_depth {
        f.max_loop_depth = new_depth
      }
      match init {
        Some(i) => walk_stmt(i, f, loop_depth, func_name, depth + 1)
        None => ()
      }
      match cond {
        Some(c) => check_compare_expr(c, f, loop_depth)
        None => ()
      }
      for s in step {
        walk_expr(s, f, loop_depth, func_name, depth + 1)
      }
      walk_stmt(body, f, new_depth, func_name, depth + 1)
    }
    VarDecl(_, _, init, extra_vars, _, _) => {
      match init {
        Some(e) => walk_expr(e, f, loop_depth, func_name, depth + 1)
        None => ()
      }
      for ex in extra_vars {
        match ex.init {
          Some(e) => walk_expr(e, f, loop_depth, func_name, depth + 1)
          None => ()
        }
      }
    }
    Expr(e, _) => walk_expr(e, f, loop_depth, func_name, depth + 1)
    Return(Some(v), _) => walk_expr(v, f, loop_depth, func_name, depth + 1)
    Switch(cond, body, _) => {
      walk_expr(cond, f, loop_depth, func_name, depth + 1)
      walk_stmt(body, f, loop_depth, func_name, depth + 1)
    }
    Case(_, s, _) => walk_stmt(s, f, loop_depth, func_name, depth + 1)
    _ => ()
  }
}

///|
fn walk_expr(
  expr : @ast.Expr,
  f : FuncFeatures,
  loop_depth : Int,
  func_name : String,
  depth : Int,
) -> Unit {
  if depth > TEACHING_MAX_WALK_DEPTH {
    return
  }
  match expr {
    Binary(op, left, right, _, _) => {
      walk_expr(left, f, loop_depth, func_name, depth + 1)
      walk_expr(right, f, loop_depth, func_name, depth + 1)
      // mid 计算：(a + b) / 2 或 a + (b - a) / 2
      if (op is Add || op is Div) && is_mid_calculation(expr) {
        f.has_mid_calculation = true
      }
    }
    Unary(_, operand, _, _) =>
      walk_expr(operand, f, loop_depth, func_name, depth + 1)
    Call(name, args, _, _) => {
      for a in args {
        walk_expr(a, f, loop_depth, func_name, depth + 1)
      }
      if name == func_name {
        f.is_recursive = true
      }
      call_pattern_flags(name, f)
    }
    // CallPtr 自调用（二审 P0-B：真实管线调用统一此形态——Call 臂
    // 单独匹配会漏 is_recursive，Rust 同位修复）
    CallPtr(callee, args, _, _) => {
      for a in args {
        walk_expr(a, f, loop_depth, func_name, depth + 1)
      }
      if callee is Identifier(name, _, _) {
        if name == func_name {
          f.is_recursive = true
        }
        call_pattern_flags(name, f)
      }
    }
    Index(array, index, _, _) => {
      // dp[...] 状态表访问特征
      if array is Identifier(name, _, _) {
        if name == "dp" {
          f.has_dp_array = true
        }
      }
      walk_expr(array, f, loop_depth, func_name, depth + 1)
      walk_expr(index, f, loop_depth, func_name, depth + 1)
    }
    Member(object, _, _, _) =>
      walk_expr(object, f, loop_depth, func_name, depth + 1)
    Assign(op, left, right, _, _) => {
      walk_expr(left, f, loop_depth, func_name, depth + 1)
      walk_expr(right, f, loop_depth, func_name, depth + 1)
      // 交换模式：两侧都是下标访问
      if is_index_access(left) && is_index_access(right) {
        if loop_depth >= 2 {
          f.has_swap_in_inner_loop = true
        }
        f.has_swap = true
      }
      // left/right 更新（索引含 mid 的赋值）
      if op is Assign {
        if left is Index(_, idx, _, _) {
          if expr_to_string(idx).contains("mid") {
            f.has_left_right_update = true
          }
        }
      }
      // 后移模式：arr[j+1] = arr[j]
      if op is Assign && is_shift_pattern(left, right) {
        f.has_shift_pattern = true
      }
    }
    Ternary(cond, then_branch, else_branch, _, _) => {
      walk_expr(cond, f, loop_depth, func_name, depth + 1)
      walk_expr(then_branch, f, loop_depth, func_name, depth + 1)
      walk_expr(else_branch, f, loop_depth, func_name, depth + 1)
    }
    Cast(e, _, _, _) => walk_expr(e, f, loop_depth, func_name, depth + 1)
    Sizeof(_, Some(e), _, _) =>
      walk_expr(e, f, loop_depth, func_name, depth + 1)
    InitList(elements, _, _) =>
      for e in elements {
        walk_expr(e.value, f, loop_depth, func_name, depth + 1)
      }
    _ => ()
  }
}

///|
/// 调用名模式旗标（partition/merge 包含性——Call/CallPtr 两臂共用）。
fn call_pattern_flags(name : String, f : FuncFeatures) -> Unit {
  let n = name.to_lower()
  if n.contains("partition") {
    f.has_partition_pattern = true
  }
  if n.contains("merge") {
    f.has_merge_pattern = true
  }
}

///|
fn check_compare_expr(
  expr : @ast.Expr,
  f : FuncFeatures,
  loop_depth : Int,
) -> Unit {
  match expr {
    Binary(op, left, right, loc, _) => {
      if is_comparison_op(op) {
        if is_index_access(left) || is_index_access(right) {
          f.has_array_compare = true
          f.compare_lines.push(
            (loc.line, 1, format_compare_context(left, right)),
          )
          if is_adjacent_compare(left, right) ||
            is_adjacent_compare(right, left) {
            f.has_adjacent_index_compare = true
          }
        } else {
          f.compare_lines.push(
            (loc.line, 1, format_compare_context(left, right)),
          )
        }
      }
      check_compare_expr(left, f, loop_depth)
      check_compare_expr(right, f, loop_depth)
    }
    Unary(_, operand, _, _) => check_compare_expr(operand, f, loop_depth)
    Call(_, args, _, _) =>
      for a in args {
        check_compare_expr(a, f, loop_depth)
      }
    Index(array, index, _, _) => {
      check_compare_expr(array, f, loop_depth)
      check_compare_expr(index, f, loop_depth)
    }
    Member(object, _, _, _) => check_compare_expr(object, f, loop_depth)
    Ternary(cond, then_branch, else_branch, _, _) => {
      check_compare_expr(cond, f, loop_depth)
      check_compare_expr(then_branch, f, loop_depth)
      check_compare_expr(else_branch, f, loop_depth)
    }
    Cast(e, _, _, _) => check_compare_expr(e, f, loop_depth)
    Sizeof(_, Some(e), _, _) => check_compare_expr(e, f, loop_depth)
    _ => ()
  }
}

///|
fn is_comparison_op(op : @ast.BinaryOp) -> Bool {
  match op {
    Lt | Gt | Le | Ge | Eq | Ne => true
    _ => false
  }
}

///|
fn is_comparison_expr(expr : @ast.Expr) -> Bool {
  match expr {
    Binary(op, _, _, _, _) => is_comparison_op(op)
    Unary(Not, operand, _, _) => is_comparison_expr(operand)
    _ => false
  }
}

///|
fn stmt_has_min_max_assign(stmt : @ast.Stmt) -> Bool {
  match stmt {
    Block(stmts, _) => {
      for s in stmts {
        if stmt_has_min_max_assign(s) {
          return true
        }
      }
      false
    }
    Expr(expr, _) => expr_has_min_max_assign(expr)
    VarDecl(_, _, init, extra_vars, _, _) => {
      let mut hit = false
      match init {
        Some(e) => hit = expr_has_min_max_assign(e)
        None => ()
      }
      if !hit {
        for ex in extra_vars {
          match ex.init {
            Some(e) =>
              if expr_has_min_max_assign(e) {
                hit = true
                break
              }
            None => ()
          }
        }
      }
      hit
    }
    _ => false
  }
}

///|
fn expr_has_min_max_assign(expr : @ast.Expr) -> Bool {
  match expr {
    Assign(_, left, _, _, _) =>
      if left is Identifier(name, _, _) {
        let n = name.to_lower()
        n.contains("min") || n.contains("max")
      } else {
        false
      }
    Binary(_, left, right, _, _) =>
      expr_has_min_max_assign(left) || expr_has_min_max_assign(right)
    Unary(_, operand, _, _) => expr_has_min_max_assign(operand)
    Ternary(cond, then_branch, else_branch, _, _) =>
      expr_has_min_max_assign(cond) ||
      expr_has_min_max_assign(then_branch) ||
      expr_has_min_max_assign(else_branch)
    Call(_, args, _, _) => {
      for a in args {
        if expr_has_min_max_assign(a) {
          return true
        }
      }
      false
    }
    CallPtr(callee, args, _, _) => {
      if expr_has_min_max_assign(callee) {
        return true
      }
      for a in args {
        if expr_has_min_max_assign(a) {
          return true
        }
      }
      false
    }
    Index(array, index, _, _) =>
      expr_has_min_max_assign(array) || expr_has_min_max_assign(index)
    Member(object, _, _, _) => expr_has_min_max_assign(object)
    Cast(e, _, _, _) => expr_has_min_max_assign(e)
    Sizeof(_, Some(e), _, _) => expr_has_min_max_assign(e)
    InitList(elements, _, _) => {
      for e in elements {
        if expr_has_min_max_assign(e.value) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn is_index_access(expr : @ast.Expr) -> Bool {
  expr is Index(_, _, _, _)
}

///|
fn is_literal_int(expr : @ast.Expr, val : Int) -> Bool {
  match expr {
    Literal(v, _, _) => v == val
    _ => false
  }
}

///|
/// 相邻索引比较（arr[x] vs arr[x+1]——AST 结构判定非字符串）。
fn is_adjacent_compare(a : @ast.Expr, b : @ast.Expr) -> Bool {
  match (a, b) {
    (Index(arr_a, idx_a, _, _), Index(arr_b, idx_b, _, _)) =>
      if expr_to_string(arr_a) == expr_to_string(arr_b) {
        match idx_b {
          Binary(Add, left, right, _, _) =>
            expr_to_string(left) == expr_to_string(idx_a) &&
            is_literal_int(right, 1)
          _ => false
        }
      } else {
        false
      }
    _ => false
  }
}

///|
/// mid 计算（(a+b)/2 或 a+(b-a)/2——二分语境特征）。
fn is_mid_calculation(expr : @ast.Expr) -> Bool {
  // 模式1: (a + b) / 2
  match expr {
    Binary(Div, left, right, _, _) =>
      if is_literal_int(right, 2) && left is Binary(Add, _, _, _, _) {
        return true
      }
    _ => ()
  }
  // 模式2: a + (b - a) / 2
  match expr {
    Binary(Add, left, right, _, _) =>
      match right {
        Binary(Div, div_left, div_right, _, _) =>
          if is_literal_int(div_right, 2) {
            match div_left {
              Binary(Sub, _, sub_right, _, _) =>
                return expr_to_string(sub_right) == expr_to_string(left)
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  false
}

///|
/// 后移模式（arr[x] = arr[y] 且 x == y+1——插入排序特征）。
fn is_shift_pattern(left : @ast.Expr, right : @ast.Expr) -> Bool {
  match (left, right) {
    (Index(arr_l, idx_l, _, _), Index(arr_r, idx_r, _, _)) =>
      if expr_to_string(arr_l) == expr_to_string(arr_r) {
        match idx_l {
          Binary(Add, add_left, add_right, _, _) =>
            expr_to_string(add_left) == expr_to_string(idx_r) &&
            is_literal_int(add_right, 1)
          _ => false
        }
      } else {
        false
      }
    _ => false
  }
}

///|
fn format_compare_context(left : @ast.Expr, right : @ast.Expr) -> String {
  "\{expr_to_string(left)}:\{expr_to_string(right)}"
}

///|
/// 类型是否指向 `TreeNode` 结构（穿透 Pointer/Array/Reference/Function
/// 包装层；整名忽略大小写——`BTreeNode` 含子串但非二叉树节点）。
fn type_is_treenode(ty : @ast.Type) -> Bool {
  match ty {
    Struct(name, _) | Class(name, _) => name.to_lower() == "treenode"
    Pointer(pointee, _) => type_is_treenode(pointee)
    Array(element, _, _, _, _, _) => type_is_treenode(element)
    Reference(base, _) => type_is_treenode(base)
    RValueRef(base) => type_is_treenode(base)
    Function(return_type, param_types, _, _) => {
      if type_is_treenode(return_type) {
        return true
      }
      for p in param_types {
        if type_is_treenode(p) {
          return true
        }
      }
      false
    }
    _ => false
  }
}
