// cmd/lib/run 白盒锚（#37 批②③）——参数解析偏移约定与 UTF-8 解码。
// J9：锚先于行为存在（parse_run_args/utf8_decode 是本批新面）。

///|
test "parse_run_args_偏移约定_透传与旗标" {
  // 薄壳形态 args[1:] / 总入口 args[2:] 对 lib 零差异——锚定「已剥子命令名」
  let ra = parse_run_args([
    "x.c", "--dump-memory", "out.bin", "-i", "in.txt", "--", "a1", "a2",
  ])
  inspect(ra.file, content="x.c")
  inspect(ra.dump_mem, content="out.bin")
  inspect(ra.stdin_file, content="in.txt")
  inspect(ra.argv_passthrough.length(), content="2")
  inspect(ra.argv_passthrough[0], content="a1")
  inspect(ra.argv_passthrough[1], content="a2")
  inspect(ra.json_mode, content="false")
}

///|
test "parse_run_args_透传域内的旗标形不解析" {
  // `--` 之后一切照收（含 -i/--json 字面量——透传域零解析）
  let ra = parse_run_args(["x.c", "--", "--json", "-i"])
  inspect(ra.argv_passthrough.length(), content="2")
  inspect(ra.json_mode, content="false")
  inspect(ra.stdin_file, content="")
}

///|
test "parse_run_args_json 与 stdin 占位" {
  let ra = parse_run_args(["--json", "-"])
  inspect(ra.json_mode, content="true")
  inspect(ra.file, content="-") // `-` 占位接收（批③ stdin 源）
}

///|
test "utf8_decode_基础与中文与代理对" {
  // ASCII
  let b1 = b"hi"
  inspect(utf8_decode(b1), content="hi")
  // 中文三字节（「中」= E4 B8 AD）
  let b2 = b"\xe4\xb8\xad"
  inspect(utf8_decode(b2), content="中")
  // 四字节 emoji（😀 = U+1F600）：String.length=2 证代理对编码成立；
  // unsafe_char_at(0) 按码点返回合并值 128512（0x1F600——实测 API 形态）
  let b3 = b"\xf0\x9f\x98\x80"
  let s3 = utf8_decode(b3)
  inspect(s3.length(), content="2")
  inspect(s3.unsafe_char_at(0).to_int(), content="128512")
}

///|
test "utf8_decode_截断序列静默止" {
  // 尾不完整三字节（2 字节截断）——不抛，输出已解码前缀
  let b = b"\xe4\xb8"
  inspect(utf8_decode(b), content="")
}
