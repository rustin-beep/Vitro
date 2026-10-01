// teaching/steps·infer sorting 族（S8 teaching 批一号）：九算法步骤
// 推断照搬 vitro_algorithm_steps/src/sorting.rs:1-507（含全部用户审阅
// 修复语义：j 合法上界越界描述拦截 / minIdx 别名表 / 插入收紧
// arr[j+1]=key 形态 + prev_vars 行入口兜底 / 子数组错字 / 空区间递归基
// 拦截 / 枢轴落位文案 / 位权位序 / count[...]++ 收紧——逐条注释照搬）。

///|
/// 冒泡排序。
fn infer_bubble_sort(
  source_line : String,
  vars : VarMap,
  algorithm : @session.AlgorithmMatch,
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
  // j 合法上界（内层 `j < n - 1 - i` ⇒ j+1 ≤ n-1-i 仍在数组内；j 停在
  // 退出值时不得再产出比较/交换——那是残留值编造，arr[j+1] 恒越界）
  let j_in_inner_range = if n > 0 && i >= 0 {
    j >= 0 && j < n - 1 - i
  } else {
    j >= 0
  }
  if starts_with(line_lower, "for ") || starts_with(line_lower, "while ") {
    if line_lower.contains("i") && not(line_lower.contains("j")) {
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
    if not(j_in_inner_range) {
      return None
    }
    let j_str = if j >= 0 { "\{j}" } else { "?" }
    let j1 = if j >= 0 { "\{j + 1}" } else { "?" }
    return Some(
      build_step(algorithm, "compare", "比较 arr[\{j_str}] 与 arr[\{j1}]"),
    )
  }
  if source_line.contains("temp") && source_line.contains("=") {
    if not(j_in_inner_range) {
      return None
    }
    let j_str = if j >= 0 { "\{j}" } else { "?" }
    let j1 = if j >= 0 { "\{j + 1}" } else { "?" }
    return Some(
      build_step(
        algorithm,
        "swap",
        "交换 arr[\{j_str}]↔arr[\{j1}]，较大的元素向右移动",
      ),
    )
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
  algorithm : @session.AlgorithmMatch,
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
    if line_lower.contains("i") && not(line_lower.contains("j")) {
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
  if source_line.contains("temp") && source_line.contains("=") {
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
  algorithm : @session.AlgorithmMatch,
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
    if line_lower.contains("i") && not(line_lower.contains("j")) {
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
    not(source_line.contains("= arr")) {
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
  algorithm : @session.AlgorithmMatch,
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
      return Some(
        build_step(
          algorithm,
          "recursive",
          "启动快速排序：处理区间 [left=\{left}, right=\{right}]",
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
  if line_lower.contains("pivot") &&
    line_lower.contains("=") &&
    not(starts_with(line_lower, "for ")) {
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
  if source_line.contains("temp") && source_line.contains("=") {
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
  algorithm : @session.AlgorithmMatch,
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
      return Some(
        build_step(
          algorithm,
          "recursive_split",
          "启动归并：处理区间 [\{left}, \{right}]",
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
  algorithm : @session.AlgorithmMatch,
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
  if source_line.contains("temp") && source_line.contains("=") {
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
  algorithm : @session.AlgorithmMatch,
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
  if line_lower.contains("temp") &&
    line_lower.contains("=") &&
    not(starts_with(line_lower, "for ")) {
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
  algorithm : @session.AlgorithmMatch,
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
  algorithm : @session.AlgorithmMatch,
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
    not(line_lower.contains("+=")) {
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
  s.length() >= prefix.length() &&
  s.substring(start=0, end=prefix.length()) == prefix
}

///|
/// prev_vars 行入口整型读（Rust `find + trim().parse()`——本侧 value
/// 严格解析，trim 容忍 Rust trim 语义）。
fn env_prev_int(env : InferEnv, name : String) -> Int? {
  for v in env.prev_vars {
    if v.name == name {
      return parse_int(v.value.trim().to_string())
    }
  }
  None
}
