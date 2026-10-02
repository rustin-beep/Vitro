// teaching/steps·detect math 族（S8 teaching 批五号）：三算法判据照搬
// detector/math.rs:6-28——全命名主导；与 graph 族差异：build_match 的
// compare_lines 传**空数组**（Rust `&[]` 同款——math 族判据零特征消费，
// vis_events 投影恒空）。

///|
/// math 族判据（三算法——gcd/is_prime/hanoi 全命名主导照搬）。
pub fn detect_math(
  name_lower : String,
  features : FuncFeatures,
  func_name : String,
  line : Int,
) -> Array[@protocol.AlgorithmMatch] {
  // features 不消费（Rust `_features` 同款）——签名保留族统一形态
  ignore(features)
  let matches : Array[@protocol.AlgorithmMatch] = []
  // 最大公约数
  if name_lower.contains("gcd") || name_lower.contains("greatest") {
    matches.push(build_match("gcd", "最大公约数", func_name, line, []))
  }
  // 素数判断
  if name_lower.contains("prime") || name_lower.contains("isprime") {
    matches.push(build_match("is_prime", "素数判断", func_name, line, []))
  }
  // 汉诺塔
  if name_lower.contains("hanoi") {
    matches.push(build_match("hanoi", "汉诺塔", func_name, line, []))
  }
  matches
}
