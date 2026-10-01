// teaching/steps 白盒锚（S8 teaching 批一号，2026-10-01）：has_word
// 切分表（Rust features.rs tests 21 例照搬——U1#1 P0-1 连续大写缩写
// 修复的等价性表格化锚）+ sorting 判据双锚（Rust detector/sorting tests
// 同款）+ infer 语义锚 + parse_int/is_signature_line 边界。

///|
/// 锚一：has_word 等价性表（Rust has_word_segmentation_table 21 例逐条）。
test "teaching_has_word_segmentation_table" {
  let cases : Array[(String, String, Bool)] = [
    ("isValidBST", "bst", true),
    ("isValidBST", "valid", true),
    ("isValidBST", "is", true),
    ("isValidBST", "validb", false),
    ("BSTInsert", "bst", true),
    ("BSTInsert", "insert", true),
    ("BSTInsert", "bstinsert", false),
    ("getHTTPResponse", "http", true),
    ("getHTTPResponse", "response", true),
    ("getHTTPResponse", "get", true),
    ("getHTTPResponse", "ttp", false),
    ("subString", "bst", false),
    ("subString", "sub", true),
    ("subString", "string", true),
    ("bestEffort", "best", true),
    ("bestEffort", "effort", true),
    ("bestEffort", "bst", false),
    ("bst_insert", "bst", true),
    ("bst_insert", "insert", true),
    ("bst2insert", "insert", true),
    ("bst2insert", "bst", true),
  ]
  for c in cases {
    let (name, word, want) = c
    assert_eq(has_word(name, word), want, msg="has_word(\{name}, \{word})")
  }
}

///|
/// 锚二（U1#1 红锚③照搬）：insert_node 不误判插入排序。
test "teaching_detect_insert_node_not_insertion_sort" {
  let f = FuncFeatures::default()
  let m = detect_sorting("insert_node", f, "insert_node", 1)
  assert_eq(m.length(), 0, msg="insert_node 不应被判插入排序")
}

///|
/// 锚三（反向照搬）：标准命名仍识别插入排序。
test "teaching_detect_insertion_sort_names" {
  let f = FuncFeatures::default()
  for name in ["insertion_sort", "insertSort", "insert_sort"] {
    let m = detect_sorting(name.to_lower(), f, name, 1)
    let mut hit = false
    for x in m {
      if x.name == "insertion_sort" {
        hit = true
      }
    }
    assert_true(hit, msg="\{name} 应识别为插入排序")
  }
}

///|
/// 锚四：判据误判收紧双面——merge 整词 + sort 语境（mergeSortedLists
/// 的裸 merge 不命中；mergeSortA 命中）。
test "teaching_detect_merge_word_context" {
  let f = FuncFeatures::default()
  // 裸 merge（链表归并函数名）不判归并排序
  let m1 = detect_sorting("mergesortedlists", f, "mergeSortedLists", 1)
  assert_eq(m1.length(), 0, msg="mergeSortedLists 不应误判归并排序")
  // merge + sort 双词命中
  let m2 = detect_sorting("mergesorta", f, "mergeSortA", 1)
  let mut hit = false
  for x in m2 {
    if x.name == "merge_sort" {
      hit = true
    }
  }
  assert_true(hit, msg="mergeSortA 应识别归并排序")
}

///|
/// 锚五：infer 冒泡——外层趟文案（第 pass 趟 + 第 kth 大——概念教反
/// 修复的回归形态：pass == kth）。
fn mk_alg(name : String, display : String) -> @protocol.AlgorithmMatch {
  {
    name,
    display_name: display,
    func_name: "bubbleSort",
    confidence: 85,
    suggestion: "",
    line: 1,
    vis_events: [],
  }
}

