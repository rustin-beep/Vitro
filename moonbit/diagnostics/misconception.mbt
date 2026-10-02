// M3 误区检测（misconception_patterns.rs 照搬，2026-10-02）：滑窗计数 +
// 置信度 + M05 trap 关键词匹配。语言无关（输入仅错误码数组与 trap 串）。

///|
/// 分析近期编译历史，返回检出的误区（置信度降序——稳定排序保声明序，
/// 探针实证 sort_by 稳定 2026-10-02）。
pub fn detect_misconceptions(
  history : Array[CompileRecord],
) -> Array[DetectedMisconception] {
  let patterns = default_patterns()
  let results : Array[DetectedMisconception] = []
  for pat in patterns {
    let window = if pat.time_window > 1 { pat.time_window } else { 1 }
    let recent_len = if history.length() > window {
      window
    } else {
      history.length()
    }
    let recent_start = history.length() - recent_len
    let mut count = 0
    for i = recent_start; i < history.length(); i = i + 1 {
      if record_matches(history[i], pat) {
        count = count + 1
      }
    }
    if count >= pat.min_occurrences {
      let denominator = if recent_len > 1 { recent_len } else { 1 }
      let raw_confidence = count.to_double() / denominator.to_double()
      let confidence = if raw_confidence > 1.0 { 1.0 } else { raw_confidence }
      results.push(DetectedMisconception::{
        pattern_id: pat.id,
        pattern_name: pat.name,
        description: pat.description,
        occurrence_count: count,
        confidence,
      })
    }
  }
  // 置信度降序（Rust sort_by stable + partial_cmp Equal 兜底）
  results.sort_by(fn(a, b) {
    if b.confidence > a.confidence {
      1
    } else if b.confidence < a.confidence {
      -1
    } else {
      0
    }
  })
  results
}

///|
/// 单条记录是否命中模式（Rust record_matches 照搬）：错误码交集或
/// M05 的 trap 关键词（英文小写化后 contains——Rust to_lowercase 的
/// 全 Unicode 变形域在本场景不可达，ASCII 域等价）。
fn record_matches(rec : CompileRecord, pat : MisconceptionPattern) -> Bool {
  if !pat.error_codes.is_empty() {
    for code in pat.error_codes {
      for c in rec.error_codes {
        if c == code {
          return true
        }
      }
    }
  }
  // M05 特例：按 trap 关键词匹配（栈溢出族）
  if pat.id == "M05" {
    match rec.trap_message {
      Some(msg) => {
        let lower = ascii_lower(msg)
        if lower.contains("stack overflow") ||
          lower.contains("call stack") ||
          lower.contains("栈溢出") {
          return true
        }
      }
      None => ()
    }
  }
  false
}

///|
/// ASCII 域大写转小写（core 无 to_lowercase；中文等非 ASCII 不变形）。
fn ascii_lower(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    let v = c.to_int()
    buf.write_char(
      if v >= 65 && v <= 90 {
        (v + 32).unsafe_to_char()
      } else {
        c
      },
    )
  }
  buf.to_string()
}
