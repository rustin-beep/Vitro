///|
/// 诊断教学域**黑盒契约**（`vitro/engine/diagnostics` 的对外面）。
///
/// 主体 = Rust oracle 单测照搬（knowledge_graph.rs 4 锚 /
/// misconception_patterns.rs 4 锚 / learning_path.rs 2 锚 / E-P1-6
/// apply_fix 中文行 3 条回归），另补 generate_fix 行为锚（Rust 侧
/// error_catalog 0 单测——行为锁为对拍前置）。pub 面以 `@diagnostics.`
/// 形式点名（喂 moonbit_surface 消费面闸）。

// ============ M5 graph（knowledge_graph.rs tests 照搬） ============

test "graph_activate_from_error_bounds" {
  // Rust test_activate_from_error_bounds 照搬
  let activated = @diagnostics.activate_from_error(3051)
  assert_false(activated.is_empty())
  let mut has_boundary = false
  for a in activated {
    if a.node.id == "BoundaryCondition" {
      has_boundary = true
    }
  }
  assert_true(has_boundary)
}

///|
test "graph_activate_from_ast_malloc" {
  // Rust test_activate_from_ast_malloc 照搬
  let activated = @diagnostics.activate_from_ast(["malloc", "free"])
  let mut has_heap = false
  let mut has_ptr = false
  for a in activated {
    if a.node.id == "HeapMemory" {
      has_heap = true
    }
    if a.node.id == "Pointer" {
      has_ptr = true
    }
  }
  assert_true(has_heap)
  assert_true(has_ptr)
}

///|
test "graph_prerequisite_path" {
  // Rust test_prerequisite_path 照搬 + 序列序锁定（DFS 后序 =
  // EDGES 声明序下钻——对拍「序列逐项等价」判据的单元级前置）
  let path = @diagnostics.find_prerequisite_path("ImplicitCast")
  let ids : Array[String] = []
  for n in path {
    ids.push(n.id)
  }
  inspect(ids, content="[VarDecl, TypeSystem, ImplicitCast]")
}

///|
test "graph_nodes_count" {
  // Rust test_get_all_nodes 为 >=20；生成器基线已锁 25——锚强化为 ==
  assert_eq(@diagnostics.concept_nodes().length(), 25)
  assert_eq(@diagnostics.concept_edges().length(), 25)
  // ERROR_CONCEPT_MAP 基线（含 3020→Recursion 存量语义错照搬——分叉登记）
  assert_eq(@diagnostics.error_concept_map().get(3020), Some(["Recursion"]))
  assert_eq(
    @diagnostics.error_concept_map().get(3051),
    Some(["BoundaryCondition", "Array"]),
  )
}

// ============ M3 misconception（misconception_patterns.rs tests 照搬） ============

///|
fn make_record(
  codes : Array[Int],
  trap : String?,
) -> @diagnostics.CompileRecord {
  @diagnostics.CompileRecord::{
    timestamp_ms: 0L,
    success: codes.is_empty(),
    error_codes: codes,
    trap_message: trap,
  }
}

///|
test "miscon_detect_m01_boundary_confusion" {
  // Rust test_detect_m01_boundary_confusion 照搬
  let history = [
    make_record([3051], None),
    make_record([3021], None),
    make_record([3051], None),
    make_record([], None),
  ]
  let detected = @diagnostics.detect_misconceptions(history)
  assert_eq(detected.length(), 1)
  assert_eq(detected[0].pattern_id, "M01")
  assert_eq(detected[0].occurrence_count, 3)
  inspect(detected[0].confidence, content="0.75")
}

///|
test "miscon_detect_m03_assignment_in_condition" {
  // Rust test_detect_m03_assignment_in_condition 照搬
  let history = [
    make_record([3050], None),
    make_record([3050], None),
    make_record([3050], None),
  ]
  let detected = @diagnostics.detect_misconceptions(history)
  assert_eq(detected.length(), 1)
  assert_eq(detected[0].pattern_id, "M03")
}

///|
test "miscon_detect_m05_stack_overflow_by_trap" {
  // Rust test_detect_m05_stack_overflow_by_trap 照搬（中文/英文 trap 双关键词）
  let history = [
    make_record([], Some("栈溢出：调用栈深度超过限制")),
    make_record([], Some("Stack overflow detected")),
  ]
  let detected = @diagnostics.detect_misconceptions(history)
  let mut has_m05 = false
  for d in detected {
    if d.pattern_id == "M05" {
      has_m05 = true
    }
  }
  assert_true(has_m05)
}

///|
test "miscon_no_detection_below_threshold" {
  // Rust test_no_detection_below_threshold 照搬
  let history = [make_record([3051], None), make_record([], None)]
  let detected = @diagnostics.detect_misconceptions(history)
  assert_true(detected.is_empty())
}

// ============ M4 learning_path（learning_path.rs tests 照搬） ============

