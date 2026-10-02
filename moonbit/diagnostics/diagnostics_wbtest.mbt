// 白盒锚：机制内部件行为（safe_byte_col 三级退化 / split_lines 边界 /
// ascii_lower / trim_end_byte_len）——黑盒锚见 diagnostics_test.mbt。

///|
test "wb_safe_byte_col_three_level" {
  let line = "int 中文变量 = 1;" // 21 字节 / 13 标量（变 = 字节 10）
  // ① 合法字节边界直通
  inspect(safe_byte_col(line, 0), content="0")
  inspect(safe_byte_col(line, 4), content="4") // 「中」起点（首字节非续）
  inspect(safe_byte_col(line, 21), content="21") // 行尾
  // ② 非边界回退标量序：6 → 第 6 个标量「变」的字节起点 10
  inspect(safe_byte_col(line, 6), content="10")
  inspect(safe_byte_col(line, 9), content="17") // 第 9 个 = '=' 字节起点
  // ③ 越界 clamp 行字节长
  inspect(safe_byte_col(line, 99), content="21")
  // 负值：绕过第一分支，回退永不命中 → clamp（Rust as usize 环绕同形）
  inspect(safe_byte_col(line, -1), content="21")
}

///|
test "wb_split_lines_rust_semantics" {
  inspect(split_lines(""), content="[]") // 空串 0 行
  inspect(split_lines("a"), content="[a]")
  inspect(split_lines("a\n"), content="[a]") // 尾随 \n 不产空尾行
  inspect(split_lines("a\nb"), content="[a, b]")
  // Rust "\n".lines() = [""]（一个空行）
  assert_eq(split_lines("\n").length(), 1)
  assert_true(split_lines("\n")[0].is_empty())
  // \r\n 剥 \r
  inspect(split_lines("a\r\nb"), content="[a, b]")
}

///|
test "wb_ascii_lower" {
  inspect(
    ascii_lower("Stack Overflow：栈溢出"),
    content="stack overflow：栈溢出",
  )
  inspect(ascii_lower("CALL STACK"), content="call stack")
}

///|
test "wb_trim_end_byte_len" {
  inspect(trim_end_byte_len("int x = 1;   \t"), content="10") // "int x = 1;" = 10 字节，尾空白剥除
  inspect(trim_end_byte_len("中文 "), content="6") // 剥尾空格后 3+3 字节
  inspect(trim_end_byte_len("  "), content="0")
}

///|
test "wb_find_single_equals_edge_forms" {
  // 孤立 = 命中（括号内、prev/next 非 = ! < >）
  inspect(find_single_equals_in_condition("if (a = b)"), content="Some((6, 7))")
  // == 不命中（next_char == '='）
  inspect(find_single_equals_in_condition("if (a == b)"), content="None")
  // <= 不命中（prev_char == '<'）
  inspect(find_single_equals_in_condition("while (i <= n)"), content="None")
  // 括号外不命中
  inspect(find_single_equals_in_condition("a = b; if (c)"), content="None")
  // 中文偏移：括号内 = 的字节位累计（设=3 字节，在=3 字节；x = y 的 = 在 17）
  inspect(
    find_single_equals_in_condition("设 a = 1 在 (x = y)"),
    content="Some((17, 18))",
  )
}

///|
test "wb_round_to_f32_f32_parity" {
  // F6 修复锚：oracle f32 的 f64 展开形态（2/3 与 3/7 系原锚零判别力的
  // 补样——3/4 十进制精确值两侧同 0.75 测不出宽度差）
  inspect(round_to_f32(2.0 / 3.0), content="0.6666666865348816") // f32 0x3F2AAAAB
  inspect(round_to_f32(3.0 / 7.0), content="0.4285714328289032") // f32 0x3EDB6DB7
  // 精确值直通
  inspect(round_to_f32(0.75), content="0.75")
  inspect(round_to_f32(1.0 / 4.0), content="0.25")
  inspect(round_to_f32(0.0), content="0")
  // 进位跨界：0.9999999999999999（f64 最大 <1）→ 舍到 1.0
  inspect(round_to_f32(0.9999999999999999), content="1")
  // 满命中 5/5（confidence 1.0 可达形态）
  inspect(round_to_f32(5.0 / 5.0), content="1")
}

// wire 文本锚（原 wb_f32_shortest_text_wire_form）随审阅 P1 销案退役：
// f32 最短文本（0.6666667）系对 oracle 序列化路径的误判——json! 走
// Value 路径先提升 f64，wire 恒 f64 最短文本。文本面锁定移至 gateway
// 的 probe_confidence_wire_text（原始字节锚，含 1.0 形态）；本包只锚
// 值面（上锚 round_to_f32 位模式对齐 oracle `as f32`）。
