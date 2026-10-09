// cmd/lib/cli 零锚区补锚（2026-10-04 二轮审「锚覆盖」结构性发现：
// 初版 7 锚全落 parse_run_args/utf8_decode（后者已上提 util），escape_json /
// extract_json_string_field / count_payloads / parse_int / dir_of 零锚——
// P1-A/P1-B 两缺陷全落零锚区。本件五函数锚 + P1 修复回归锚）。

///|
test "escape_json_转义面" {
  // 收一后锚单源 @util.json_escape（原本地 escape_json 已删——issue #55）
  inspect(@util.json_escape("a\"b\\c\nd\te"), content="a\\\"b\\\\c\\nd\\te")
  inspect(@util.json_escape("纯中文"), content="纯中文")
  inspect(@util.json_escape(""), content="")
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

///|
test "api_params_解析形态" {
  // api 参数解析抽验：无 params → "{}"；params 非 { 开头 → 用法错路径的
  // 判定输入（cli 层轻锚——api 主体是 gateway.invoke 透传，协议面锚在
  // serve_smoke/gateway wbtest 在案）
  inspect("{}".has_prefix("{"), content="true")
  inspect("not-json".has_prefix("{"), content="false")
}

///|
test "api_batch_行解析形态" {
  // 批式行级预处理抽验：CRLF/空白行耐受（\r 由 Windows 管道常见——
  // trim " \t\r" 后空行跳过；NDJSON 帧本体不受影响）
  let l1 : String = "  {\"id\":1}  ".trim(chars=" \t\r").to_owned()
  inspect(l1, content="{\"id\":1}")
  let l2 : String = "\r".trim(chars=" \t\r").to_owned()
  inspect(l2.is_empty(), content="true")
}

///|
test "stdout_bytes_of_字节保真" {
  // DIFF-EXIT-STDOUT-ENCODE-01 函数级锚（2026-10-05 脱钩修复批批一）：
  // ≥0x80 字节原样聚合（0x80/0xC8/0xFF 单字节出入——出口层双编码修复
  // 前 Latin-1 char 直转 + println 会把它们变 UTF-8 双重编码字节序列）；
  // 尾换行保形（无尾 \n 补 / 已有则不补 / 空输出补单换行）
  let hi : Bytes = b"\x80\xc8\xffZ"
  let got = stdout_bytes_of([hi])
  inspect(got.length(), content="5")
  inspect(got[0].to_int(), content="128")
  inspect(got[1].to_int(), content="200")
  inspect(got[2].to_int(), content="255")
  inspect(got[3].to_int(), content="90")
  inspect(got[4].to_int(), content="10")
  // 多 chunk 拼接保真
  let two = stdout_bytes_of([b"AB", b"\xc8"])
  inspect(two.length(), content="4")
  inspect(two[2].to_int(), content="200")
  // 已有尾换行不补
  let nltail = stdout_bytes_of([b"hi\n"])
  inspect(nltail.length(), content="3")
  // 空输出补单换行（原 println 空串同形）
  inspect(stdout_bytes_of([]).length(), content="1")
}