///|
test "path_recommend_m01" {
  // Rust test_recommend_m01 照搬
  let detected = [
    @diagnostics.DetectedMisconception::{
      pattern_id: "M01",
      pattern_name: "边界混淆",
      description: "",
      occurrence_count: 3,
      confidence: 0.75,
    },
  ]
  let paths = @diagnostics.recommend_learning_paths(detected)
  assert_eq(paths.length(), 1)
  assert_eq(paths[0].target_misconception_id, "M01")
  assert_eq(paths[0].target_misconception_name, "边界混淆")
  assert_eq(paths[0].steps.length(), 3)
  assert_eq(paths[0].steps[0].step_type, "ReadKnowledgeCard")
  assert_eq(paths[0].steps[1].step_type, "StudyTemplate")
}

///|
test "path_recommend_empty" {
  // Rust test_recommend_empty 照搬
  let paths = @diagnostics.recommend_learning_paths([])
  assert_true(paths.is_empty())
}

// ============ M2 apply_fix（E-P1-6 中文行回归，crash_regression_tests.rs:460 照搬） ============

///|
fn make_fix_target(
  start_col : Int,
  end_col : Int,
  text : String,
) -> @diagnostics.FixTarget {
  @diagnostics.FixTarget::{
    fix_kind: 1, // ReplaceText
    replace_start_line: 1,
    replace_start_column: start_col,
    replace_end_line: 1,
    replace_end_column: end_col,
    replacement_text: text,
  }
}

///|
test "autofix_chinese_line_byte_boundary_valid" {
  // Rust 原断言 is_some；本侧加全文锁（safe_byte_col 语义：col 6 非标量
  // 边界 → 回退标量序第 6 个「变」字节位 10；col 9 同理 → 17；
  // [10,17) = "变量 " 段替换）
  let source = "int 中文变量 = 1;"
  let r = @diagnostics.apply_fix(source, make_fix_target(6, 9, "X"))
  inspect(r, content="Some(int 中文X= 1;)")
}

///|
test "autofix_chinese_line_mid_char_fallback" {
  // 列 3（"int " 空格位，合法边界）到列 9（回退 17）：[3,17) 整段替换
  let source = "int 中文变量 = 1;"
  let r = @diagnostics.apply_fix(source, make_fix_target(3, 9, "X"))
  inspect(r, content="Some(intX= 1;)")
}

///|
test "autofix_chinese_line_char_semantic_cols" {
  // 列 4/10 双双为合法字节边界（「中」/「变」起点）：[4,10) = 中文
  let source = "int 中文变量 = 1;"
  let r = @diagnostics.apply_fix(source, make_fix_target(4, 10, "X"))
  inspect(r, content="Some(int X变量 = 1;)")
}

// ============ M1 generate_fix 行为锚（Rust 侧 0 单测——对拍前置行为锁） ============

///|
test "fixgen_line_end_payload_1002" {
  // 静态载荷 LineEnd 形态：坐标 = (line, trimmed_len) ×2，text = 引号
  let out = @diagnostics.generate_fix(1002, 1, 10, "", ["int s = \"abc"])
  inspect(
    out.suggestion,
    content="字符串引号未闭合，建议在行末添加双引号",
  )
  inspect(out.fix_kind, content="2")
  inspect(out.start_line, content="1")
  inspect(out.start_col, content="12") // "int s = \"abc" = 12 字节（无尾空白）
  inspect(out.end_col, content="12")
  inspect(out.text, content="\"")
}

///|
test "fixgen_manual_payload_3023" {
  let out = @diagnostics.generate_fix(3023, 2, 5, "未声明", ["int x;"])
  inspect(out.fix_kind, content="4")
  inspect(out.start_line, content="0")
  inspect(out.text, content="")
}

///|
test "fixgen_3050_assign_in_condition" {
  // "if (a = b)"：'=' 字节位 6，孤立（prev ' ' / next ' '）→ Replace ==
  let out = @diagnostics.generate_fix(3050, 1, 9, "", ["if (a = b)"])
  inspect(out.fix_kind, content="1")
  inspect(out.start_col, content="6")
  inspect(out.end_col, content="7")
  inspect(out.text, content="==")
}

///|
test "fixgen_3050_no_equals_fallback_manual" {
  // 行内无孤立 = → manual 降级文案
  let out = @diagnostics.generate_fix(3050, 1, 9, "", ["if (a == b)"])
  inspect(out.fix_kind, content="4")
  inspect(out.start_line, content="0")
}

///|
test "fixgen_3051_off_by_one" {
  // "for(i=0;i<=n;i++)"：首现 "<=" 字节位 9 → (9,11) 替换为 "<"
  let out = @diagnostics.generate_fix(3051, 1, 9, "", ["for(i=0;i<=n;i++)"])
  inspect(out.fix_kind, content="1")
  inspect(out.start_col, content="9")
  inspect(out.end_col, content="11")
  inspect(out.text, content="<")
}