///|
test "teaching_infer_bubble_outer_and_j_bound" {
  let alg = mk_alg("bubble_sort", "冒泡排序")
  // 外层 for（i 趟）——i=2, n=5：第 3 趟/第 3 大
  let r1 = infer_algorithm_step(
    10,
    [{ name: "i", value: "2", }, { name: "n", value: "5", }],
    "bubbleSort",
    "for (i = 0; i < n - 1; i++) {",
    Some(alg),
    {
      prev_vars: [],
      at_callee_entry: false,
      caller_is_main: false,
      lookahead: "",
    },
  )
  guard r1 is Some(s1) else { fail("外层趟必产步") }
  assert_eq(s1.phase, "outer_loop")
  assert_eq(
    s1.description,
    "第 3 趟：将第 3 大的元素放到正确位置",
  )
  // 交换行 j 越界拦截：i=0, n=5, j=4（退出值 = n-1-i=4 ⇒ j+1=5 越界）
  let r2 = infer_algorithm_step(
    12,
    [
      { name: "i", value: "0", },
      { name: "j", value: "4", },
      { name: "n", value: "5", },
    ],
    "bubbleSort",
    "temp = arr[j]; arr[j] = arr[j + 1];",
    Some(alg),
    {
      prev_vars: [],
      at_callee_entry: false,
      caller_is_main: false,
      lookahead: "",
    },
  )
  assert_true(
    r2 is None,
    msg="j=4（退出值）不得产出交换描述——arr[5] 越界",
  )
  // 合法 j：比较行
  let r3 = infer_algorithm_step(
    11,
    [
      { name: "i", value: "0", },
      { name: "j", value: "2", },
      { name: "n", value: "5", },
    ],
    "bubbleSort",
    "if (arr[j] > arr[j + 1]) {",
    Some(alg),
    {
      prev_vars: [],
      at_callee_entry: false,
      caller_is_main: false,
      lookahead: "",
    },
  )
  guard r3 is Some(s3) else { fail("合法 j 必产比较步") }
  assert_eq(s3.phase, "compare")
  assert_eq(s3.description, "比较 arr[2] 与 arr[3]")
}

///|
/// 锚六：infer 选择——minIdx 驼峰别名 + 越界守卫。
test "teaching_infer_selection_alias_and_guard" {
  let alg = mk_alg("selection_sort", "选择排序")
  // minIdx 别名（U1#1 P1-84）
  let r1 = infer_algorithm_step(
    10,
    [{ name: "j", value: "3", }, { name: "minIdx", value: "1", }],
    "selectionSort",
    "for (j = i + 1; j < n; j++) {",
    Some(alg),
    {
      prev_vars: [],
      at_callee_entry: false,
      caller_is_main: false,
      lookahead: "",
    },
  )
  guard r1 is Some(s1) else { fail("内层扫描必产步") }
  assert_eq(s1.description, "扫描 j=3，当前最小值在 min_idx=1")
  // 越界守卫：j=5=n（收尾帧）不产出比较
  let r2 = infer_algorithm_step(
    11,
    [
      { name: "j", value: "5", },
      { name: "n", value: "5", },
      { name: "min_idx", value: "2", },
    ],
    "selectionSort",
    "if (arr[j] < arr[min_idx]) {",
    Some(alg),
    {
      prev_vars: [],
      at_callee_entry: false,
      caller_is_main: false,
      lookahead: "",
    },
  )
  assert_true(r2 is None, msg="j==n 收尾帧不得产出比较描述")
}

///|
/// 锚七：infer 插入——写回形态收紧 + prev_vars 行入口兜底。
test "teaching_infer_insertion_writeback_and_prev_vars" {
  let alg = mk_alg("insertion_sort", "插入排序")
  // 写回行：arr[j + 1] = key（j 已作用域收回——prev_vars 兜底 j=1）
  let r = infer_algorithm_step(
    13,
    [{ name: "key", value: "7", }],
    "insertionSort",
    "arr[j + 1] = key;",
    Some(alg),
    {
      prev_vars: [{ name: "j", value: "1", }],
      at_callee_entry: false,
      caller_is_main: false,
      lookahead: "",
    },
  )
  guard r is Some(s) else { fail("写回行必产插入步") }
  assert_eq(s.phase, "insert")
  assert_eq(s.description, "将 key=7 插入到正确位置 2")
  // 读操作行（int key = arr[i];）不命中（U1#1 P1-60 收紧）
  let r2 = infer_algorithm_step(
    5,
    [{ name: "i", value: "3", }],
    "insertionSort",
    "int key = arr[i];",
    Some(alg),
    {
      prev_vars: [],
      at_callee_entry: false,
      caller_is_main: false,
      lookahead: "",
    },
  )
  assert_true(r2 is None, msg="声明读行不判插入")
}

///|
/// 锚八：infer 快排——caller_is_main 启动态 + 空区间递归基拦截。
test "teaching_infer_quick_sort_entry_and_base" {
  let alg = mk_alg("quick_sort", "快速排序")
  // callee entry + caller_is_main → 启动态
  let r1 = infer_algorithm_step(
    20,
    [{ name: "left", value: "0", }, { name: "right", value: "9", }],
    "quickSort",
    "quickSort(arr, 0, n - 1);",
    Some(alg),
    {
      prev_vars: [],
      at_callee_entry: true,
      caller_is_main: true,
      lookahead: "",
    },
  )
  guard r1 is Some(s1) else { fail("启动帧必产步") }
  assert_eq(
    s1.description,
    "启动快速排序：处理区间 [left=0, right=9]",
  )
  // 空区间递归基（left > right）不产出
  let r2 = infer_algorithm_step(
    20,
    [{ name: "left", value: "0", }, { name: "right", value: "-1", }],
    "quickSort",
    "quickSort(arr, left, pivot - 1);",
    Some(alg),
    {
      prev_vars: [],
      at_callee_entry: false,
      caller_is_main: true,
      lookahead: "",
    },
  )
  assert_true(r2 is None, msg="空区间帧不产出 recursive")
}

