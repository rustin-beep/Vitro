// issue #224 / #225 锚（2026-10-23 B 线批二）：
// #224 排序族判据交叉误命中——quickSort/mergeSort 被堆排序宽兜底
//（递归+数组比较+swap+名字含 sort）同时命中（confidence 双 85 + 错误
// 教学文案）；修复=堆排序结构分支收紧为堆索引形态证据 + sorting 族内
// 互斥裁决（命名证据优先）。以下三锚先红后绿（J9）。
// #225 infer 层行为锚——j 值动态文案（issue 报「只标 j=0」形态的
// HEAD 复核锚：j=1/j=2 的 if 比较行均产出 compare）。

///|
/// 锚一（#224 红锚①）：quickSort 形态（递归+数组比较+swap+名字含
/// sort、无堆索引）——旧堆排序宽兜底令其与 quick_sort 双命中；期望
/// 唯一 quick_sort。
test "issue224_quick_sort_shape_no_heap_crossmatch" {
  let f = FuncFeatures::default()
  f.is_recursive = true
  f.has_array_compare = true
  f.has_swap = true
  let m = detect_sorting("quicksort", f, "quickSort", 1)
  assert_eq(
    m.length(),
    1,
    msg="quickSort 形态应唯一命中（双命中=交叉误命中）",
  )
  assert_eq(m[0].name, "quick_sort", msg="唯一命中应为 quick_sort")
  assert_eq(m[0].evidence, "name", msg="命中 quick 字样=命名证据")
}

///|
/// 锚二（#224 红锚②）：堆形态结构分支——迭代建堆（堆子索引 2*i+1/
/// 2*i+2 + 交换 + 数组比较、函数名不含 heap、非递归）。旧判据要求
/// is_recursive + 名字含 sort ⇒ 教科书 heapSort 主函数（迭代、名字
/// 含 sort 但被递归条件排除）落空；新结构分支以堆索引为证据应命中。
test "issue224_heap_structure_shape_detected" {
  let f = FuncFeatures::default()
  f.has_array_compare = true
  f.has_swap = true
  f.has_heap_index_pattern = true
  let m = detect_sorting("my_sort", f, "mySort", 1)
  let mut hit = false
  for x in m {
    if x.name == "heap_sort" {
      hit = true
    }
  }
  assert_true(
    hit,
    msg="堆索引形态（无名无递归）应结构命中 heap_sort",
  )
}

///|
/// 锚三（#224 红锚③，互斥裁决）：名字含 quick + 同时满足堆结构特征
///（含堆索引）——sorting 九算法教学互斥，命名证据优先于结构证据，
/// 期望唯一 quick_sort。
test "issue224_sorting_exclusive_name_over_structure" {
  let f = FuncFeatures::default()
  f.is_recursive = true
  f.has_array_compare = true
  f.has_swap = true
  f.has_heap_index_pattern = true
  let m = detect_sorting("quicksort", f, "quickSort", 1)
  assert_eq(
    m.length(),
    1,
    msg="sorting 族内命名证据应裁决结构证据",
  )
  assert_eq(
    m[0].name,
    "quick_sort",
    msg="命名命中的 quick_sort 唯一保留",
  )
}

///|
/// 锚五（#224 infer 垃圾区间降级）：callee 入口首帧形参未落局部
///（left/right 读不到）——「启动快速排序」不得拼出 [left=-1, right=-1]
/// 垃圾值（issue 实锤形态），降级为不带数字的启动文案。
test "issue224_quick_start_no_garbage_range" {
  let alg : @protocol.AlgorithmMatch = {
    name: "quick_sort",
    display_name: "快速排序",
    func_name: "quickSort",
    confidence: 85,
    suggestion: "",
    line: 3,
    vis_events: [],
    evidence: "name",
  }
  // 无 left/right/i/pivot 局部（入口首帧形态）；source_line = main 调用行
  let env : InferEnv = {
    prev_vars: [],
    at_callee_entry: true,
    caller_is_main: true,
    lookahead: "",
  }
  let r = infer_algorithm_step(
    25,
    [{ name: "arr", value: "1048544", }],
    "quickSort",
    "quickSort(arr, 0, 4);",
    Some(alg),
    env,
  )
  let mut ok = false
  let mut msg = "未产出启动帧"
  match r {
    Some(s) =>
      if s.description.contains("-1") {
        msg = "启动文案带 -1 垃圾区间：\{s.description}"
      } else {
        ok = true
        msg = ""
      }
    None => ()
  }
  assert_true(ok, msg~)
}

///|
/// 锚四（#225 行为锚）：bubble infer 对 if 比较行的 j=1/j=2 均产出
/// compare（j 值动态进文案——issue 报「内层只标 j=0」形态的 HEAD
/// 复核锚）。
test "issue225_bubble_compare_j_values_dynamic" {
  let alg : @protocol.AlgorithmMatch = {
    name: "bubble_sort",
    display_name: "冒泡排序",
    func_name: "bubbleSort",
    confidence: 85,
    suggestion: "",
    line: 3,
    vis_events: [],
    evidence: "name",
  }
  let if_line = "if (arr[j] > arr[j + 1]) {"
  let mk = (j : String) => {
    let vars : Array[VarSnapshot] = [
      { name: "arr", value: "1048544", },
      { name: "n", value: "5", },
      { name: "i", value: "0", },
      { name: "j", value: j, },
    ]
    infer_bubble_sort(if_line, VarMap::new(vars), alg)
  }
  let mut ok = true
  let mut msg = ""
  match mk("1") {
    Some(s) =>
      if s.phase != "compare" || s.description != "比较 arr[1] 与 arr[2]" {
        ok = false
        msg = "j=1 文案错：\{s.description}"
      }
    None => {
      ok = false
      msg = "j=1 未产出 compare"
    }
  }
  match mk("2") {
    Some(s) =>
      if s.phase != "compare" || s.description != "比较 arr[2] 与 arr[3]" {
        ok = false
        msg = msg + "；j=2 文案错：\{s.description}"
      }
    None => {
      ok = false
      msg = msg + "；j=2 未产出 compare"
    }
  }
  assert_true(ok, msg~)
}
