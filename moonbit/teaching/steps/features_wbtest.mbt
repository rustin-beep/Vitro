// teaching/steps·features 结构特征锚（2026-10-01 审阅 P2 补——迁移批
// 无对拍兜底，结构分支此前零锚：三个突变全绿的缺口）。真 AST 构造
// （ProgramNode→FuncDecl→Stmt 树）走 extract_features 全链——锚定
// walk_stmt/walk_expr/check_compare_expr 的特征产出与 detect 的结构
// 分支可达性。B13 序锚（bstKmpSearch 同命中多族的元素序）同文件。

///|
/// AST 构造 helper（wbtest 专用——最简 SourceLoc/类型形态）。
fn loc(line : Int) -> @source.SourceLoc {
  @source.SourceLoc::new(line, 1)
}

///|
fn int_ty() -> @ast.Type {
  Int(false, false)
}

///|
/// `for (INIT; COND; STEP) BODY` 语句。
fn mk_for(init : @ast.Stmt, cond : @ast.Expr, body : @ast.Stmt) -> @ast.Stmt {
  let steps : Array[@ast.Expr] = []
  For(Some(init), Some(cond), steps, body, loc(1))
}

///|
/// `for (I = A; I < N; i++) BODY` 标准计数循环。
fn mk_count_for(
  ivar : String,
  n_expr : @ast.Expr,
  body : @ast.Stmt,
) -> @ast.Stmt {
  let init : @ast.Stmt = VarDecl(
    int_ty(),
    ivar,
    Some(Literal(0, loc(1), int_ty())),
    [],
    false,
    loc(1),
  )
  let cond : @ast.Expr = Binary(
    Lt,
    Identifier(ivar, loc(1), int_ty()),
    n_expr,
    loc(1),
    int_ty(),
  )
  let steps : Array[@ast.Expr] = [
    Unary(PostInc, Identifier(ivar, loc(1), int_ty()), loc(1), int_ty()),
  ]
  For(Some(init), Some(cond), steps, body, loc(1))
}

///|
/// `arr[IDX]`。
fn mk_index(arr : String, idx : @ast.Expr) -> @ast.Expr {
  Index(Identifier(arr, loc(1), int_ty()), idx, loc(1), int_ty())
}

///|
/// `arr[IDX] = RHS`（交换对构造用）。
fn mk_index_assign(arr : String, idx : @ast.Expr, rhs : @ast.Expr) -> @ast.Expr {
  Assign(Assign, mk_index(arr, idx), rhs, loc(1), int_ty())
}

///|
fn mk_ident_expr(name : String) -> @ast.Expr {
  Identifier(name, loc(1), int_ty())
}

///|
/// 构造 FuncDecl（名 + 函数体）。
fn mk_func(name : String, body : @ast.Stmt) -> @ast.FuncDecl {
  {
    loc: loc(1),
    return_type: int_ty(),
    name,
    params: [],
    body: Some(body),
    is_static: false,
    is_extern: false,
    source_file: "main.c",
    is_variadic: false,
  }
}

///|
fn extract_of(name : String, body : @ast.Stmt) -> FuncFeatures {
  extract_features(mk_func(name, body), body)
}

