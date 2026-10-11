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

///|
test "utf8_text_partial_三态_基础中文代理对与截断止" {
  // ASCII 单字节
  inspect(utf8_text_partial(b"hi"), content="hi")
  // 中文三字节（「中」= E4 B8 AD）
  inspect(utf8_text_partial(b"\xe4\xb8\xad"), content="中")
  // 四字节 emoji（😀 = U+1F600）：String.length=2 证代理对编码成立；
  // unsafe_char_at(0) 按码点返回合并值 128512（API 形态锚自 cli_wbtest 随迁）
  let s3 = utf8_text_partial(b"\xf0\x9f\x98\x80")
  inspect(s3.length(), content="2")
  inspect(s3.get_char(0).unwrap().to_int(), content="128512")
  // 尾不完整三字节（2 字节截断）——不抛，输出已解码前缀（空）
  inspect(utf8_text_partial(b"\xe4\xb8"), content="")
  // 中段截断：合法前缀 + 截断尾（「hi」+ 半个「中」→ 前缀止）
  inspect(utf8_text_partial(b"hi\xe4\xb8"), content="hi")
}

///|
test "base64_encode_rfc4648_向量全集" {
  inspect(base64_encode(b""), content="")
  inspect(base64_encode(b"f"), content="Zg==")
  inspect(base64_encode(b"fo"), content="Zm8=")
  inspect(base64_encode(b"foo"), content="Zm9v")
  inspect(base64_encode(b"foob"), content="Zm9vYg==")
  inspect(base64_encode(b"fooba"), content="Zm9vYmE=")
  inspect(base64_encode(b"foobar"), content="Zm9vYmFy")
}

///|
/// base64_decode 对偶锚（#70 第二步）：encode→decode 往返 + 尾填充三形态。
test "base64_decode_roundtrip" {
  for payload in [b"hello", b"a", b"ab", b"abc", b""] {
    let enc = base64_encode(payload)
    let dec = base64_decode(enc)
    assert_true(dec is Some(_), msg="往返可解")
    assert_eq(dec.unwrap(), payload, msg="往返逐字节")
  }
  assert_true(base64_decode("!!!") is None, msg="非法字符 fail loud")
}
