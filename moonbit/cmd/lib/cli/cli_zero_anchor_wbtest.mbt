// cmd/lib/cli 零锚区补锚（2026-10-04 二轮审「锚覆盖」结构性发现：
// 初版 7 锚全落 parse_run_args/utf8_decode（后者已上提 util），escape_json /
// extract_json_string_field / count_payloads / parse_int 零锚——
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
  // B3 批（2026-11-02，M35 C5）：安慰性锚升级——旧形态只 inspect core
  // `String::has_prefix` 行为，不触达 api 解析循环（A1 未知旗标缺陷恰落此
  // 零覆盖区而锚全绿）。现改真实调用：params 非 `{` 开头 → rc=4 用法错；
  // 缺省 params → "{}" 正常执行 rc=0。
  assert_eq(
    api(
      ["ping", "not-json"],
      () => b"",
      write_stdout=noop_write,
      channel=fake_channel(),
    ),
    4,
    msg="params 非 JSON 对象字面量 → rc=4",
  )
  assert_eq(
    api(["ping"], () => b"", write_stdout=noop_write, channel=fake_channel()),
    0,
    msg="缺省 params 走 {} 正常执行",
  )
}

///|
test "api_batch_行解析形态" {
  // B3 批（M35 C5）同款升级：旧形态只 inspect core `String::trim`。现真实
  // 走 --batch：CRLF 行尾 + 空白行 + 尾换行混合 NDJSON，空行跳过、每非空行
  // 一次 invoke——fake_channel 全 ok 帧 → rc=0；喂空 stdin → rc=4 用法错。
  // （Bytes 字面量直写——不经 util 包的 utf8_bytes，免给 surface 边表添一条
  // wbtest 消费边；帧文本纯 ASCII，字节即文本。）
  let frames : Bytes = b"{\"id\":1,\"method\":\"ping\",\"params\":{}}\r\n\r\n  \t\n{\"id\":2,\"method\":\"ping\",\"params\":{}}\n"
  assert_eq(
    api(
      ["--batch"],
      () => frames,
      write_stdout=noop_write,
      channel=fake_channel(),
    ),
    0,
    msg="CRLF/空白行耐受，非空帧全 ok → rc=0",
  )
  assert_eq(
    api(["--batch"], () => b"", write_stdout=noop_write, channel=fake_channel()),
    4,
    msg="--batch 空 stdin → rc=4",
  )
}

///|