///|
/// 锚九：is_signature_line——定义行拦截 / 赋值行放行。
fn sig_line_probe(line : String) -> Bool {
  is_signature_line(line)
}

///|
test "teaching_signature_line_gate" {
  assert_true(sig_line_probe("int main() {"))
  assert_true(sig_line_probe("void quickSort(int arr[], int low, int high) {"))
  assert_false(sig_line_probe("int mid = (left + right) / 2;"))
  assert_false(sig_line_probe("  if (arr[j] > arr[j + 1]) {"))
}

///|
/// 锚十：parse_int 边界（正负号 / 空串 / 非数字 / 前导空白拒绝）。
test "teaching_parse_int_boundaries" {
  assert_true(parse_int("42") == Some(42))
  assert_true(parse_int("-7") == Some(-7))
  assert_true(parse_int("+9") == Some(9))
  assert_true(parse_int("") is None)
  assert_true(
    parse_int(" 3") is None,
    msg="Rust parse 不容忍空白——严格对齐",
  )
  assert_true(parse_int("3x") is None)
}

// ─────────────────────────────────────────────────────────────────────
// search + string 族锚（S8 teaching 批二号，2026-10-01）：binary_search
// 三红锚照搬（search.rs tests——U1#1 比较行短路修复 / narrow 差一修复 /
// mid_calc 反向）+ KMP nextval 语义（§6-7 两表优先序 + v5 ✗1 行文本
// 下标）+ 判据面。
// ─────────────────────────────────────────────────────────────────────

///|
fn mk_alg2(name : String, display : String) -> @protocol.AlgorithmMatch {
  {
    name,
    display_name: display,
    func_name: "binary_search",
    confidence: 90,
    suggestion: "",
    line: 1,
    vis_events: [],
  }
}

///|
fn empty_env() -> InferEnv {
  {
    prev_vars: [],
    at_callee_entry: false,
    caller_is_main: false,
    lookahead: "",
  }
}

///|
/// 锚十一（U1#1 红锚①照搬）：比较行不得被 mid_calc 短路。
test "teaching_infer_binary_compare_not_swallowed" {
  let alg = mk_alg2("binary_search", "二分查找")
  let vars : Array[VarSnapshot] = [
    { name: "left", value: "0", },
    { name: "right", value: "4", },
    { name: "mid", value: "2", },
    { name: "target", value: "7", },
  ]
  let r = infer_algorithm_step(
    5,
    vars,
    "binary_search",
    "if (a[mid] == target) return mid;",
    Some(alg),
    empty_env(),
  )
  guard r is Some(s) else { fail("比较行应有标注") }
  assert_eq(
    s.phase,
    "compare",
    msg="比较行应命中 compare 而非 mid_calc",
  )
  assert_true(s.description.contains("arr[2]"), msg="描述应含比较下标")
}

///|
/// 锚十二（U1#1 红锚②照搬）：narrow 打印实际边界值（差一修复——
/// right = mid - 1 执行后 right=1 而非 mid=2）。
test "teaching_infer_binary_narrow_actual_value" {
  let alg = mk_alg2("binary_search", "二分查找")
  let vars : Array[VarSnapshot] = [
    { name: "left", value: "0", },
    { name: "right", value: "1", },
    { name: "mid", value: "2", },
    { name: "target", value: "7", },
  ]
  let r = infer_algorithm_step(
    7,
    vars,
    "binary_search",
    "right = mid - 1;",
    Some(alg),
    empty_env(),
  )
  guard r is Some(s) else { fail("边界更新行应有标注") }
  assert_eq(s.phase, "narrow_left")
  assert_true(
    s.description.contains("right=1"),
    msg="应打印 right 实际值 1（mid=2 减一）而非 mid 本身",
  )
}

///|
/// 锚十三（反向照搬）：mid 计算行仍命中 mid_calc。
test "teaching_infer_binary_mid_calc_still" {
  let alg = mk_alg2("binary_search", "二分查找")
  let vars : Array[VarSnapshot] = [
    { name: "left", value: "0", },
    { name: "right", value: "4", },
    { name: "mid", value: "2", },
  ]
  let r = infer_algorithm_step(
    4,
    vars,
    "binary_search",
    "int mid = (left + right) / 2;",
    Some(alg),
    empty_env(),
  )
  guard r is Some(s) else { fail("mid 行应有标注") }
  assert_eq(s.phase, "mid_calc")
  assert_true(s.description.contains("mid=2"))
}

