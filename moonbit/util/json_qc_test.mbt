// util 层 JSON 域 quickcheck 属性（QC 批，2026-11-04）——moon prove 盲区
// 的互补防线（String/SB/组合语义 frontend 全拒，报告 §3.1）。与既有例锚
// 分工：json_escape_wbtest 管 serde_json 口径的定点例，本文件管任意输入
// 域上的 roundtrip/卫生/文法两向性质。
//
// prove 三态对照：
// - json_escape 转义完备性：prove 码点数组模型 17/18 goal（1 timeout，
//   报告 §3.2 试点 a）——本文件双保险 + 采 frontend 拒的原函数面
// - valid_json_number：prove int 段全自动证过（试点 c）；frac/exp 段
//   未做——本文件全段双保险 + 变异必拒方向 qc 独占
// - json_escape roundtrip：组合语义 prove frontend 拒——qc 独占

///|
/// json_escape roundtrip：escape 后包引号经 json_parse 解回必得原串
/// （转义/反转义两实现互为对偶的机器检查）。parse 失败折 Null → 属性红
/// （打印收缩后的反例串）。
/// prove 三态：frontend 拒（String/SB）——qc 独占。
test "qc_json_escape_roundtrip" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (s : String) => {
        let doc = "\"" + @util.json_escape(s) + "\""
        let parsed = Some(@util.json_parse(doc)) catch { _ => None }
        match parsed {
          Some(Json::String(back)) => back == s
          _ => false
        }
      },
      count=300,
      max_size=32,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// json_escape 无裸控制字符：转义输出中不残留任何码元 < 0x20（RFC 8259
/// 对字符串内容的机器化要求——\u00XX/短转义覆盖全部控制位）。
/// prove 三态：模型主体自动（17/18，1 timeout）——双保险。
test "qc_json_escape_no_bare_control" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (s : String) => {
        let esc = @util.json_escape(s)
        let mut bare = false
        for i in 0..<esc.length() {
          if esc[i].to_int() < 0x20 {
            bare = true
            break
          }
        }
        !bare
      },
      count=300,
      max_size=32,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// valid_json_number 合法构造必过：文法镜像生成器（[-]?int[.frac][exp]
/// 各段独立采样，int 禁前导零、frac/exp 至少一位）产出的串必被接受，
/// 且 json_parse 全程接受（文法校验与解析器一致）。
/// prove 三态：int 段全自动证过（报告 §3.2 试点 c）；frac/exp 段未做
/// ——全段双保险。
test "qc_valid_json_number_accepts_grammar" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (g : QcLegalNumber) => {
        if !@util.valid_json_number(g.text) {
          return false
        }
        // 文法合法 ⇔ 解析器接受，且数字捕获原文 repr 保真（"42" 不折
        // "42.0"——json_parse 头注宣称的往返保真性质的采样级检查）
        let parsed = Some(@util.json_parse(g.text)) catch { _ => None }
        match parsed {
          Some(Json::Number(_, repr~)) => repr == Some(g.text)
          _ => false
        }
      },
      count=300,
      max_size=16,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// valid_json_number 非法变异必拒：合法基底注入单点文法破坏（前导零/
/// 空 int/裸尾点/裸 e/尾垃圾），必被拒绝。
/// prove 三态：文法拒绝性质 int 段证过——变异面（跨段组合的非法形态）
/// qc 独占；每算子必非法的论证见 qc_mutate_bad 注释。
test "qc_valid_json_number_rejects_mutants" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (g : QcBadNumber) => !@util.valid_json_number(g.text),
      count=300,
      max_size=16,
      seed=seed.to_uint64(),
    )
  }
}

// —— 测试侧辅助（文法镜像生成器 + 变异算子；与被测 valid_json_number
//    实现独立——生成器构造合法/非法的论证在代码内自足） ——

///|
/// [0, bound) 均匀取整（kimicc qc_test 先例同款形态）。
fn qc_pick(state : @splitmix.RandomState, bound : Int32) -> Int32 {
  if bound <= 1 {
    0
  } else {
    (state.next_uint() % bound.reinterpret_as_uint()).reinterpret_as_int()
  }
}

///|
/// n 位随机十进制数字串（n ≥ 1）。
fn qc_digits(state : @splitmix.RandomState, n : Int32) -> String {
  let buf = StringBuilder()
  for _ in 0..<n {
    buf.write_char((48 + qc_pick(state, 10)).unsafe_to_char())
  }
  buf.to_string()
}

///|
/// RFC 8259 number 文法镜像构造：[-]?int[.frac][eE[+-]?exp]——int 是
/// "0" 或非零开头（禁前导零）；frac/exp 至少一位（禁裸点/裸 e）。
fn qc_gen_legal_number(state : @splitmix.RandomState) -> String {
  let buf = StringBuilder()
  if qc_pick(state, 4) == 0 {
    buf.write_char('-')
  }
  if qc_pick(state, 3) == 0 {
    buf.write_char('0')
  } else {
    buf.write_char((49 + qc_pick(state, 9)).unsafe_to_char()) // '1'..'9'
    buf.write_string(qc_digits(state, qc_pick(state, 7)))
  }
  if qc_pick(state, 2) == 0 {
    buf.write_char('.')
    buf.write_string(qc_digits(state, 1 + qc_pick(state, 6)))
  }
  if qc_pick(state, 2) == 0 {
    buf.write_char(if qc_pick(state, 2) == 0 { 'e' } else { 'E' })
    match qc_pick(state, 3) {
      0 => buf.write_char('+')
      1 => buf.write_char('-')
      _ => ()
    }
    buf.write_string(qc_digits(state, 1 + qc_pick(state, 3)))
  }
  buf.to_string()
}

