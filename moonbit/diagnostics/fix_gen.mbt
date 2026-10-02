// M1 修复生成机制（error_catalog.rs generate_fix 照搬，2026-10-02）：
// 静态载荷查表（fix_payloads_gen）+ 动态五码坐标计算（本文件）+
// find_single_equals_in_condition 辅助。**坐标单位 = UTF-8 字节偏移**
// （诊断坐标契约与 source 包列号口径同源）——字节域操作一律经
// @util.utf8_bytes，禁在 UTF-16 码元域做位置算术（MoonBit String 陷阱）。
//
// 分叉登记：trimmed_len 的尾部空白集按「空格/\t/\r/\n」四类剥（Rust
// trim_end 是全量 Unicode is_whitespace——U+0085/U+3000 等在 C 源码
// 行尾不可达，简化域登记在案）。

///|
/// 修复生成（Rust generate_fix 七元组的 record 形态）。入参与 Rust 同形：
/// `code` 错误码 / `line` `column` 1-based 诊断坐标 / `message` 诊断文案
/// （3035/3041 的分支判据）/ `source_lines` 源码行表。
pub fn generate_fix(
  code : Int,
  line : Int,
  column : Int,
  message : String,
  source_lines : Array[String],
) -> FixOutcome {
  let line_idx = if line - 1 > 0 { line - 1 } else { 0 }
  let line_text = if line_idx < source_lines.length() {
    source_lines[line_idx]
  } else {
    ""
  }
  let trimmed_len = trim_end_byte_len(line_text)
  let col0 = if column - 1 > 0 { column - 1 } else { 0 }
  // 动态五码（机制——勘察 A3 拆分判据，不入表）
  match code {
    1004 => fix_1004_unsupported_op(line, col0, line_text)
    3035 => fix_3035_scanf_arg(message)
    3041 => fix_3041_member_access(message)
    3050 => fix_3050_assign_in_condition(line, line_text)
    3051 => fix_3051_off_by_one(line, line_text)
    _ =>
      // 静态载荷表（fix_payloads_gen）
      match fix_payload(code) {
        Some(p) =>
          match p.anchor {
            Manual =>
              FixOutcome::{
                suggestion: p.suggestion,
                fix_kind: p.fix_kind,
                start_line: 0,
                start_col: 0,
                end_line: 0,
                end_col: 0,
                text: "",
              }
            LineEnd =>
              FixOutcome::{
                suggestion: p.suggestion,
                fix_kind: p.fix_kind,
                start_line: line,
                start_col: trimmed_len,
                end_line: line,
                end_col: trimmed_len,
                text: p.text,
              }
          }
        // Rust `_ =>` default：无修复（空七元组）
        None =>
          FixOutcome::{
            suggestion: "",
            fix_kind: 0,
            start_line: 0,
            start_col: 0,
            end_line: 0,
            end_col: 0,
            text: "",
          }
      }
  }
}

///|
/// 1004：条件中的单 | / & 回搜（Rust 列 92-138 照搬——错误位前 3 字节
/// 内找孤立位运算符，改写为逻辑运算符；找不到给 manual 提示）。
fn fix_1004_unsupported_op(
  line : Int,
  col0 : Int,
  line_text : String,
) -> FixOutcome {
  let bytes = @util.utf8_bytes(line_text)
  let mut found_pos : Int? = None
  let mut replacement = ""
  if col0 >= 1 {
    // Rust (0..=col0-1).rev().take(3)：i 自 col0-1 降序至多 3 个
    let mut i = col0 - 1
    let mut steps = 0
    while i >= 0 && steps < 3 {
      if i + 1 < bytes.length() {
        let cur = bytes[i].to_int()
        let next = bytes[i + 1].to_int()
        if next == 0x7c && cur != 0x7c {
          found_pos = Some(i)
          replacement = "||"
          break
        }
        if next == 0x26 && cur != 0x26 {
          found_pos = Some(i)
          replacement = "&&"
          break
        }
      }
      i = i - 1
      steps = steps + 1
    }
  }
  match found_pos {
    Some(pos) => {
      let lone = if replacement == "||" { "|" } else { "&" }
      FixOutcome::{
        suggestion: "位运算符 '\{lone}' 在条件中很少使用，建议改为逻辑运算符 '\{replacement}'",
        fix_kind: 1,
        start_line: line,
        start_col: pos,
        end_line: line,
        end_col: pos + 1,
        text: replacement,
      }
    }
    None =>
      FixOutcome::{
        suggestion: "检测到不支持的操作符，建议检查是否误写 | 或 &",
        fix_kind: 4,
        start_line: 0,
        start_col: 0,
        end_line: 0,
        end_col: 0,
        text: "",
      }
  }
}

///|
/// 3035：scanf 参数类型（按诊断文案分支——Rust 列 199-221 照搬）。
fn fix_3035_scanf_arg(message : String) -> FixOutcome {
  let manual = fn(s : String) -> FixOutcome {
    FixOutcome::{
      suggestion: s,
      fix_kind: 4,
      start_line: 0,
      start_col: 0,
      end_line: 0,
      end_col: 0,
      text: "",
    }
  }
  if message.contains("&") || message.contains("指针") {
    manual(
      "scanf 参数需要传入变量的地址，建议在变量名前添加 '&'",
    )
  } else {
    manual("scanf 参数类型不匹配，请检查格式符与变量类型")
  }
}

