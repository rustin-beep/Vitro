// teaching/steps·infer math 族（S8 teaching 批五号，2026-10-02）：
// 三算法照搬 vitro_algorithm_steps/src/math.rs:1-148——gcd 的 prev_vars
// 算式收口（U1#1 P0-4——行末帧 b 已被赋值，用行入口操作数拼 48 % 18 = 12）
// + mod 判据 IO 行排除与表达式语境收紧（二审 P0-C）/ hanoi 的 n-1 与
// 顶层调用区分（U1#1 P1-50）+ return 分支 main 判定（§6-5 v4 #68）。

///|
/// prev_vars 按名取整（Rust `prev_vars.iter().find(|v| v.name == n)
/// .and_then(|v| v.value.parse::<i32>().ok())`——裸数组直查）。
fn prev_get_int(prev_vars : Array[VarSnapshot], name : String) -> Int? {
  for v in prev_vars {
    if v.name == name {
      return parse_int(v.value)
    }
  }
  None
}

///|
/// 最大公约数。
fn infer_gcd(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  env : InferEnv,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let a = match vars.get_int_any(["a"]) {
    Some(v) => v
    None => -1
  }
  let b = match vars.get_int_any(["b"]) {
    Some(v) => v
    None => -1
  }
  if starts_with(line_lower, "while ") {
    return Some(build_step(algorithm, "loop", "辗转相除：a=\{a}, b=\{b}"))
  }
  // U1#1 P0-4（用户审阅）：mod 是「展示运算过程」的 phase——行末帧的 b
  // 已被本语句赋值，用当前 a/b 拼算式会得到 48 % 12 = 0（真值 48 % 18 = 12）。
  // 二审 P0-C：`contains('%')` 过宽——printf 格式串的百分号命中，mod
  // 首现漂到 main 的打印行。排除 IO 行 + 要求 % 出现在表达式语境
  //（a % b / %= / x % y 形态，而非 "..." 字符串内）。
  let is_io_line = line_lower.contains("printf") ||
    line_lower.contains("scanf") ||
    line_lower.contains("sprintf") ||
    line_lower.contains("fprintf") ||
    line_lower.contains("snprintf")
  let has_mod_expr = line_lower.contains(" % ") || line_lower.contains("%=")
  if has_mod_expr && not(is_io_line) {
    // U1#1 管道批（P0-4 收口）：运算过程类 phase 用**行入口操作数**拼
    // 算式——行末帧的 b 已被 `b = a % b` 赋值（48 % 12 = 0 是错的），
    // prev 是进入本行前一刻（48 % 18），结果恰是行末的 b（余数 12）。
    let pa = prev_get_int(env.prev_vars, "a")
    let pb = prev_get_int(env.prev_vars, "b")
    let b_now = match vars.get_int("b") {
      Some(v) => v
      None => -1
    }
    match (pa, pb) {
      (Some(x), Some(y)) =>
        if x > 0 && y > 0 && b_now >= 0 {
          return Some(
            build_step(
              algorithm,
              "mod",
              "计算 \{x} % \{y} = \{b_now}（余数作为新的 b）",
            ),
          )
        }
      _ => ()
    }
    return Some(
      build_step(algorithm, "mod", "求余并更新 b（辗转相除一步）"),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "最大公约数为 \{a}"))
  }
  None
}

///|
/// 素数判断。
fn infer_is_prime(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let n = match vars.get_int_any(["n"]) {
    Some(v) => v
    None => -1
  }
  let i = match vars.get_int("i") {
    Some(v) => v
    None => -1
  }
  if starts_with(line_lower, "if ") &&
    line_lower.contains("<=") &&
    line_lower.contains("1") {
    return Some(
      build_step(algorithm, "check_small", "排除小于等于 1 的数"),
    )
  }
  if starts_with(line_lower, "for ") {
    return Some(
      build_step(
        algorithm,
        "test_divisor",
        "试除 i=\{i}，检查 \{n} % \{i} == 0",
      ),
    )
  }
  if line_lower.contains("n % i") && line_lower.contains("== 0") {
    return Some(
      build_step(
        algorithm,
        "found_factor",
        "发现因子 \{i}，\{n} 不是素数",
      ),
    )
  }
  if starts_with(line_lower, "return") {
    return Some(build_step(algorithm, "finish", "\{n} 是素数"))
  }
  None
}

///|
/// 汉诺塔。
fn infer_hanoi(
  source_line : String,
  vars : VarMap,
  algorithm : @protocol.AlgorithmMatch,
  func_name : String,
) -> @protocol.AlgorithmStepSnapshot? {
  let line_lower = source_line.to_lower()
  let n = match vars.get_int_any(["n"]) {
    Some(v) => v
    None => -1
  }
  if line_lower.contains("n == 1") || line_lower.contains("n==1") {
    return Some(
      build_step(
        algorithm, "base", "基准情况：直接把盘子从起始柱移到目标柱",
      ),
    )
  }
  // 递归调用判定用原大小写 source_line（Rust/dfs 同款——函数名大小写敏感）
  if source_line.contains("\{func_name}(") {
    // U1#1 P1-50（用户审阅）：main 调用点（n=3）曾被文案恒减一报「2 个
    // 盘子」。递归实参含 n-1 形态才是函数体内的自递归（减一正确）；
    // main 顶层的 hanoi(3, …) 原值表述。
    if line_lower.contains("n - 1") || line_lower.contains("n-1") {
      // 二审 §7.5：n=1 时 hanoi(n-1) 是 0 盘递归（基准分支前的形态），
      // 不产出「递归移动 0 个盘子」。
      if n > 1 {
        return Some(
          build_step(algorithm, "recursive", "递归移动 \{n - 1} 个盘子"),
        )
      }
      return None
    }
    // v5 ✗3：顶层调用帧的「问题陈述」改入口语义——从 from 柱移动到 to 柱
    //（char 形参按 i32 存，还原为字符；Rust from_u32 无效 None 降级——
    // MoonBit Char::from_int 恒返回 Char，有效性以可打印 ASCII 域近似
    //〔char 形参域即 'A'/'B'/'C'，ASCII 域内等价，登记〕，域外降级）。
    let from_c = match vars.get_int_any(["from"]) {
      Some(v) => if v >= 32 && v < 127 { Some(Char::from_int(v)) } else { None }
      None => None
    }
    let to_c = match vars.get_int_any(["to"]) {
      Some(v) => if v >= 32 && v < 127 { Some(Char::from_int(v)) } else { None }
      None => None
    }
    match (from_c, to_c) {
      (Some(f), Some(t)) =>
        return Some(
          build_step(
            algorithm,
            "recursive",
            "从 \{f} 柱移动 \{n} 个盘子到 \{t} 柱",
          ),
        )
      _ =>
        return Some(
          build_step(
            algorithm,
            "recursive",
            "启动汉诺塔：移动 \{n} 个盘子",
          ),
        )
    }
  }
  if line_lower.contains("move") && line_lower.contains("disk") {
    return Some(build_step(algorithm, "move", "移动第 \{n} 个盘子"))
  }
  if starts_with(line_lower, "return") {
    // §6-5（v4 #68）：hanoi 体内的 return（含基准分支）是**该层递归
    // 结束**，不是整体完成——原文案「汉诺塔移动完成」与所挂语句不符
    //（真正完成在 main 末尾的 return）。
    if func_name == "main" {
      return Some(build_step(algorithm, "finish", "汉诺塔移动完成"))
    }
    return Some(
      build_step(algorithm, "finish", "该层递归结束，返回上一层"),
    )
  }
  None
}
