// teaching/steps·判据 search + string 族（S8 teaching 批二号，2026-10-01）：
// detector/search.rs:6-23（binary_search——命名三分支 + 结构分支
// 〔单循环 + mid 计算 + left/right 更新〕）+ detector/string.rs:6-27
//（string_reverse / string_match_bf / string_match_kmp 命名判据——
// 结构特征零消费，compare_lines 空表与 Rust `&[]` 同形）。

///|
/// search 族判据（二分查找）。
pub fn detect_search(
  name_lower : String,
  features : FuncFeatures,
  func_name : String,
  line : Int,
) -> Array[@protocol.AlgorithmMatch] {
  let matches : Array[@protocol.AlgorithmMatch] = []
  // 二分查找
  if name_lower.contains("binary") ||
    name_lower.contains("bsearch") ||
    (
      features.has_single_loop &&
      features.has_mid_calculation &&
      features.has_left_right_update
    ) {
    matches.push(
      build_match(
        "binary_search",
        "二分查找",
        func_name,
        line,
        features.compare_lines,
      ),
    )
  }
  matches
}

///|
/// string 族判据（反转 / 朴素匹配 / KMP——纯命名判据）。
pub fn detect_string(
  name_lower : String,
  func_name : String,
  line : Int,
) -> Array[@protocol.AlgorithmMatch] {
  let matches : Array[@protocol.AlgorithmMatch] = []
  // 字符串反转
  if name_lower.contains("reverse") && name_lower.contains("str") {
    matches.push(
      build_match("string_reverse", "字符串反转", func_name, line, []),
    )
  }
  // 朴素模式匹配
  if name_lower.contains("indexbf") ||
    name_lower.contains("bfmatch") ||
    name_lower.contains("brute") {
    matches.push(
      build_match("string_match_bf", "朴素模式匹配", func_name, line, []),
    )
  }
  // KMP 模式匹配
  if name_lower.contains("kmp") ||
    name_lower.contains("indexkmp") ||
    name_lower.contains("getnext") {
    matches.push(
      build_match("string_match_kmp", "KMP 模式匹配", func_name, line, []),
    )
  }
  matches
}