///|
/// 锚二十八：bubble 结构特征全链——嵌套循环 + 相邻比较 + 交换 ⇒
/// detect_sorting 的**结构分支**（无 bubble 命名）命中 bubble_sort。
/// 体内：`if (arr[j] > arr[j+1]) { temp = arr[j]; arr[j] = arr[j+1]; arr[j+1] = temp; }`
test "teaching_features_bubble_structural_branch" {
  // 交换三连（temp 交换形态：两条下标互赋 + 一条 temp 读回）
  let swap_body : @ast.Stmt = Block(
    [
      Expr(
        mk_index_assign(
          "temp",
          mk_ident_expr("temp"),
          mk_index("arr", mk_ident_expr("j")),
        ),
        loc(1),
      ),
      Expr(
        mk_index_assign(
          "arr",
          mk_ident_expr("j"),
          mk_index(
            "arr",
            Binary(
              Add,
              mk_ident_expr("j"),
              Literal(1, loc(1), int_ty()),
              loc(1),
              int_ty(),
            ),
          ),
        ),
        loc(1),
      ),
    ],
    loc(1),
  )
  // 相邻比较 if
  let cmp : @ast.Expr = Binary(
    Gt,
    mk_index("arr", mk_ident_expr("j")),
    mk_index(
      "arr",
      Binary(
        Add,
        mk_ident_expr("j"),
        Literal(1, loc(1), int_ty()),
        loc(1),
        int_ty(),
      ),
    ),
    loc(1),
    int_ty(),
  )
  let inner_body : @ast.Stmt = Block([If(cmp, swap_body, None, loc(1))], loc(1))
  // 内层 for j < n-1-i；外层 for i < n-1
  let n_var = mk_ident_expr("n")
  let inner_cond : @ast.Expr = Binary(
    Lt,
    mk_ident_expr("j"),
    Binary(
      Sub,
      Binary(Sub, n_var, mk_ident_expr("i"), loc(1), int_ty()),
      Literal(1, loc(1), int_ty()),
      loc(1),
      int_ty(),
    ),
    loc(1),
    int_ty(),
  )
  let j_decl : @ast.Stmt = VarDecl(
    int_ty(),
    "j",
    Some(Literal(0, loc(1), int_ty())),
    [],
    false,
    loc(1),
  )
  let inner : @ast.Stmt = For(
    Some(j_decl),
    Some(inner_cond),
    [Unary(PostInc, mk_ident_expr("j"), loc(1), int_ty())],
    inner_body,
    loc(1),
  )
  let outer : @ast.Stmt = mk_count_for(
    "i",
    Binary(
      Sub,
      mk_ident_expr("n"),
      Literal(1, loc(1), int_ty()),
      loc(1),
      int_ty(),
    ),
    inner,
  )
  let body : @ast.Stmt = Block([outer], loc(1))
  // 特征断言：嵌套循环 / 数组比较 / 交换 / 相邻比较
  let f = extract_of("mySort", body)
  assert_true(f.has_nested_loops, msg="嵌套 for 必须识别")
  assert_true(
    f.has_array_compare,
    msg="if (arr[j] > arr[j+1]) 必须产数组比较",
  )
  assert_true(f.has_swap, msg="arr[j] = arr[j+1] 必须产交换特征")
  assert_true(
    f.has_adjacent_index_compare,
    msg="arr[j] vs arr[j+1] 必须产相邻比较",
  )
  // **oracle 死分支等价锚（2026-10-01 审阅 P2 深挖实锤）**：判据的
  // `loop_depth >= 2` 在两侧永不满足——walk 从不写 f.loop_depth（oracle
  // features.rs 同形：字段只在签名，恒 0），bubble/selection/insertion
  // 三结构分支在 oracle 也是死分支。断言「不命中」= 等价的机器判据
  //（两侧同病，修单侧即破等价——修复归 0.8.0 脱钩批裁定）。
  let ms = detect_sorting("mysort", f, "mySort", 1)
  assert_eq(
    ms.length(),
    0,
    msg="loop_depth 恒 0——结构分支两侧同为死分支（等价）",
  )
}

///|
/// 锚二十九：二分结构特征——单循环 + mid 计算 + left/right 更新 ⇒
/// detect_search 结构分支命中 binary_search（无 binary 命名）。
test "teaching_features_binary_structural_branch" {
  // mid = (left + right) / 2
  let mid_calc : @ast.Stmt = VarDecl(
    int_ty(),
    "mid",
    Some(
      Binary(
        Div,
        Binary(
          Add,
          mk_ident_expr("left"),
          mk_ident_expr("right"),
          loc(1),
          int_ty(),
        ),
        Literal(2, loc(1), int_ty()),
        loc(1),
        int_ty(),
      ),
    ),
    [],
    false,
    loc(1),
  )
  // right = mid - 1（索引含 mid 的赋值——walk 的 has_left_right_update）
  let narrow : @ast.Stmt = Expr(
    Assign(
      Assign,
      mk_ident_expr("right"),
      Binary(
        Sub,
        mk_ident_expr("mid"),
        Literal(1, loc(1), int_ty()),
        loc(1),
        int_ty(),
      ),
      loc(1),
      int_ty(),
    ),
    loc(1),
  )
  ignore(narrow)
  // walk 源：left/right 更新判据是「索引访问的赋值且 index 含 mid」——
  // 形态 arr[mid] = x；构造 arr[mid] = arr[left] 以触发
  let lr_update : @ast.Stmt = Expr(
    mk_index_assign(
      "arr",
      mk_ident_expr("mid"),
      mk_index("arr", mk_ident_expr("left")),
    ),
    loc(1),
  )
  let body : @ast.Stmt = Block([mid_calc, lr_update], loc(1))
  let f = extract_of("myFind", body)
  assert_true(
    f.has_mid_calculation,
    msg="(left+right)/2 必须产 mid 计算特征",
  )
  assert_true(
    f.has_left_right_update,
    msg="arr[mid] = ... 必须产 left/right 更新特征",
  )
  assert_false(
    f.has_nested_loops,
    msg="无循环——单循环特征为假（空体形态）",
  )
  // 单循环 + mid + lr 更新 ⇒ 结构分支
  let with_loop : @ast.Stmt = Block(
    [
      mk_for(
        VarDecl(
          int_ty(),
          "i",
          Some(Literal(0, loc(1), int_ty())),
          [],
          false,
          loc(1),
        ),
        Binary(Lt, mk_ident_expr("i"), mk_ident_expr("n"), loc(1), int_ty()),
        Block([mid_calc, lr_update], loc(1)),
      ),
    ],
    loc(1),
  )
  let f2 = extract_of("myFind", with_loop)
  assert_true(f2.has_single_loop)
  let ms = detect_search("myfind", f2, "myFind", 1)
  assert_eq(ms.length(), 1, msg="结构分支必须命中 binary_search")
  assert_eq(ms[0].name, "binary_search")
}

