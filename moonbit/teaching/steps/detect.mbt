// teaching/steps·判据主口 + sorting 族（S8 teaching 批一号）：
// detect_algorithms / detect_in_func 照搬 algorithm_detector/mod.rs
//（批一号仅 sorting 臂——后续族随批逐个 extend）；sorting 判据照搬
// detector/sorting.rs:6-113（含 U1#1 P0-2 四处误判收紧的全部注释语义：
// select/merge 整词 + sort 语境、insertion 形态、贪心语境排除）。

///|
/// 检测程序中的所有算法模式（逐函数特征提取 + 各族判据）。
pub fn detect_algorithms(
  program : @ast.ProgramNode,
) -> Array[@protocol.AlgorithmMatch] {
  let matches : Array[@protocol.AlgorithmMatch] = []
  for func in program.funcs {
    match func.body {
      Some(body) =>
        for m in detect_in_func(func, body) {
          matches.push(m)
        }
      None => ()
    }
  }
  matches
}

///|
/// 单函数判据（特征提取 + 族分派——批一号仅 sorting；U1#1 P1-a 的 dp
/// 接线分支随 dp 族批）。
fn detect_in_func(
  func : @ast.FuncDecl,
  body : @ast.Stmt,
) -> Array[@protocol.AlgorithmMatch] {
  let features = extract_features(func, body)
  let name_lower = func.name.to_lower()
  let matches : Array[@protocol.AlgorithmMatch] = []
  // 族序 = oracle 次序（detector/mod.rs:35-41：sorting → search →
  // graph → tree → structures → string → math + dp 附加）——输出数组
  // 是对外面，序即契约（B13：同命中多族的输入两侧元素序必须一致，
  // bstKmpSearch 实测例在案）。43/43 七族全迁移（批六号收官——历史「42」系统计笔误）。
  for m in detect_sorting(name_lower, features, func.name, func.loc.line) {
    matches.push(m)
  }
  for m in detect_search(name_lower, features, func.name, func.loc.line) {
    matches.push(m)
  }
  for m in detect_graph(name_lower, features, func.name, func.loc.line) {
    matches.push(m)
  }
  for m in detect_tree(name_lower, features, func.name, func.loc.line) {
    matches.push(m)
  }
  for m in detect_structures(name_lower, features, func.name, func.loc.line) {
    matches.push(m)
  }
  for m in detect_string(name_lower, func.name, func.loc.line) {
    matches.push(m)
  }
  for m in detect_math(name_lower, features, func.name, func.loc.line) {
    matches.push(m)
  }
  // U1#1 P1-a：dp 检测接线——infer_dp 早已实现但检测器此前无 dp 分支
  //（孤儿，41 个 build_match 无一产出 dp）。dpFib/dpKnapsack/dpLCS/
  // dpLIS 的状态机都在 main 或独立函数里，以 `dp[` 状态表访问 + 循环
  // 为结构特征（Rust 手写 AlgorithmMatch 非 build_match——suggestion/
  // vis_events 恒空同形）。
  if features.has_dp_array &&
    (features.has_single_loop || features.has_nested_loops) {
    matches.push(
      build_match(
        "dp",
        "动态规划",
        func.name,
        func.loc.line,
        [],
        evidence="structure",
      ),
    )
  }
  matches
}