///|
/// 3041：非结构体成员访问（. <-> -> 互改建议——Rust 列 232-255 照搬）。
fn fix_3041_member_access(message : String) -> FixOutcome {
  let manual = fn(s : String) -> FixOutcome {
    FixOutcome::{
      suggestion: s,
      fix_kind: 4,
      start_line: 0,
      start_col: 0,
      end_line: 0,
      end_col: 0,
      text: "",
    }
  }
  if message.contains("->") {
    manual(
      "结构体变量应使用 '.' 而不是 '->'，建议将 '->' 改为 '.'",
    )
  } else {
    manual(
      "只有结构体类型才能使用成员访问，请检查变量类型",
    )
  }
}

///|
/// 3050：条件中赋值 = → ==（Rust 列 276-299 + find_single_equals 照搬）。
fn fix_3050_assign_in_condition(line : Int, line_text : String) -> FixOutcome {
  match find_single_equals_in_condition(line_text) {
    Some((start, end)) =>
      FixOutcome::{
        suggestion: "条件中使用了赋值 =，建议改为比较 ==",
        fix_kind: 1,
        start_line: line,
        start_col: start,
        end_line: line,
        end_col: end,
        text: "==",
      }
    None =>
      FixOutcome::{
        suggestion: "条件中使用了赋值 =，建议检查是否应使用 ==",
        fix_kind: 4,
        start_line: 0,
        start_col: 0,
        end_line: 0,
        end_col: 0,
        text: "",
      }
  }
}

///|
/// 3051：循环 <= → <（Rust 列 301-323 照搬——行内找首现 "<=" 字节位）。
fn fix_3051_off_by_one(line : Int, line_text : String) -> FixOutcome {
  let bytes = @util.utf8_bytes(line_text)
  let mut pos : Int? = None
  for i = 0; i + 1 < bytes.length(); i = i + 1 {
    if bytes[i].to_int() == 0x3c && bytes[i + 1].to_int() == 0x3d {
      pos = Some(i)
      break
    }
  }
  match pos {
    Some(p) =>
      FixOutcome::{
        suggestion: "循环条件使用了 <=，可能导致数组越界，建议改为 <",
        fix_kind: 1,
        start_line: line,
        start_col: p,
        end_line: line,
        end_col: p + 2,
        text: "<",
      }
    None =>
      FixOutcome::{
        suggestion: "循环条件可能导致数组越界，建议检查边界",
        fix_kind: 4,
        start_line: 0,
        start_col: 0,
        end_line: 0,
        end_col: 0,
        text: "",
      }
  }
}

///|
/// 找条件括号内的孤立 `=`（Rust find_single_equals_in_condition 照搬）：
/// 返回其 (起始字节位, 结束字节位)。prev/next 排除 ==、!=、<=、>=。
fn find_single_equals_in_condition(line : String) -> (Int, Int)? {
  // 标量数组 + 平行字节偏移表（Rust char_indices 的等价物）
  let chars : Array[Char] = []
  for c in line {
    chars.push(c)
  }
  let offsets : Array[Int] = []
  let mut acc = 0
  for c in chars {
    offsets.push(acc)
    acc = acc + char_utf8_len(c)
  }
  let mut in_parens = false
  let mut prev_char = '\u0000'
  for k = 0; k < chars.length(); k = k + 1 {
    let c = chars[k]
    if c == '(' {
      in_parens = true
      prev_char = c
      continue
    }
    if c == ')' {
      in_parens = false
      prev_char = c
      continue
    }
    if in_parens && c == '=' {
      let prev_ok = prev_char != '=' &&
        prev_char != '!' &&
        prev_char != '<' &&
        prev_char != '>'
      let next_char = if k + 1 < chars.length() {
        chars[k + 1]
      } else {
        '\u0000'
      }
      if prev_ok && next_char != '=' {
        return Some((offsets[k], offsets[k] + char_utf8_len(c)))
      }
    }
    prev_char = c
  }
  None
}

///|
/// 标量的 UTF-8 编码长度（码点判段——与 util 的 utf8 通道逐字符编码量
/// 一致；`for c in` 迭代单位是标量〔代理对自动合并，探针实证 2026-10-02〕）。
fn char_utf8_len(c : Char) -> Int {
  let cp = c.to_int()
  if cp < 0 {
    1
  } else if cp < 0x80 {
    1
  } else if cp < 0x800 {
    2
  } else if cp < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// 行尾 trim 后的 UTF-8 字节长（Rust `line_text.trim_end().len()`）。
/// 空白集 = 空格/\t/\r/\n（C 源码行尾可达域；全量 Unicode 空白简化
/// 登记——见文件头分叉注）。
fn trim_end_byte_len(s : String) -> Int {
  let bytes = @util.utf8_bytes(s)
  let mut end = bytes.length()
  while end > 0 {
    let b = bytes[end - 1].to_int()
    if b == 0x20 || b == 0x09 || b == 0x0d || b == 0x0a {
      end = end - 1
    } else {
      break
    }
  }
  end
}
