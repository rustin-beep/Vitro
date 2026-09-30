///| L9 time_travel·**语义分类器锚族**（S8 批一号三段-b，2026-10-01）——
/// infer_semantic_label 是全库唯一分类器（R3 单源），判定**顺序敏感**
/// （Rust collector.rs:405-412 修订注释照搬：具体语句模式优先于循环上下
/// 文——旧序致循环后的 printf/free/return 全被标"循环 i=3"的实测缺陷）。
/// 本锚族锁判定顺序契约与各词汇分支；纯函数形态（源码行文本直传）。

///|
fn mkvar(name : String, value : String) -> @protocol.ApiVariableSnapshot {
  { name, addr: 0U, is_local: true, ty_name: "int", value, }
}

///|
/// 锚一：判定顺序契约——循环变量在作用域内（loop_depth≥1）时，具体
/// 语句模式仍优先（printf/return/释放内存先判；都判不出才回落循环
/// 上下文）。旧序缺陷形态：`return 0;` 位于循环后被标"循环 i=3"。
test "semantic_order_specific_before_loop_context" {
  let vars : Array[@protocol.ApiVariableSnapshot]? = Some([mkvar("i", "3")])
  // return 优先于循环上下文
  assert_eq(
    infer_semantic_label(9, vars, "main", "    return 0;", false),
    "返回",
  )
  // printf 优先
  assert_eq(
    infer_semantic_label(9, vars, "main", "  printf(\"%d\", i);", false),
    "调用 printf",
  )
  // 释放内存优先
  assert_eq(
    infer_semantic_label(9, vars, "main", "  free(p);", false),
    "释放内存",
  )
  // 都判不出 → 循环上下文回落（教学价值最高的"循环体内普通语句"）
  assert_eq(
    infer_semantic_label(9, vars, "main", "  sum = sum + a[i];", false),
    "循环 i=3",
  )
  // 兜底：行号
  assert_eq(
    infer_semantic_label(12, Some([]), "main", "  int x;", false),
    "第 12 行",
  )
}

///|
/// 锚二：交换分支 + P0-3 内层下标——源码行下标标识符优先于白名单序
/// （`temp = arr[j];` 取 j=5 而非 first() 的 n 规模量）。
test "semantic_swap_picks_inner_index" {
  let vars : Array[@protocol.ApiVariableSnapshot]? = Some([
    mkvar("n", "10"),
    mkvar("i", "2"),
    mkvar("j", "5"),
  ])
  assert_eq(
    infer_semantic_label(7, vars, "main", "    temp = arr[j];", false),
    "交换 arr[5]↔arr[6]",
  )
}

///|
/// 锚三：递归分支两排除——callee 入口首步（行归因调用点，S3 观测 #3）
/// 与函数定义行（`int helper(int x) {` 不是递归调用——直接呈现给学生
/// 的错误描述形态）。
test "semantic_recursive_exclusions" {
  let none : Array[@protocol.ApiVariableSnapshot]? = None
  // 真递归：函数体内调用自身
  assert_eq(
    infer_semantic_label(5, none, "fact", "  return fact(n - 1);", false),
    "递归调用 fact",
  )
  // 排除一：callee 入口首步（行=调用点行 `fact(3);`——非递归）
  assert_eq(
    infer_semantic_label(3, none, "fact", "  fact(3);", true),
    "调用 fact",
  )
  // 排除二：定义行（含 `fact(` 且行尾 { ——不是递归调用）
  assert_eq(
    infer_semantic_label(1, none, "fact", "int fact(int n) {", false),
    "函数调用",
  )
}

///|
/// 锚四：降级形态（local_vars=None——检查点保存路径）——同词汇表同
/// 顺序，值敏感分支退化为行首形态（循环行首直接判"循环"）。
test "semantic_degraded_loop_headline" {
  let none : Array[@protocol.ApiVariableSnapshot]? = None
  assert_eq(
    infer_semantic_label(4, none, "main", "  for (i = 0; i < n; i++) {", false),
    "循环",
  )
  // 降级形态下 swap 不触发（loop_depth=0——值敏感分支退化）
  assert_eq(
    infer_semantic_label(4, none, "main", "  temp = arr[j];", false),
    "第 4 行",
  )
}

///|
/// 锚五：词汇分支剩余面——内存分配 / IO / qsort / scanf / 非循环变量
/// 不入白名单 / 负值循环变量。
test "semantic_vocab_branches" {
  let none : Array[@protocol.ApiVariableSnapshot]? = None
  assert_eq(
    infer_semantic_label(3, none, "main", "  p = malloc(16);", false),
    "内存分配",
  )
  assert_eq(
    infer_semantic_label(3, none, "main", "  c = getchar();", false),
    "IO 操作",
  )
  assert_eq(
    infer_semantic_label(3, none, "main", "  qsort(a, n, 4, cmp);", false),
    "调用 qsort",
  )
  assert_eq(
    infer_semantic_label(3, none, "main", "  scanf(\"%d\", &x);", false),
    "调用 scanf",
  )
  // 非循环变量名不入白名单（x 不是 i/j/k/...）——不产生循环上下文
  let vars : Array[@protocol.ApiVariableSnapshot]? = Some([mkvar("x", "5")])
  assert_eq(
    infer_semantic_label(8, vars, "main", "  x = x + 1;", false),
    "第 8 行",
  )
  // 负值循环变量（j=-2——合法 i32 域）
  let neg : Array[@protocol.ApiVariableSnapshot]? = Some([mkvar("j", "-2")])
  assert_eq(
    infer_semantic_label(8, neg, "main", "  s = s + 1;", false),
    "循环 j=-2",
  )
}

///|
/// 锚六：extract_called_func——赋值跳过（"x = foo(...)" → foo）与
/// 非标识符名拒绝。
test "semantic_extract_called_func" {
  assert_eq(extract_called_func("  foo(bar, baz)"), Some("foo"))
  assert_eq(extract_called_func("  x = foo(1)"), Some("foo"))
  assert_eq(extract_called_func("  x = "), None)
  assert_eq(extract_called_func("  (a + b)(c)"), None)
}

///|
/// 锚七：parse_addr 两形态 + 拒绝面。
test "semantic_parse_addr" {
  assert_eq(parse_addr("0x1234"), Some(0x1234U))
  assert_eq(parse_addr("0XAB"), Some(0xABU))
  assert_eq(parse_addr("4660"), Some(4660U))
  assert_eq(parse_addr("-1"), None)
  assert_eq(parse_addr("xyz"), None)
  assert_eq(parse_addr(""), None)
}

///|
/// 锚八：trim_trailing_zeros——"1.500"→"1.5"、"2.0"→"2"、纯整数串不动
/// （"20" 不被剪成 "2"）。
test "semantic_trim_trailing_zeros" {
  assert_eq(trim_trailing_zeros("1.500"), "1.5")
  assert_eq(trim_trailing_zeros("2.0"), "2")
  assert_eq(trim_trailing_zeros("3.000"), "3")
  assert_eq(trim_trailing_zeros("20"), "20")
  assert_eq(trim_trailing_zeros("1.501"), "1.501")
}
