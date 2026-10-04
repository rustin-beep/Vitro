// cmd/lib/cli 零锚区补锚（2026-10-04 二轮审「锚覆盖」结构性发现：
// 初版 7 锚全落 parse_run_args/utf8_decode，escape_json /
// extract_json_string_field / count_payloads / parse_int / dir_of 零锚——
// P1-A/P1-B 两缺陷全落零锚区。本件五函数锚 + P1 修复回归锚）。

///|
test "escape_json_转义面" {
  inspect(escape_json("a\"b\\c\nd\te"), content="a\\\"b\\\\c\\nd\\te")
  inspect(escape_json("纯中文"), content="纯中文")
  inspect(escape_json(""), content="")
}

///|
test "extract_json_string_field_提取与转义" {
  let j = "{\"trap_message\":\"程序执行步数超过限制（100 步）\",\"x\":1}"
  inspect(
    extract_json_string_field(j, "trap_message"),
    content="程序执行步数超过限制（100 步）",
  )
  // 值内 \" 转义还原
  let j2 = "{\"m\":\"a\\\"q\\nb\"}"
  inspect(extract_json_string_field(j2, "m"), content="a\"q\nb")
  // 键不存在 → 空
  inspect(extract_json_string_field(j, "nope"), content="")
}

///|
test "count_payloads_帧计数" {
  let b = "{\"payloads\":[{\"step_index\":0,\"x\":1},{\"step_index\":1},{}],\"finished\":false}"
  inspect(count_payloads(b), content="2")
  inspect(count_payloads("{\"payloads\":[],\"finished\":true}"), content="0")
  inspect(count_payloads("{\"finished\":true}"), content="0")
}

///|
test "parse_int_严格形态" {
  inspect(parse_int("123"), content="Some(123)")
  inspect(parse_int("0"), content="Some(0)")
  // 非数字/空 → None（调用方判用法错——静默 default 已弃）
  inspect(parse_int("abc"), content="None")
  inspect(parse_int("12x"), content="None")
  inspect(parse_int(""), content="None")
}

///|
test "dir_of_双分隔符" {
  inspect(dir_of("dir/sub/x.c"), content="dir/sub")
  inspect(dir_of("dir\\sub\\x.c"), content="dir\\sub")
  inspect(dir_of("x.c"), content=".")
}

///|
test "parse_run_args_P1A_零透传不吞文件位" {
  // P1-A 回归锚：零透传时 file 仍在（argv 恒下发的前置——json 分支曾把
  // 零参 argv 整段丢成 {}，gateway argc=0 / argv[0] NULL trap）
  let ra = parse_run_args(["only.c"])
  inspect(ra.file, content="only.c")
  inspect(ra.argv_passthrough.length(), content="0")
}