///|
test "fixgen_3035_message_branch" {
  // 消息分支：含 "&"/"指针" → 取地址文案；否则类型不匹配文案
  let a = @diagnostics.generate_fix(
    3035,
    3,
    8,
    "scanf 参数需要 int* 指针",
    [""],
  )
  inspect(
    a.suggestion,
    content="scanf 参数需要传入变量的地址，建议在变量名前添加 '&'",
  )
  let b = @diagnostics.generate_fix(3035, 3, 8, "类型不匹配", [""])
  inspect(
    b.suggestion,
    content="scanf 参数类型不匹配，请检查格式符与变量类型",
  )
}

///|
test "fixgen_1004_pipe_rewrite" {
  // "if (a | b)"：错误列 8（col0=7）回搜 3 字节命中 '|'（字节位 6）→ ||
  let out = @diagnostics.generate_fix(1004, 1, 8, "", ["if (a | b)"])
  inspect(out.fix_kind, content="1")
  inspect(out.start_col, content="5")
  inspect(out.end_col, content="6")
  inspect(out.text, content="||")
}

///|
test "fixgen_default_no_fix" {
  // 无载荷无机制的码 → 空七元组
  let out = @diagnostics.generate_fix(9999, 1, 1, "", ["int x;"])
  inspect(out.suggestion, content="")
  inspect(out.fix_kind, content="0")
  inspect(out.text, content="")
}

// ============ 数据表出口点名（生成物 pub 面——喂 surface 消费闸） ============

///|
test "data_table_surface" {
  // fix_payload：静态载荷查询口（1002 命中 / 9999 落空）
  let p = @diagnostics.fix_payload(1002)
  assert_true(p is Some(_))
  assert_true(@diagnostics.fix_payload(9999) is None)
  // default_patterns：六模式出口（基线 6——生成器锁定的另一面）
  assert_eq(@diagnostics.default_patterns().length(), 6)
  // default_paths：六路径出口（键域 M01..M06）
  assert_eq(@diagnostics.default_paths().length(), 6)
  assert_true(@diagnostics.default_paths().contains("M06"))
}

// ============ F7 锚盲区补断言（审阅 2026-10-02） ============

///|
test "graph_neighbor_prerequisite_flag" {
  // is_prerequisite 反向边旗标：3004 → TypeSystem，其邻居 VarDecl 经
  // Prerequisite 边（VarDecl→TypeSystem）指向 TypeSystem → true；
  // ImplicitCast 邻居 TypeSystem 是 LeadsTo 正向 → false
  let activated = @diagnostics.activate_from_error(3004)
  assert_eq(activated.length(), 2)
  let mut var_decl_flag : Bool? = None
  for a in activated {
    if a.node.id == "TypeSystem" {
      for n in a.neighbors {
        if n.node.id == "VarDecl" {
          var_decl_flag = Some(n.is_prerequisite)
        }
      }
    }
  }
  assert_eq(var_decl_flag, Some(true))
}

///|
test "path_minutes_asserted" {
  // estimated_time_minutes（表值 10——恒 0 突变此前无断言）
  let paths = @diagnostics.recommend_learning_paths([
    @diagnostics.DetectedMisconception::{
      pattern_id: "M01",
      pattern_name: "边界混淆",
      description: "",
      occurrence_count: 3,
      confidence: 0.75,
    },
  ])
  assert_eq(paths[0].estimated_time_minutes, 10)
}

///|
test "graph_ast_struct_member_mapping" {
  // struct_member | "." | "->" → StructLayout（映射清空突变此前无断言）
  let activated = @diagnostics.activate_from_ast(["struct_member", "->", "."])
  assert_eq(activated.length(), 1) // 三特征同概念去重
  assert_eq(activated[0].node.id, "StructLayout")
  assert_eq(activated[0].activated_by, "AST")
}

///|
test "miscon_confidence_f32_semantics" {
  // F6：非十进制比值的 f32 语义化（2/3 = M02 命中 2/3 条；3/7 = M04 命中 3/7 条）
  let h23 = [
    make_record([3035], None),
    make_record([3035], None),
    make_record([1000], None),
  ]
  let d1 = @diagnostics.detect_misconceptions(h23)
  assert_eq(d1.length(), 1)
  inspect(d1[0].confidence, content="0.6666666865348816")
  let h37 = [
    make_record([3045], None),
    make_record([1000], None),
    make_record([3045], None),
    make_record([1000], None),
    make_record([1000], None),
    make_record([3052], None),
    make_record([1000], None),
  ]
  let d2 = @diagnostics.detect_misconceptions(h37)
  assert_eq(d2.length(), 1)
  inspect(d2[0].confidence, content="0.4285714328289032")
}
