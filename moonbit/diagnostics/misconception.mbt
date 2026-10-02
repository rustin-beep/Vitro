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
      // f32 语义化（审阅 F6 修复 2026-10-02）：oracle confidence 是 f32
      //（Rust `as f32`），本侧 Double=f64——2/3 等非十进制比值两侧文本
      // 分叉（0.6666666666666666 vs serde f32 "0.6666667"，探针实证）。
      // 计算处舍入到最近 f32 保 wire 等价。
      let confidence = if raw_confidence > 1.0 {
        1.0
      } else {
        round_to_f32(raw_confidence)
      }
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

///|
/// f64 → 最近 f32 的值域舍入（oracle `as f32` 的语义等价物——MoonBit 无
/// f32 类型，round_to_nearest 手写）。**tie 边界不可达论证**：调用域 =
/// count/denominator（两整数 ≤ 10）；tie 需值恰为某 f32 中点（尾数 25
/// 位精确值），n/d 达此需 d 整除 2^25 形态——d ∈ {1,2,4,8} 时尾数 ≤3 位
/// 远短于 24，d ∈ {3,5,6,7,9,10} 为二进制循环小数（f64 近似不落中点），
/// 故 half-up 与 half-even 等价。探针锚 2/3 / 3/7（serve 对拍终证随段三）。
fn round_to_f32(v : Double) -> Double {
  if v <= 0.0 || v >= 1.0 {
    return v // 域外直通（confidence ∈ [0,1]；0/1 均为 f32 精确值）
  }
  // 规格化 v = m × 2^e，m ∈ [1,2)
  let mut e = 0
  let mut m = v
  while m >= 2.0 {
    m = m / 2.0
    e = e + 1
  }
  while m < 1.0 {
    m = m * 2.0
    e = e - 1
  }
  // 尾数舍到 24 位有效（f32 = 1 + 23 位尾数）；scaled ≤ 2^24 为 f64 精确整数域
  let scaled = m * 8388608.0
  let rounded = (scaled + 0.5).floor() // half-up（域内无 tie，见头注论证）
  if rounded >= 8388608.0 * 2.0 {
    // 1.111..1 → 10.0 进位跨界：m'=1、指数 +1
    pow2i(e + 1)
  } else {
    rounded / 8388608.0 * pow2i(e)
  }
}

///|
/// 2 的整数幂（e 小负数域——confidence 规格化 |e| ≤ 4）。
fn pow2i(e : Int) -> Double {
  let mut r = 1.0
  let mut k = e
  while k < 0 {
    r = r / 2.0
    k = k + 1
  }
  while k > 0 {
    r = r * 2.0
    k = k - 1
  }
  r
}

///|
/// f32 精确值的最短十进制文本（ryu f32 的行为等价物——serde_json 序列化
/// f32 的 wire 形态；confidence 对拍面用）。**前置**：v 须已是 f32 精确值
///（经 `round_to_f32`）。算法 = 逐小数位 D（1..=9）四舍五入生成候选 +
/// parse 回代验证 `round_to_f32(parse(s)) == v`——**不能截断 f64 最短
/// 文本**（f32 与 f64 在各数位上舍入到不同精度，首版截断法实锤产出
/// "0.6666668" 假值）。域约束 (0,1) 小数（confidence = n/d，n<d；
/// 0/1 前置分支；邻近 1 的进位形态域内不可达，9 位全败走防御 fallback）。
pub fn f32_shortest_text(v : Double) -> String {
  if v == 0.0 {
    return "0.0" // serde_json 整值形态（同 1.0）
  }
  if v == 1.0 {
    return "1.0"
  }
  for d = 1; d <= 9; d = d + 1 {
    let digits = (v * pow10d(d) + 0.5).floor().to_int()
    if digits <= 0 {
      continue
    }
    let text = "0." + pad_zero_to(digits, d)
    let parsed = @string.parse_double(text.view()) catch { _ => continue }
    if round_to_f32(parsed) == v {
      return text
    }
  }
  v.to_string() // 防御（域内不可达——f32 九位十进制唯一标识）
}

///|
/// 10 的正整数幂（d ≤ 9）。
fn pow10d(d : Int) -> Double {
  let mut r = 1.0
  for _i = 0; _i < d; _i = _i + 1 {
    r = r * 10.0
  }
  r
}

///|
/// 数字文本左补零至 width 位（"6666667"→d=7 同宽；"5"→d=2 得 "05"）。
fn pad_zero_to(digits : Int, width : Int) -> String {
  let t = digits.to_string()
  if t.length() >= width {
    return t
  }
  let buf = StringBuilder()
  for _i = 0; _i < width - t.length(); _i = _i + 1 {
    buf.write_char('0')
  }
  buf.write_string(t)
  buf.to_string()
}