///|
/// 合法数字串（生成域 = qc_gen_legal_number）。
struct QcLegalNumber {
  text : String
}

///|
impl @quickcheck.Arbitrary for QcLegalNumber with fn arbitrary(
  size : Int32,
  state : @splitmix.RandomState,
) -> QcLegalNumber {
  ignore(size)
  { text: qc_gen_legal_number(state), }
}

///|
impl @shrink.Shrink for QcLegalNumber with fn shrink(self : QcLegalNumber) -> Iter[
  QcLegalNumber,
] {
  // 化简链恒保文法合法：剥 sign → 剥 exp → 剥 frac → int 截短（保非零
  // 开头或单 "0"）→ 归 "0"（候选里总有比原串更短的形态）
  let (sign, int, frac, exp) = qc_split_number(self.text)
  let candidates : Array[String] = []
  if sign != "" {
    candidates.push(int + frac + exp)
  }
  if exp != "" {
    candidates.push(sign + int + frac)
  }
  if frac != "" {
    candidates.push(sign + int + exp)
  }
  if int.length() > 1 && !(int[0] == '0') {
    // 非零开头：截到单字符仍合法（首字符非 '0'）
    candidates.push(sign + int[0:1].to_owned() + frac + exp)
    candidates.push("0")
  } else if self.text != "0" {
    candidates.push("0")
  }
  candidates
  .filter(c => c != self.text && c.length() < self.text.length())
  .map(c => ({ text: c, } : QcLegalNumber))
  .iter()
}

///|
impl @debug.Debug for QcLegalNumber with fn to_repr(self : QcLegalNumber) -> Repr {
  Repr("QcLegalNumber(\{self.text})")
}

///|
/// 非法数字串（合法基底 + 单点文法破坏）。每算子必非法的论证：
/// - 前导零（sign 后插 '0'）：int 段 >1 位且首 '0' → 拒
/// - 空 int（sign 后插 '.'）：int_len == 0 → 拒
/// - 尾 '.'：合法段扫完后残留 '.'（i != n）→ 拒（含已有 frac/exp 的基底）
/// - 尾 'e'/'e+'/'e-'：exp 段零位数字 → 拒
/// - 尾 'x'/'+'：字符域外/残留 → 拒
struct QcBadNumber {
  text : String
}

///|
impl @quickcheck.Arbitrary for QcBadNumber with fn arbitrary(
  size : Int32,
  state : @splitmix.RandomState,
) -> QcBadNumber {
  ignore(size)
  let base = qc_gen_legal_number(state)
  { text: qc_mutate_bad(state, base), }
}

///|
impl @shrink.Shrink for QcBadNumber with fn shrink(_ : QcBadNumber) -> Iter[
  QcBadNumber,
] {
  // 不收缩：朴素截短会跨合法性边界（"01" 截短得 "0" 即合法），保持
  // 「必非法」不变量需重跑变异算子——反例可复现性由固定 seed 承担
  // （同 seed 重跑必得同反例），收缩收益放弃、理由在此登记
  Iter::new(() => None)
}

///|
impl @debug.Debug for QcBadNumber with fn to_repr(self : QcBadNumber) -> Repr {
  Repr("QcBadNumber(\{self.text})")
}

///|
/// 合法基底的单点文法破坏（六算子等概率）。
fn qc_mutate_bad(state : @splitmix.RandomState, legal : String) -> String {
  // sign 后的插入位（空 int / 前导零都作用于 int 段首）
  let head = if legal[0] == '-' { 1 } else { 0 }
  match qc_pick(state, 6) {
    0 => legal[0:head].to_owned() + "0" + legal[head:].to_owned()
    1 => legal[0:head].to_owned() + "." + legal[head:].to_owned()
    2 => legal + "."
    3 =>
      legal +
      (match qc_pick(state, 3) {
        0 => "e"
        1 => "e+"
        _ => "e-"
      })
    4 => legal + "x"
    _ => legal + "+"
  }
}

///|
/// 数字串四段拆解（sign/int/frac/exp；输入为 qc_gen_legal_number 形态）。
fn qc_split_number(text : String) -> (String, String, String, String) {
  let n = text.length()
  let mut i = 0
  let sign = if i < n && text[i] == '-' {
    i += 1
    "-"
  } else {
    ""
  }
  let int_start = i
  while i < n && text[i] >= '0' && text[i] <= '9' {
    i += 1
  }
  let int = text[int_start:i].to_owned()
  let frac_start = i
  if i < n && text[i] == '.' {
    i += 1
    while i < n && text[i] >= '0' && text[i] <= '9' {
      i += 1
    }
  }
  let frac = text[frac_start:i].to_owned()
  let exp_start = i
  if i < n && (text[i] == 'e' || text[i] == 'E') {
    i += 1
    if i < n && (text[i] == '+' || text[i] == '-') {
      i += 1
    }
    while i < n && text[i] >= '0' && text[i] <= '9' {
      i += 1
    }
  }
  let exp = text[exp_start:i].to_owned()
  (sign, int, frac, exp)
}
