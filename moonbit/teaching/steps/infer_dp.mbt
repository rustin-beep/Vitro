// teaching/steps·infer dp 族（S8 teaching 批五号，2026-10-02）：泛型
// 动态规划照搬 vitro_algorithm_steps/src/dp.rs:1-146——外/内循环初始化体
// 排除（二审 P1-1：多行 for 体经 lookahead 找首个非循环头行；§6-2 同款
// j 分支）+ transition 收紧（U1#1 P0-3：同语句两侧都有 dp[ 才是转移）+
// 循环主语具名（§6-3：币种/物品/金额特征词）。

///|
/// 动态规划。
fn infer_dp(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let i = match vars.get_int_any(["i", "n"]) {
    Some(v) => v
    None => -1
  }
  let w = match vars.get_int_any(["w", "j", "capacity"]) {
    Some(v) => v
    None => -1
  }
  // U1#1 P0-3（用户审阅实锤）：① 旧外循环判据 `contains("i") &&
  // contains("n")` 把 `for (int j = coins[i]; j <= amount; j++)` 的
  // **amount 含 n** 误判外循环——收紧为 i 的形态判据（int i / i < / i <=）；
  // ② 文案「遍历物品」按算法族泛化（dpFib/dpLCS/dpLIS/matrixChain 均
  // 非背包），标注展示的是子问题下标。
  if starts_with(line_lower, "for ") || starts_with(line_lower, "while ") {
    let i_head = line_lower.contains("int i") ||
      line_lower.contains(" i <") ||
      line_lower.contains(" i <=") ||
      line_lower.contains("(i <") ||
      line_lower.contains("(i <=")
    // 二审 P1-1：4/6 模板的 outer_loop 首现挂在初始化循环
    //（for (…) dp[i] = 1000; / dp[i] = 1; / dp[i][0] = 0; 等）——
    // 循环体为 dp[..] = 纯字面量时不算子问题遍历。
    // U1#1 管道批（P1-1 边界收口）：多行/嵌套 for 的体不在 for 行内
    //（dpLCS L10 for i / L11 for j / L12 体）——lookahead 里找首个
    // 非循环头/非花括号的行作为体。
    let body_line = if line_lower.contains("dp[") {
      line_lower
    } else {
      lookahead_first_body_line(env.lookahead)
    }
    if i_head && not(dp_loop_body_is_init(body_line)) {
      return Some(
        build_step(
          algorithm,
          "outer_loop",
          "遍历\{dp_outer_subject(line_lower, env)} i=\{i}",
        ),
      )
    }
    // §6-2（v4 清单，2026-09-14）：j 分支补同款初始化体排除——多行双层
    // 初始化循环（dpKnapsack L14 / dpLCS L11 / matrixChain L6 的内层 j，
    // 体 `dp[i][j] = 0;` 在下一行）此前漏判，inner_loop 首现挂初始化循环
    //（人审 ✗ ×3）。
    if (
        line_lower.contains("int j") ||
        line_lower.contains(" j <") ||
        line_lower.contains("(j <")
      ) &&
      not(dp_loop_body_is_init(body_line)) {
      return Some(
        build_step(
          algorithm,
          "inner_loop",
          "遍历\{dp_inner_subject(line_lower, env)} j=\{w}",
        ),
      )
    }
  }
  // U1#1 P0-3：旧判据 `contains("dp[") && contains('=')` 使**全部 5 个
  // dp 模板的 transition 首现挂在初始化行**（dp[0] = 0; 等）。真正的
  // 状态转移右侧引用 dp[（dp[i] = f(dp[..])）——要求同语句两侧都有 dp[。
  if count_occurrences(line_lower, "dp[") >= 2 && line_lower.contains("=") {
    return Some(
      build_step(
        algorithm, "transition", "状态转移：计算当前子问题的最优解",
      ),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "动态规划计算完成"))
  }
  None
}

///|
/// 二审 P1-1：循环行是否为 dp 状态表初始化（体为 `dp[..] = <纯字面量>`）。
/// 真正的子问题遍历循环体要么为空（`{`），要么引用其他变量/dp 依赖。
fn dp_loop_body_is_init(line_lower : String) -> Bool {
  if not(line_lower.contains("dp[")) || not(line_lower.contains("=")) {
    return false
  }
  // 取最后一个 '=' 的右侧，trim 后是纯整数字面量即初始化
  match find_char_reverse(line_lower, '=') {
    Some(eq) => {
      let rhs0 = line_lower
        .substring(start=eq + 1, end=line_lower.length())
        .trim()
        .to_string()
      let rhs = strip_trailing_semicolon(rhs0).trim().to_string()
      rhs != "" && all_digits(rhs)
    }
    None => false
  }
}

///|
/// lookahead 里找首个非循环头/非花括号的行作为循环体（Rust
/// `lines().map(trim+lower).find(...)`——trim 后小写，行序遍历首中）。
fn lookahead_first_body_line(lookahead : String) -> String {
  // 按 \n 切行（Rust lines() 语义：尾换行不产空行）
  let mut start = 0
  let n = lookahead.length()
  while start <= n {
    let end0 = find_char(lookahead, '\n', start)
    let end = match end0 {
      Some(e) => e
      None => n
    }
    if end > start || end0 is Some(_) {
      let l = lookahead.substring(start~, end~).trim().to_lower().to_string()
      if l != "" &&
        not(starts_with(l, "for ")) &&
        not(starts_with(l, "while ")) &&
        not(starts_with(l, "{")) {
        return l
      }
    }
    if end0 is None {
      break
    }
    start = end + 1
  }
  ""
}

///|
/// 子串出现次数（Rust `matches("dp[").count()`）。
fn count_occurrences(s : String, sub : String) -> Int {
  let mut cnt = 0
  let mut from = 0
  while true {
    match find_sub(s, sub, from) {
      Some(p) => {
        cnt = cnt + 1
        from = p + sub.length()
        if from >= s.length() && sub.length() > 0 {
          break
        }
      }
      None => break
    }
  }
  cnt
}

///|
/// §6-3（v4 清单 #43/#51）：外层循环主语——i 不总是「子问题」下标：币种
/// 循环（dpCoinChange：`for (i < coinCount)`）与物品循环（背包：行或
/// lookahead 含 `wt[`/`weight[`）。检测到特征词才具名，否则保持泛化
///「子问题」（dpFib/dpLIS/dpLCS/matrixChain 的 i 确是子问题下标）。
fn dp_outer_subject(line_lower : String, env : InferEnv) -> String {
  let ctx = "\{line_lower} \{env.lookahead.to_lower()}"
  if ctx.contains("coin") {
    return "币种"
  }
  if ctx.contains("wt[") || ctx.contains("weight[") {
    return "物品"
  }
  "子问题"
}

///|
/// §6-3：内层循环主语——dpCoinChange 的 j 索引金额
///（`for (j = coins[i]; j <= amount)`）。
fn dp_inner_subject(line_lower : String, env : InferEnv) -> String {
  let ctx = "\{line_lower} \{env.lookahead.to_lower()}"
  if ctx.contains("coin") {
    return "金额"
  }
  "子问题维度"
}