///|
/// 锚十四（§6-7 v4 #35）：nextval 行优先于 next 分支（两表词汇区分）；
/// v5 ✗1：下标从行文本解析（字面量 0 不被变量 j 污染）。
test "teaching_infer_kmp_nextval_priority_and_literal_idx" {
  let alg = mk_alg2("string_match_kmp", "KMP 模式匹配")
  let vars : Array[VarSnapshot] = [
    { name: "j", value: "-1", },
    { name: "k", value: "0", },
  ]
  let r = infer_algorithm_step(
    9,
    vars,
    "getNext",
    "nextval[0] = -1;",
    Some(alg),
    empty_env(),
  )
  guard r is Some(s) else { fail("nextval 行应有标注") }
  assert_eq(
    s.phase,
    "build_nextval",
    msg="两表优先序——nextval 不被 next 分支吞",
  )
  assert_eq(
    s.description,
    "构建 nextval 数组，nextval[0]=-1",
    msg="下标取行文本字面量 0（非 j 的 -1）、值取右侧字面量",
  )
}

///|
/// 锚十五（U1#1 P1-19/96）：getNext 调用点无数值（main 里的启动调用）。
test "teaching_infer_kmp_getnext_call_no_value" {
  let alg = mk_alg2("string_match_kmp", "KMP 模式匹配")
  let vars : Array[VarSnapshot] = [
    { name: "j", value: "3", },
    { name: "k", value: "2", },
  ]
  let r = infer_algorithm_step(
    20,
    vars,
    "getNext",
    "getNext(T, next);",
    Some(alg),
    empty_env(),
  )
  guard r is Some(s) else { fail("调用行应有标注") }
  assert_eq(s.phase, "build_next")
  assert_eq(
    s.description,
    "调用构建 next 数组",
    msg="调用点不带 j/k 数值（巧合域外值）",
  )
}

///|
/// 锚十六：search/string 判据面——binary 结构分支 + reverse/bf/kmp 命名。
test "teaching_detect_search_and_string" {
  let f = FuncFeatures::default()
  // binary 命中
  let m1 = detect_search("binarysearch", f, "binarySearch", 1)
  assert_eq(m1.length(), 1)
  assert_eq(m1[0].name, "binary_search")
  // reverse+str 命中；reverse 单词不命中（缺 str 语境）
  let m2 = detect_string("reversestring", "reverseString", 1)
  assert_eq(m2.length(), 1)
  assert_eq(m2[0].name, "string_reverse")
  let m3 = detect_string("reverselist", "reverseList", 1)
  assert_eq(m3.length(), 0, msg="无 str 语境不判字符串反转")
  // bf / kmp 命名族
  let m4 = detect_string("indexbf", "indexBF", 1)
  assert_eq(m4[0].name, "string_match_bf")
  let m5 = detect_string("getnext", "getNext", 1)
  assert_eq(m5[0].name, "string_match_kmp")
}

// ─────────────────────────────────────────────────────────────────────
// tree 族锚（S8 teaching 批三号，2026-10-01）：判据七锚照搬（detector/
// tree.rs tests——bst 家族双条件全套：isValidBST 方案②/裸命名 TreeNode
// 语境/无语境反锚/驼峰/无语义词/bstHeight 反例）+ infer 四锚照搬
//（tree.rs tests——validate 三 phase 锚定模板行 + delete 八行 phase 表）。
// ─────────────────────────────────────────────────────────────────────

///|
fn fnames(ms : Array[@protocol.AlgorithmMatch]) -> Array[String] {
  let out : Array[String] = []
  for m in ms {
    out.push(m.name)
  }
  out
}

///|
/// 锚十七（U1#1 P0-2 照搬）：hashTable 递归插入不误判 BST。
test "teaching_detect_hash_insert_not_bst" {
  let f = FuncFeatures::default()
  f.is_recursive = true
  let m = detect_tree("hashtable_insert", f, "hashTable", 1)
  assert_eq(m.length(), 0, msg="hashTable 插入不应被判 BST")
}

