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
///（交换**主行**取 j=5 而非 first() 的 n 规模量）。PR #347 审阅 P2-c
/// 连坐翻案：判据 v2（左侧下标写）后暂存读行（`temp = arr[j];`——纯
/// 赋值单向读）不再标交换，落循环上下文；主行/回写行标交换。
test "semantic_swap_picks_inner_index" {
  let vars : Array[@protocol.ApiVariableSnapshot]? = Some([
    mkvar("n", "10"),
    mkvar("i", "2"),
    mkvar("j", "5"),
  ])
  // 交换主行：左侧下标写——内层下标 j=5 优先
  assert_eq(
    infer_semantic_label(7, vars, "main", "    arr[j] = arr[j + 1];", false),
    "交换 arr[5]↔arr[6]",
  )
  // 回写行：左侧下标写（暂存名无关）
  assert_eq(
    infer_semantic_label(8, vars, "main", "    arr[j + 1] = t;", false),
    "交换 arr[5]↔arr[6]",
  )
  // 暂存读行（v1 误报面）：不标交换，落循环上下文
  assert_eq(
    infer_semantic_label(9, vars, "main", "    temp = arr[j];", false),
    "循环 n=10, i=2, j=5",
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
  // 排除二：定义行（含 `fact(` 且行尾 { ——不是递归调用）。
  // #245（2026-10-22）翻转：定义行旧落 is_func_call 兜底「函数调用」
  //（正是本 issue 病），现独立标签「进入 fact」
  assert_eq(
    infer_semantic_label(1, none, "fact", "int fact(int n) {", false),
    "进入 fact",
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

///|
/// #220（2026-10-21 报）：for 语句语义标签误标「函数调用」——前缀排除
/// `has_prefix("for ")` 对 `for(int i=0;...)` **无空格形态**失配，行落
/// is_func_call → extract_called_func 抽不出 → 「函数调用」；行首**缩进**
/// 同样让全部关键字前缀排除失效（「调用 while」来源：缩进 while 行被
/// 当普通调用抽出 "while"）。
test "semantic_for_and_indented_while_not_func_call_220" {
  // for 无空格形态（vars 缺席的降级形态）——不得「函数调用」
  assert_eq(
    infer_semantic_label(4, None, "main", "for(int i = 0; i < 3; i++)", false),
    "循环",
  )
  // for 无空格形态（vars 在场：i=0 已初始化）——循环上下文
  assert_eq(
    infer_semantic_label(
      4,
      Some([mkvar("i", "0")]),
      "main",
      "for(int i = 0; i < 3; i++)",
      false,
    ),
    "循环 i=0",
  )
  // 缩进 while（关键字前有空格）——不得「调用 while」
  assert_eq(
    infer_semantic_label(6, None, "main", "  while (i < 3)", false),
    "循环",
  )
  // 缩进 for（双盲叠加：缩进 + 无空格）
  assert_eq(
    infer_semantic_label(
      4,
      None,
      "main",
      "    for(int i = 0; i < n; i++)",
      false,
    ),
    "循环",
  )
  // do-while 尾随形态（`} while (...)`）——前缀排除漏网后 extract 曾抽
  // 出 "while" 产出「调用 while」（issue 原报告 L6 形态）
  let dowhile = infer_semantic_label(
    6,
    Some([mkvar("i", "3")]),
    "main",
    "} while (i < 3);",
    false,
  )
  assert_true(
    dowhile != "调用 while",
    msg="do-while 尾不得标「调用 while」（得：\{dowhile}）",
  )
}

///|
/// #246 锚（2026-10-22，修复前证红）：下标内括号不是调用点——
/// `int p = arr[(0+1)/2];` 的 '(' 前是 '['（非标识符），旧判据
/// contains("(") 令 is_func_call 成立、extract 返 None 落兜底
///「函数调用」×每帧；修复后回落行号（声明语句的教学形态）。
test "semantic_index_paren_not_func_call" {
  // 简单下标对照（本来就不触发——#246 报告的对照组形态）
  assert_eq(
    infer_semantic_label(6, None, "main", "  int x = arr[0];", false),
    "第 6 行",
  )
  // 下标内含括号表达式：不得落「函数调用」
  assert_eq(
    infer_semantic_label(13, None, "main", "  int p = arr[(0+1)/2];", false),
    "第 13 行",
    msg="arr[(0+1)/2] 的 '(' 前是 '['——非调用点",
  )
}

///|
/// #245 锚（2026-10-22，修复前证红）：函数定义行/入口帧独立标签——
/// `int main() {`/`void defLine(void) {` 此前落 is_func_call 兜底
///「函数调用」（extract 对 "int main" 多词段返 None）；修复后标
///「进入 <名>」（#220 销案时上游明确留作未修的「另开单病」即本条）。
test "semantic_function_definition_entry_label" {
  assert_eq(
    infer_semantic_label(12, None, "main", "int main() {", false),
    "进入 main",
  )
  assert_eq(
    infer_semantic_label(5, None, "main", "void defLine(void) {", false),
    "进入 defLine",
  )
  // 对照：真调用行不受影响
  assert_eq(
    infer_semantic_label(20, None, "main", "  defLine();", false),
    "调用 defLine",
  )
}

///|
/// 审阅 P2-4 锚（2026-10-23）：#245/#246 的边界形态四例——
/// 指针/多词返回类型定义行、调用点空格形态、函数指针调用形态。
test "semantic_label_review_p24_edge_forms" {
  let none : Array[@protocol.ApiVariableSnapshot]? = None
  // 形态 1：char 返回类型的定义行
  let r1 = infer_semantic_label(5, none, "main", "char make(void) {", false)
  inspect(r1, content="进入 make")
  // 形态 2：static struct S 多词 + 指针返回类型定义行
  let r2 = infer_semantic_label(
    6, none, "main", "static struct S *f(void) {", false,
  )
  inspect(r2, content="进入 f")
  // 形态 3：调用点名字与括号间有空格（旧判据 contains("(") 可达）
  let r3 = infer_semantic_label(5, none, "main", "  defLine ();", false)
  inspect(r3, content="调用 defLine")
  // 形态 4：函数指针调用 (fp)(1);
  let r4 = infer_semantic_label(6, none, "main", "  (fp)(1);", false)
  inspect(r4, content="函数调用")
}

///|
/// PR #280 审阅 P2-3 锚（2026-10-23）：定义行「名字与括号间空白」——
/// `int main  (void) {` 学生常见书写形态，定义侧 paren 探测须与调用侧
/// 同跳空白（旧形态落 is_func_call 兜底「函数调用」）。
test "semantic_definition_name_space_before_paren" {
  assert_eq(
    infer_semantic_label(1, None, "main", "int main  (void) {", false),
    "进入 main",
  )
  assert_eq(
    infer_semantic_label(5, None, "main", "void defLine () {", false),
    "进入 defLine",
  )
  // 对照：调用侧同形态（P2-4 已锚）不受影响
  assert_eq(
    infer_semantic_label(9, None, "main", "  defLine ();", false),
    "调用 defLine",
  )
}
