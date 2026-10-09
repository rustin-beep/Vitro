// M2 修复应用器（历史出处 auto_fix.rs，2026-10-02；已随删区消失，tag
// rust-oracle-freeze 可回溯）：按 FixTarget 的 fix_kind 对源码执行
// Replace/Insert/Delete。**全程字节域**——行切分/
// 列换算/切片拼接一律在 UTF-8 字节序列上做（坐标契约 = 字节偏移；
// MoonBit String 是 UTF-16，码元域切片会错位或 raise）。
//
// 分叉登记（批五注释清理收口 2026-10-09：现状维持）：safe_byte_col
// 三级退化（合法字节位优先 → 非边界回退按**标量序**解释 → 越界 clamp
// 行长）继承自 Rust 勘察 S1「症状治疗」的兜底形态——UTF-8 非边界
// 回退属罕见面，维持现状；坐标口径单源化（勘察 ⑤-2）随 CS/后续批
// 裁定不变。Rust 负数 i32 经 `as usize` 环绕成巨数后落入回退分支终于
// clamp——本实现负数直接走回退分支（行为同形）。

///|
/// 应用修复（Rust apply_fix 照搬）：fix_kind 1/2/3 分派，其余 None。
pub fn apply_fix(source : String, target : FixTarget) -> String? {
  match target.fix_kind {
    1 => apply_replace(source, target)
    2 => apply_insert(source, target)
    3 => apply_delete(source, target)
    _ => None
  }
}

///|
/// 行切分（Rust `str::lines()` 语义）：按 \n 切、行尾 \r 剔除、
/// 尾随 \n 不产空尾行、空串 = 0 行。**pub**（段三接线 2026-10-02）：
/// generate_fix 的 source_lines 参数口径单源——gateway 编译管线与
/// probe 共用，勿在消费侧再写一份 lines 语义。
pub fn split_lines(source : String) -> Array[String] {
  if source.is_empty() {
    return []
  }
  let bytes = @util.utf8_bytes(source)
  let lines : Array[String] = []
  let mut line_start = 0
  let mut i = 0
  while i < bytes.length() {
    if bytes[i].to_int() == 0x0a {
      // 行段 [line_start, i)，\r\n 序列剥 \r
      let mut end = i
      if end > line_start && bytes[end - 1].to_int() == 0x0d {
        end = end - 1
      }
      lines.push(@util.utf8_text(bytes_slice(bytes, line_start, end)))
      i = i + 1
      line_start = i
    } else {
      i = i + 1
    }
  }
  // 尾段：尾随 \n 不产空尾行
  let ended_with_newline = bytes.length() > 0 &&
    bytes[bytes.length() - 1].to_int() == 0x0a
  if !ended_with_newline {
    lines.push(@util.utf8_text(bytes_slice(bytes, line_start, bytes.length())))
  }
  lines
}

///|
/// 字节序列的 [from, until) 段（Bytes 无 slice——Array 中转）。
fn bytes_slice(bytes : Bytes, from : Int, until : Int) -> Bytes {
  let out : Array[Byte] = []
  for i = from; i < until; i = i + 1 {
    out.push(bytes[i])
  }
  Bytes::from_array(out)
}

///|
/// 列号安全换算（Rust safe_byte_col 照搬）：优先按字节边界解释；
/// 非边界（或越界/负值）回退按**标量序**第 col 个的字节起点；最终
/// clamp 到行字节长。任何输入不 raise。
fn safe_byte_col(line : String, col : Int) -> Int {
  let bytes = @util.utf8_bytes(line)
  if col >= 0 && col <= bytes.length() && is_char_boundary(bytes, col) {
    return col
  }
  let mut idx = 0
  let mut cnt = 0
  for c in line {
    if cnt == col {
      return idx
    }
    idx = idx + char_utf8_len(c)
    cnt = cnt + 1
  }
  bytes.length()
}