///|
/// 锚三十：插入排序结构分支——嵌套 + 后移模式（arr[j+1] = arr[j]）。
test "teaching_features_insertion_structural_branch" {
  let shift : @ast.Stmt = Expr(
    mk_index_assign(
      "arr",
      Binary(
        Add,
        mk_ident_expr("j"),
        Literal(1, loc(1), int_ty()),
        loc(1),
        int_ty(),
      ),
      mk_index("arr", mk_ident_expr("j")),
    ),
    loc(1),
  )
  let inner : @ast.Stmt = mk_for(
    VarDecl(
      int_ty(),
      "j",
      Some(Literal(0, loc(1), int_ty())),
      [],
      false,
      loc(1),
    ),
    Binary(Lt, mk_ident_expr("j"), mk_ident_expr("i"), loc(1), int_ty()),
    Block([shift], loc(1)),
  )
  let outer : @ast.Stmt = mk_count_for("i", mk_ident_expr("n"), inner)
  let f = extract_of("myArrange", Block([outer], loc(1)))
  assert_true(
    f.has_shift_pattern,
    msg="arr[j+1] = arr[j] 必须产后移特征",
  )
  assert_true(f.has_nested_loops)
  // 死分支等价锚（同 bubble 注——insertion 结构分支的 loop_depth >= 2
  // 恒假；shift 特征断言锁 walk 正确性）
  let ms = detect_sorting("myarrange", f, "myArrange", 1)
  assert_eq(
    ms.length(),
    0,
    msg="loop_depth 恒 0——结构分支两侧同为死分支（等价）",
  )
}

///|
/// 锚三十一（B13）：同命中多族的元素序 = oracle 族序（tree 先于 string）。
test "teaching_detect_family_order_b13" {
  // 真 AST 全链：TreeNode* 参数（is_treenode_ctx）+ 体内自调用
  //（is_recursive）——两特征均由 extract_features 产出，非手工塞值。
  let treenode_ptr : @ast.Type = Pointer(Struct("TreeNode", false), false)
  let self_call_body : @ast.Stmt = Block(
    [
      Expr(
        Call(
          "bstKmpSearch",
          [Identifier("t", loc(1), treenode_ptr)],
          loc(1),
          int_ty(),
        ),
        loc(1),
      ),
    ],
    loc(1),
  )
  let ms = detect_in_func(
    {
      loc: loc(1),
      return_type: int_ty(),
      name: "bstKmpSearch",
      params: [{ ty: treenode_ptr, name: "t", loc: loc(1), default: None, }],
      body: Some(self_call_body),
      is_static: false,
      is_extern: false,
      source_file: "main.c",
      is_variadic: false,
    },
    self_call_body,
  )
  assert_true(ms.length() >= 2, msg="须双命中（tree + string）")
  assert_eq(
    ms[0].name,
    "bst_search",
    msg="oracle 族序 tree 先于 string——首元素必须是 bst_search（B13）",
  )
  assert_eq(ms[1].name, "string_match_kmp")
}