///|
/// 锚十八（照搬）：bst 命名仍识别 + 驼峰形态。
test "teaching_detect_bst_names_still" {
  let f = FuncFeatures::default()
  f.is_recursive = true
  let m1 = detect_tree("bst_insert", f, "bst_insert", 1)
  assert_true(fnames(m1).contains("bst_insert"))
  let m2 = detect_tree("bstinsert", f, "bstInsert", 1)
  assert_true(
    fnames(m2).contains("bst_insert"),
    msg="驼峰 bstInsert 应识别（整词匹配不因小写化丢驼峰边界）",
  )
}

///|
/// 锚十九（U1#1 复审补丁照搬）：subString 子串陷阱不命中 BST。
test "teaching_detect_substring_not_bst" {
  let f = FuncFeatures::default()
  let m = detect_tree("substring", f, "subString", 1)
  let names = fnames(m)
  assert_false(names.contains("bst_insert"))
  assert_false(names.contains("bst_search"))
}

///|
/// 锚二十（二审 P0-B 方案②照搬）：isValidBST 判校验不判插入。
test "teaching_detect_isvalidbst_as_validate" {
  let f = FuncFeatures::default()
  f.is_recursive = true
  let m = detect_tree("isvalidbst", f, "isValidBST", 1)
  let names = fnames(m)
  assert_true(
    names.contains("bst_validate"),
    msg="isValidBST 应判 bst_validate",
  )
  assert_false(names.contains("bst_insert"), msg="不得被判插入")
  assert_false(names.contains("bst_search"), msg="不得被判查找")
}

///|
/// 锚二十一（照搬）：无语义词的 bst 名字（bstHeight/bstTraverse）零匹配。
test "teaching_detect_bst_no_semantic_word_zero" {
  let f = FuncFeatures::default()
  f.is_recursive = true
  for name in ["bstHeight", "bstTraverse"] {
    let m = detect_tree(name.to_lower(), f, name, 1)
    assert_eq(m.length(), 0, msg="\{name} 无语义词不应命中 bst 家族")
  }
}

///|
/// 锚二十二（人审档 A 补齐照搬）：裸命名 + TreeNode 语境四形。
test "teaching_detect_bare_names_treenode_ctx" {
  // 裸 insert(TreeNode*) → bst_insert
  let insert_f = FuncFeatures::default()
  insert_f.is_treenode_ctx = true
  let m1 = detect_tree("insert", insert_f, "insert", 1)
  assert_true(fnames(m1).contains("bst_insert"))
  // 裸递归 search(TreeNode*) → bst_search
  let search_f = FuncFeatures::default()
  search_f.is_recursive = true
  search_f.is_treenode_ctx = true
  let m2 = detect_tree("search", search_f, "search", 1)
  assert_true(fnames(m2).contains("bst_search"))
  // 迭代 findMin 不判（递归条件）
  let find_min_f = FuncFeatures::default()
  find_min_f.is_treenode_ctx = true
  let m3 = detect_tree("findmin", find_min_f, "findMin", 1)
  assert_eq(m3.length(), 0, msg="迭代 findMin 不判 bst_search")
  // 裸 deleteNode(TreeNode*) → bst_delete
  let m4 = detect_tree("deletenode", find_min_f, "deleteNode", 1)
  assert_true(fnames(m4).contains("bst_delete"))
}

///|
/// 锚二十三（语境反锚照搬）：无 TreeNode 语境的裸命名拒绝。
test "teaching_detect_bare_names_no_ctx_rejected" {
  for name in ["insert", "search", "deleteNode"] {
    let f = FuncFeatures::default()
    f.is_recursive = true
    let m = detect_tree(name.to_lower(), f, name, 1)
    assert_eq(m.length(), 0, msg="\{name} 无 TreeNode 语境不应命中")
  }
}

///|
/// 锚二十四（二审 P0-B 方案②回归照搬）：validate 三 phase 落模板行。
test "teaching_infer_validate_phases_match_lines" {
  let alg : @protocol.AlgorithmMatch = {
    name: "bst_validate",
    display_name: "BST 合法性校验",
    func_name: "isValidBST",
    confidence: 85,
    suggestion: "",
    line: 19,
    vis_events: [],
  }
  let env = empty_env()
  let r1 = infer_algorithm_step(
    20,
    [],
    "isValidBST",
    "if (root == NULL) return 1;",
    Some(alg),
    env,
  )
  guard r1 is Some(s1) else { fail("空树判定行应标注") }
  assert_eq(s1.phase, "empty_valid")
  let r2 = infer_algorithm_step(
    21,
    [],
    "isValidBST",
    "if (root->val <= min || root->val >= max) return 0;",
    Some(alg),
    env,
  )
  guard r2 is Some(s2) else { fail("区间校验行应标注") }
  assert_eq(s2.phase, "range_check")
  let r3 = infer_algorithm_step(
    22,
    [],
    "isValidBST",
    "return isValidBST(root->left, min, root->val) &&",
    Some(alg),
    env,
  )
  guard r3 is Some(s3) else { fail("递归校验行应标注") }
  assert_eq(s3.phase, "recursive")
}

