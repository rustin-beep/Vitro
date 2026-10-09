///|
test "json_escape five named escapes" {
  inspect(json_escape("a\"b\\c\nd\re\tf"), content="a\\\"b\\\\c\\nd\\re\\tf")
}

///|
test "json_escape control chars full coverage" {
  // U+0000–001F 中非五具名转义的其余控制字符一律 \u00XX（issue #55：
  // diag E4 出口曾只转五个、其余原样写出=非法 JSON）
  inspect(json_escape("a\u{0}b"), content="a\\u0000b")
  inspect(json_escape("a\u{1}b"), content="a\\u0001b")
  inspect(json_escape("a\u{B}b"), content="a\\u000bb")
  inspect(json_escape("a\u{C}b"), content="a\\u000cb")
  inspect(json_escape("a\u{1F}b"), content="a\\u001fb")
}

///|
test "json_escape passthrough above 0x20" {
  // ≥ 0x20（含非 ASCII 多字节）原样透传；length 按码点计=8
  let out = json_escape("中文 @ $ 漢")
  inspect(out, content="中文 @ $ 漢")
  assert_eq(out.length(), 8)
}

///|
test "json_escape_into writes same bytes as pure version" {
  let pure = json_escape("x\u{7}y\"z")
  let buf = StringBuilder()
  json_escape_into("x\u{7}y\"z", buf)
  assert_eq(buf.to_string(), pure)
}