///|
/// 字节位是否标量边界（Rust is_char_boundary：位上或行尾、且非续字节）。
fn is_char_boundary(bytes : Bytes, pos : Int) -> Bool {
  if pos == bytes.length() {
    return true
  }
  let b = bytes[pos].to_int()
  !(b >= 0x80 && b <= 0xbf)
}

///|
/// 行字节序列的 [from, until) 段。
fn line_bytes_between(line : String, from : Int, until : Int) -> Bytes {
  bytes_slice(@util.utf8_bytes(line), from, until)
}

///|
fn apply_replace(source : String, t : FixTarget) -> String? {
  let lines = split_lines(source)
  let start_line = t.replace_start_line
  let end_line = t.replace_end_line
  if start_line == 0 ||
    end_line == 0 ||
    start_line > lines.length() ||
    end_line > lines.length() {
    return None
  }
  let start_idx = start_line - 1
  let end_idx = end_line - 1
  let start_col = safe_byte_col(lines[start_idx], t.replace_start_column)
  let end_col = safe_byte_col(lines[end_idx], t.replace_end_column)
  if start_col > end_col && start_idx == end_idx {
    return None
  }
  let new_line = @util.utf8_text(
    line_bytes_between(lines[start_idx], 0, start_col) +
    @util.utf8_bytes(t.replacement_text) +
    line_bytes_between(
      lines[end_idx],
      end_col,
      @util.utf8_bytes(lines[end_idx]).length(),
    ),
  )
  Some(replace_line_range(lines, start_idx, end_idx, new_line))
}

///|
fn apply_insert(source : String, t : FixTarget) -> String? {
  let lines = split_lines(source)
  let start_line = t.replace_start_line
  if start_line == 0 || start_line > lines.length() {
    return None
  }
  let idx = start_line - 1
  let start_col = safe_byte_col(lines[idx], t.replace_start_column)
  let line_len = @util.utf8_bytes(lines[idx]).length()
  let new_line = @util.utf8_text(
    line_bytes_between(lines[idx], 0, start_col) +
    @util.utf8_bytes(t.replacement_text) +
    line_bytes_between(lines[idx], start_col, line_len),
  )
  Some(replace_line_range(lines, idx, idx, new_line))
}

///|
fn apply_delete(source : String, t : FixTarget) -> String? {
  let lines = split_lines(source)
  let start_line = t.replace_start_line
  let end_line = t.replace_end_line
  if start_line == 0 ||
    end_line == 0 ||
    start_line > lines.length() ||
    end_line > lines.length() {
    return None
  }
  let start_idx = start_line - 1
  let end_idx = end_line - 1
  let start_col = safe_byte_col(lines[start_idx], t.replace_start_column)
  let end_col = safe_byte_col(lines[end_idx], t.replace_end_column)
  if start_col > end_col && start_idx == end_idx {
    return None
  }
  let end_len = @util.utf8_bytes(lines[end_idx]).length()
  let new_line = @util.utf8_text(
    line_bytes_between(lines[start_idx], 0, start_col) +
    line_bytes_between(lines[end_idx], end_col, end_len),
  )
  Some(replace_line_range(lines, start_idx, end_idx, new_line))
}

///|
/// 行表 [start..=end] 区间替换为单行 + "\n" join（Rust drain+insert+join）。
fn replace_line_range(
  lines : Array[String],
  start_idx : Int,
  end_idx : Int,
  new_line : String,
) -> String {
  let buf = StringBuilder()
  let mut first = true
  for i = 0; i < start_idx; i = i + 1 {
    if !first {
      buf.write_char('\n')
    }
    first = false
    buf.write_string(lines[i])
  }
  if !first {
    buf.write_char('\n')
  }
  buf.write_string(new_line)
  for i = end_idx + 1; i < lines.length(); i = i + 1 {
    buf.write_char('\n')
    buf.write_string(lines[i])
  }
  buf.to_string()
}