///|
/// 锚二十五（反向照搬）：普通比较行不判区间校验。
test "teaching_infer_validate_rejects_plain_compare" {
  let alg : @protocol.AlgorithmMatch = {
    name: "bst_validate",
    display_name: "BST 合法性校验",
    func_name: "isValidBST",
    confidence: 85,
    suggestion: "",
    line: 19,
    vis_events: [],
  }
  let r = infer_algorithm_step(
    10,
    [],
    "isValidBST",
    "if (val < root->val)",
    Some(alg),
    empty_env(),
  )
  assert_true(
    r is None,
    msg="无 min/max 界的普通比较不应判区间校验",
  )
}

///|
/// 锚二十六（照搬）：bst_delete 八行 phase 表。
test "teaching_infer_delete_phases_table" {
  let alg : @protocol.AlgorithmMatch = {
    name: "bst_delete",
    display_name: "BST 删除",
    func_name: "deleteNode",
    confidence: 85,
    suggestion: "",
    line: 32,
    vis_events: [],
  }
  let lines : Array[(String, String)] = [
    ("if (root == NULL) return NULL;", "not_found"),
    ("if (key < root->val)", "compare"),
    ("root->left = deleteNode(root->left, key);", "recursive"),
    ("if (root->left == NULL) {", "single_child"),
    ("free(root); return temp;", "free"),
    ("struct TreeNode* temp = findMin(root->right);", "find_successor"),
    ("root->val = temp->val;", "replace"),
    ("root->right = deleteNode(root->right, temp->val);", "recursive"),
  ]
  for c in lines {
    let (src, want) = c
    let r = infer_algorithm_step(
      32,
      [],
      "deleteNode",
      src,
      Some(alg),
      empty_env(),
    )
    guard r is Some(s) else { fail("该行应标注：\{src}") }
    assert_eq(s.phase, want, msg="行 `\{src}` 应为 \{want}")
  }
}

///|
/// 锚二十七（反向照搬）：bst_delete 无关行不标注。
test "teaching_infer_delete_rejects_unrelated" {
  let alg : @protocol.AlgorithmMatch = {
    name: "bst_delete",
    display_name: "BST 删除",
    func_name: "deleteNode",
    confidence: 85,
    suggestion: "",
    line: 32,
    vis_events: [],
  }
  for
    src in [
      "struct TreeNode* temp = root->right;", "return root;", "printf(\"%d \", root->val);",
    ] {
    let r = infer_algorithm_step(
      32,
      [],
      "deleteNode",
      src,
      Some(alg),
      empty_env(),
    )
    assert_true(r is None, msg="无关行不应标注：\{src}")
  }
}

///|
/// 锚二十八（U1#1 P0-2 照搬）：linearSearch（单循环）曾被 BFS 结构分支
/// 误判——"linear(linearSearch) → BFS 遍历完成"；收紧后命名主导不误判。
/// （Rust 锚的 cfg_has_back_edge 字段本侧 CFG 分叉恒默认——分叉登记见
/// moon.pkg 头注，锚取 has_single_loop 表达同款"带回边的单循环"。）
test "teaching_detect_linear_search_not_bfs" {
  let f = FuncFeatures::default()
  f.has_single_loop = true
  let m = detect_graph("linearsearch", f, "linearSearch", 1)
  let mut names = ""
  for x in m {
    names = "\{names} \{x.name}"
  }
  assert_eq(m.length(), 0, msg="linearSearch 不应被判 BFS:\{names}")
}

///|
/// 锚二十九（U1#1 P0-2 照搬）：递归 binarySearch 曾被 DFS 结构分支误判。
test "teaching_detect_recursive_binary_search_not_dfs" {
  let f = FuncFeatures::default()
  f.is_recursive = true
  let m = detect_graph("binarysearch", f, "binarySearch", 1)
  assert_eq(m.length(), 0, msg="递归 binarySearch 不应被判 DFS")
}

///|
/// 锚三十（反向照搬）：bfs/dfs 命名仍识别。
test "teaching_detect_graph_names_still_detected" {
  let f = FuncFeatures::default()
  let m1 = detect_graph("bfs", f, "bfs", 1)
  let mut hit1 = false
  for x in m1 {
    if x.name == "bfs" {
      hit1 = true
    }
  }
  assert_true(hit1, msg="bfs 应识别 BFS")
  let m2 = detect_graph("dfs_graph", f, "dfs_graph", 1)
  let mut hit2 = false
  for x in m2 {
    if x.name == "dfs" {
      hit2 = true
    }
  }
  assert_true(hit2, msg="dfs_graph 应识别 DFS")
}

