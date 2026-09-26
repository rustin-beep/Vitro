// util 白盒锚（G-1）：每件机器可验的行为契约。str_cmp 的锚刻意覆盖
// 陷阱 #29 的实证反例（"delta" vs "charlie"——内置比较在此为 false）。

///|
test "utf8_len_ascii_and_multibyte" {
  assert_eq(utf8_len("hello"), 5, msg="ASCII 字节数 = 码元数")
  assert_eq(utf8_len("你好"), 6, msg="中文每字 3 字节")
  assert_eq(utf8_len(""), 0, msg="空串")
  // 码元数 vs 字节数的分界：同串两个口径必须不等（length()=3, utf8_len=7）
  let s = "你a好"
  assert_eq(s.length(), 3, msg="码元数（BMP 内中文占 1 码元）")
  assert_eq(utf8_len(s), 7, msg="UTF-8 字节数（中文每字 3 字节）")
}

///|
test "str_cmp_dict_order_contrapositive" {
  assert_eq(
    str_cmp("delta", "charlie"),
    1,
    msg="字典序 delta>charlie（内置比较此处为 false——陷阱 #29 反例）",
  )
  assert_eq(str_cmp("abc", "abc"), 0, msg="相等")
  assert_eq(str_cmp("abc", "abd"), -1, msg="末位分出")
  assert_eq(str_cmp("abc", "ab"), 1, msg="前缀者大")
  assert_eq(str_cmp("ab", "abc"), -1, msg="短者小")
  assert_eq(str_cmp("", ""), 0, msg="双空")
  assert_eq(str_cmp("", "a"), -1, msg="空最小")
}

///|
test "i64_to_i32_bits_truncation" {
  assert_eq(i64_to_i32_bits(0L), 0, msg="零")
  assert_eq(i64_to_i32_bits(42L), 42, msg="界内直通")
  assert_eq(i64_to_i32_bits(2147483647L), 2147483647, msg="i32 MAX")
  assert_eq(
    i64_to_i32_bits(2147483648L),
    -2147483648,
    msg="MAX+1 回绕 MIN（低 32 位符号解释）",
  )
  assert_eq(i64_to_i32_bits(4294967295L), -1, msg="0xFFFFFFFF → -1")
  assert_eq(
    i64_to_i32_bits(4294967296L),
    0,
    msg="0x100000000 → 0（高 32 位丢弃）",
  )
  assert_eq(i64_to_i32_bits(-1L), -1, msg="负一全 1 低 32 位 → -1")
  assert_eq(
    i64_to_i32_bits(-9223372036854775807L - 1L),
    0,
    msg="i64 MIN 低 32 位为 0",
  )
}

///|
test "le_u32_u64_at_known_bytes" {
  let b : FixedArray[Byte] = FixedArray::make(8, b'\x00')
  // 0x12345678 LE = 78 56 34 12
  b[0] = b'\x78'
  b[1] = b'\x56'
  b[2] = b'\x34'
  b[3] = b'\x12'
  assert_eq(le_u32_at(b, 0), 0x12345678U, msg="u32 小端拼装")
  // 0x0102030405060708 LE = 08 07 06 05 04 03 02 01
  b[4] = b'\x08'
  b[5] = b'\x07'
  b[6] = b'\x06'
  b[7] = b'\x05'
  assert_eq(
    le_u64_at(b, 0),
    0x0506070812345678UL,
    msg="u64 小端拼装（含前四字节）",
  )
  // 全零
  let z : FixedArray[Byte] = FixedArray::make(8, b'\x00')
  assert_eq(le_u32_at(z, 0), 0U, msg="全零 u32")
  assert_eq(le_u64_at(z, 0), 0UL, msg="全零 u64")
}