///|
/// sorting 族判据（九算法——命名分支 + 结构特征分支；收紧注释照搬）。
/// #224：各命中带判别依据（evidence：name=命名 / structure=结构特征），
/// 族尾互斥裁决（九算法教学互斥——命名证据优先，跨族共存不动 B13 契约）。
pub fn detect_sorting(
  name_lower : String,
  features : FuncFeatures,
  func_name : String,
  line : Int32,
) -> Array[@protocol.AlgorithmMatch] {
  let matches : Array[@protocol.AlgorithmMatch] = []
  // 冒泡排序
  let bubble_name = name_lower.contains("bubble")
  if bubble_name ||
    (
      features.has_nested_loops &&
      features.has_array_compare &&
      features.has_swap &&
      features.loop_depth >= 2 &&
      features.has_adjacent_index_compare
    ) {
    matches.push(
      build_match(
        "bubble_sort",
        "冒泡排序",
        func_name,
        line,
        features.compare_lines,
        evidence=if bubble_name { "name" } else { "structure" },
      ),
    )
  }
  // 选择排序（U1#1 P0-2 收紧：select 整词 + sort 语境；结构分支排除
  // huffman/activitySelection/replacementSelection 贪心与置换语境）
  let greedy_ctx = name_lower.contains("huffman") ||
    name_lower.contains("activity") ||
    name_lower.contains("replacement")
  let has_sort_word = has_word(func_name, "sort")
  let sel_name = (
      has_word(func_name, "select") || has_word(func_name, "selection")
    ) &&
    has_sort_word
  let sel_struct = !greedy_ctx &&
    features.has_nested_loops &&
    features.has_array_compare &&
    features.has_min_max_track &&
    features.loop_depth >= 2 &&
    !features.has_swap_in_inner_loop
  if sel_name || sel_struct {
    matches.push(
      build_match(
        "selection_sort",
        "选择排序",
        func_name,
        line,
        features.compare_lines,
        evidence=if sel_name { "name" } else { "structure" },
      ),
    )
  }
  // 插入排序（U1#1 修复：insertion / insert_sort / insertsort 形态——
  // insert_node 等子串不命中）
  let ins_name = name_lower.contains("insertion") ||
    name_lower.contains("insert_sort") ||
    name_lower.contains("insertsort")
  if ins_name ||
    (
      features.has_nested_loops &&
      features.has_shift_pattern &&
      features.loop_depth >= 2 &&
      !features.has_swap
    ) {
    matches.push(
      build_match(
        "insertion_sort",
        "插入排序",
        func_name,
        line,
        features.compare_lines,
        evidence=if ins_name { "name" } else { "structure" },
      ),
    )
  }
  // 快速排序
  let quick_name = name_lower.contains("quick")
  if quick_name ||
    (
      features.is_recursive &&
      features.has_partition_pattern &&
      features.has_nested_loops
    ) {
    matches.push(
      build_match(
        "quick_sort",
        "快速排序",
        func_name,
        line,
        features.compare_lines,
        evidence=if quick_name { "name" } else { "structure" },
      ),
    )
  }
  // 归并排序（U1#1 P0-2：merge 整词 + sort 语境——mergeSortedLists
  // 的链表归并函数不误判）
  let merge_name = has_word(func_name, "merge") && has_word(func_name, "sort")
  if merge_name ||
    (
      features.is_recursive &&
      features.has_merge_pattern &&
      !features.has_partition_pattern
    ) {
    matches.push(
      build_match(
        "merge_sort",
        "归并排序",
        func_name,
        line,
        features.compare_lines,
        evidence=if merge_name { "name" } else { "structure" },
      ),
    )
  }
  // 堆排序（#224 收紧：旧结构分支「递归 + 数组比较 + swap + 名字含
  // sort」是极宽兜底——教科书命名的 quickSort/mergeSort 全中四项，与
  // 真族并存交叉误命中〔confidence 双 85 + 完整错误教学文案 + 同一份
  // vis_events〕。改堆索引形态为排他证据：子索引 2*i+1/2*i+2 或建堆
  // 起点 n/2-1〔features.has_heap_index_pattern〕；递归条件同时去除
  // ——教科书 heapSort 主函数是迭代建堆，递归的是 heapify 辅助函数
  // 〔其命中走命名分支〕）
  let heap_name = name_lower.contains("heap")
  // 审阅 P1-3：三合取对真实代码不可达（建堆起点在 driver、子索引在
  // sift——证据天然跨函数；插桩：siftDown 有 compare+swap 无 heap_index
  // 〔修复 check_compare_expr 前〕、driver 有 heap_index 无 compare）。
  // 改 OR 链：堆索引形态为排他主证据，交换/数组比较任一佐证即可。
  let heap_struct = features.has_heap_index_pattern &&
    (features.has_swap || features.has_array_compare)
  if heap_name || heap_struct {
    matches.push(
      build_match(
        "heap_sort",
        "堆排序",
        func_name,
        line,
        features.compare_lines,
        evidence=if heap_name { "name" } else { "structure" },
      ),
    )
  }
  // 希尔排序
  if name_lower.contains("shell") {
    matches.push(
      build_match(
        "shell_sort",
        "希尔排序",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // 计数排序
  if name_lower.contains("counting") {
    matches.push(
      build_match(
        "counting_sort",
        "计数排序",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  // 基数排序
  if name_lower.contains("radix") {
    matches.push(
      build_match(
        "radix_sort",
        "基数排序",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  adjudicate_sorting(matches)
}

///|
/// sorting 族内互斥裁决（#224）：九排序算法教学互斥——同一函数多命中
/// 只保留一条：命名证据（evidence="name"）优先于结构证据，同证据按
/// 族序（push 序 = oracle 族序）首中。跨族（sorting×search×graph…）
/// 共存是 B13 契约内合法形态，不在此裁决。
fn adjudicate_sorting(
  matches : Array[@protocol.AlgorithmMatch],
) -> Array[@protocol.AlgorithmMatch] {
  if matches.length() <= 1 {
    return matches
  }
  for m in matches {
    if m.evidence == "name" {
      return [m]
    }
  }
  [matches[0]]
}