///|
/// 锚三十一：graph 七算法命名正面覆盖（判据全分支 + display_name 逐条）。
test "teaching_detect_graph_all_seven" {
  let f = FuncFeatures::default()
  let cases : Array[(String, String, String)] = [
    ("bfs_traverse", "bfs", "BFS 广度优先搜索"),
    ("breadth_first", "bfs", "BFS 广度优先搜索"),
    ("depth_first", "dfs", "DFS 深度优先搜索"),
    ("prim_mst", "prim_mst", "Prim 最小生成树"),
    ("kruskal_mst", "kruskal_mst", "Kruskal 最小生成树"),
    ("dijkstra_sp", "dijkstra", "Dijkstra 最短路径"),
    ("floyd_warshall", "floyd", "Floyd 最短路径"),
    ("topological_sort", "topological_sort", "拓扑排序"),
  ]
  for c in cases {
    let (nm, want, display) = c
    let m = detect_graph(nm.to_lower(), f, nm, 1)
    let mut hit = false
    for x in m {
      if x.name == want {
        hit = true
        assert_eq(
          x.display_name,
          display,
          msg="\{nm} display_name 应为 \{display}",
        )
      }
    }
    assert_true(hit, msg="\{nm} 应识别 \{want}")
  }
}

///|
/// 锚三十二（U1#1 P0-1 复审照搬）：初始化行 `visited[v0] = 1;` 不得被判
/// "确认顶点"（u 未初始化哨兵 -1，实测输出"顶点 -1 的最短距离已确定"）。
test "teaching_infer_dijkstra_init_line_not_confirmed" {
  let alg = mk_alg("dijkstra", "Dijkstra 最短路径")
  let vars : Array[VarSnapshot] = [{ name: "u", value: "-1", }]
  let r = infer_algorithm_step(
    5,
    vars,
    "dijkstra",
    "visited[v0] = 1;",
    Some(alg),
    empty_env(),
  )
  // 照搬 oracle 断言语义：None 或文案不含 -1
  guard r is Some(step) else { return }
  assert_false(
    step.description.contains("-1"),
    msg="初始化行不应产出「顶点 -1 已确定」",
  )
}

///|
/// 锚三十三（反向照搬）：`visited[u] = 1;` 仍产出 confirm。
test "teaching_infer_dijkstra_visited_u_confirms" {
  let alg = mk_alg("dijkstra", "Dijkstra 最短路径")
  let vars : Array[VarSnapshot] = [{ name: "u", value: "1", }]
  let r = infer_algorithm_step(
    6,
    vars,
    "dijkstra",
    "visited[u] = 1;",
    Some(alg),
    empty_env(),
  )
  guard r is Some(step) else {
    fail("visited[u] 行应有标注")
    return
  }
  assert_eq(step.phase, "confirm", msg="phase 应为 confirm")
  assert_true(
    step.description.contains("顶点 1"),
    msg="文案应含「顶点 1」",
  )
}

///|
/// 锚三十四：infer BFS 六分支 phase 表（含 P1-6 起点入队文案区分）。
test "teaching_infer_bfs_phases_table" {
  let alg = mk_alg("bfs", "BFS 广度优先搜索")
  let vars : Array[VarSnapshot] = [
    { name: "u", value: "3", },
    { name: "front", value: "1", },
    { name: "rear", value: "5", },
  ]
  let cases : Array[(String, String)] = [
    ("while (front < rear) {", "loop"),
    ("int u = queue[front++];", "dequeue"),
    ("queue[rear++] = start;", "enqueue"),
    ("queue[rear++] = w;", "enqueue"),
    ("visited[u] = 1;", "visit"),
    ("return 0;", "finish"),
  ]
  for c in cases {
    let (src, phase) = c
    let r = infer_algorithm_step(
      7,
      vars,
      "bfsGraph",
      src,
      Some(alg),
      empty_env(),
    )
    guard r is Some(step) else {
      fail("BFS 行应有标注：\{src}")
      return
    }
    assert_eq(step.phase, phase, msg="\{src} phase 应为 \{phase}")
  }
  // 起点入队文案区分（P1-6）：start 版「起点入队」、邻居版「邻居节点入队」
  let r1 = infer_algorithm_step(
    7,
    vars,
    "bfsGraph",
    "queue[rear++] = start;",
    Some(alg),
    empty_env(),
  )
  guard r1 is Some(s1) else {
    fail("起点入队行应有标注")
    return
  }
  assert_eq(s1.description, "起点入队", msg="start 版文案")
  let r2 = infer_algorithm_step(
    7,
    vars,
    "bfsGraph",
    "queue[rear++] = w;",
    Some(alg),
    empty_env(),
  )
  guard r2 is Some(s2) else {
    fail("邻居入队行应有标注")
    return
  }
  assert_eq(s2.description, "邻居节点入队", msg="邻居版文案")
  // loop 文案实际值（front=1, rear=5）
  let r3 = infer_algorithm_step(
    7,
    vars,
    "bfsGraph",
    "while (front < rear) {",
    Some(alg),
    empty_env(),
  )
  guard r3 is Some(s3) else {
    fail("while 行应有标注")
    return
  }
  assert_eq(
    s3.description,
    "队列非空，继续广度优先搜索 [front=1, rear=5]",
    msg="loop 文案实际值",
  )
}

///|
/// 锚三十五：graph 其余六算法 phase 表（主分派臂接线覆盖——dfs 递归判定
/// 用原大小写行、prim P1-76 收紧、kruskal/dijkstra/floyd/topological 全
/// 分支）。
test "teaching_infer_graph_remaining_phases_table" {
  let k2 : Array[VarSnapshot] = [{ name: "k", value: "2", }]
  // (算法, 行, func_name, 期望 phase)
  let cases : Array[(String, String, String, String)] = [
    ("dfs", "dfsGraph(w, adj, visited);", "dfsGraph", "recursive"),
    ("dfs", "for (int i = 0; i < n; i++) {", "dfsGraph", "scan"),
    ("dfs", "return;", "dfsGraph", "finish"),
    ("prim_mst", "k = min_dist(lowcost, n, INF);", "primMst", "select_min"),
    ("prim_mst", "lowcost[k] = 0;", "primMst", "add_vertex"),
    ("prim_mst", "if (g[k][j] < lowcost[j]) {", "primMst", "update"),
    ("kruskal_mst", "return edges[i].w < edges[j].w;", "kruskal", "sort"),
    (
      "kruskal_mst", "if (find(parent, x) != find(parent, y)) {", "kruskal", "check_cycle",
    ),
    ("kruskal_mst", "union_parent(parent, x, y);", "kruskal", "add_edge"),
    ("dijkstra", "u = min_dist(dist, INF, visited, n);", "dijkstra", "select"),
    ("dijkstra", "if (dist[u] + g[u][j] < dist[j]) {", "dijkstra", "relax"),
    ("floyd", "for (k = 0; k < n; k++) {", "floyd", "outer_loop"),
    ("floyd", "if (g[i][k] + g[k][j] < g[i][j]) {", "floyd", "relax"),
    (
      "topological_sort", "if (indegree[i] == 0) queue[rear++] = i;", "topo", "enqueue",
    ),
    ("topological_sort", "printf(\"%d \", u);", "topo", "output"),
    ("topological_sort", "int u = queue[front++];", "topo", "dequeue"),
    ("topological_sort", "indegree[w]--;", "topo", "decrease"),
  ]
  for c in cases {
    let (alg_name, src, fname, phase) = c
    let r = infer_algorithm_step(
      9,
      k2,
      fname,
      src,
      Some(mk_alg(alg_name, alg_name)),
      empty_env(),
    )
    guard r is Some(step) else {
      fail("[\{alg_name}] 行应有标注：\{src}")
      return
    }
    assert_eq(
      step.phase,
      phase,
      msg="[\{alg_name}] \{src} phase 应为 \{phase}（实际 \{step.phase}）",
    )
  }
  // prim select_min 文案带 k 实际值（k=2）
  let r = infer_algorithm_step(
    9,
    k2,
    "primMst",
    "k = min_dist(lowcost, n, INF);",
    Some(mk_alg("prim_mst", "prim_mst")),
    empty_env(),
  )
  guard r is Some(step) else {
    fail("prim select_min 行应有标注")
    return
  }
  assert_eq(
    step.description,
    "选择最小边，顶点 k=2",
    msg="prim select_min 文案实际值",
  )
  // P1-76 收紧反向：初始化行 `lowcost[0] = 0;` 不产 add_vertex
  let r0 = infer_algorithm_step(
    9,
    k2,
    "primMst",
    "lowcost[0] = 0;",
    Some(mk_alg("prim_mst", "prim_mst")),
    empty_env(),
  )
  let bad = match r0 {
    None => false
    Some(step) => step.description.contains("-1")
  }
  assert_false(
    bad,
    msg="初始化行 lowcost[0]=0 不应产「顶点 -1 加入生成树」",
  )
}
