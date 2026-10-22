// cmd/lib/run 白盒锚（#37 批②③）——参数解析偏移约定与 UTF-8 解码。
// J9：锚先于行为存在（parse_run_args 是本批新面；utf8_decode 三态锚
// 2026-10-06 随函数上提 util_wbtest〔util.utf8_text_partial〕，本文件不再持锚）。
// main.js 退役批（2026-10-16）：lib/cli 纯逻辑化（gateway 依赖出走
// engine_direct）后，本文件引擎路径用 fake channel（method-aware 桩——
// 测试与引擎隔离，浅路径断言零引擎依赖）。

///|
fn fake_channel() -> EngineChannel {
  {
    invoke: fn(line : String) -> String {
      // method-aware 最小桩：编译过 + run finished + step.next finished
      if line.contains("\"method\":\"compile\"") {
        "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"diagnostics\":[]}}"
      } else if line.contains("\"method\":\"run\"") {
        "{\"id\":1,\"ok\":true,\"result\":{\"status\":\"finished\",\"return_value\":0}}"
      } else if line.contains("\"method\":\"step.next\"") {
        "{\"id\":1,\"ok\":true,\"result\":{\"finished\":true}}"
      } else if line.contains("\"method\":\"output.delta\"") {
        // decode_delta_stdout 对缺失 delta 字段是负索引崩——桩必须带字段
        "{\"id\":1,\"ok\":true,\"result\":{\"delta\":\"\"}}"
      } else {
        "{\"id\":1,\"ok\":true,\"result\":{}}"
      }
    },
    invoke_parsed: fn(_line : String) -> Json? { None },
    reset: fn() { () },
    set_clock: fn(_c) { () },
    set_include_reader: fn(_r) { () },
    compile_params: fn(file : String, src : String) -> String {
      "{\"source\":\"\{@util.json_escape(src)}\",\"filename\":\"\{@util.json_escape(file)}\"}"
    },
  }
}

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
/// #211 锚（2026-10-22）：--realtime 解析（time()/clock() 真墙钟——
/// config.set 的 deterministic 置 false）；透传域内旗标形不解析同款。
test "parse_run_args_realtime" {
  let ra = parse_run_args(["--realtime", "x.c"])
  inspect(ra.realtime, content="true")
  inspect(ra.file, content="x.c")
  // 默认关（判分可复现口径）+ 透传域零解析
  inspect(parse_run_args(["x.c"]).realtime, content="false")
  inspect(parse_run_args(["x.c", "--", "--realtime"]).realtime, content="false")
}

///|
test "parse_run_args_多位参数_首为文件余进 argv（Rust 口径）" {
  let ra = parse_run_args(["ok.c", "extra1", "extra2"])
  inspect(ra.file, content="ok.c")
  inspect(ra.argv_passthrough.length(), content="2")
  inspect(ra.argv_passthrough[0], content="extra1")
  inspect(ra.argv_passthrough[1], content="extra2")
}

///|
test "parse_run_args_裸位置参数与__透传合流" {
  let ra = parse_run_args(["ok.c", "a", "--", "b"])
  inspect(ra.file, content="ok.c")
  inspect(ra.argv_passthrough.length(), content="2")
  inspect(ra.argv_passthrough[0], content="a")
  inspect(ra.argv_passthrough[1], content="b")
}

///|
test "cli_api_help_清单与详情_rc 三态" {
  // #67 红→绿锚（2026-10-11）：api help 离线可发现性出口——改前 `help`
  // 走 invoke 得「未知方法」帧（rc=1）、`help compile` 的 compile 被当
  // params 非 JSON 对象（rc=4）。输出内容断言由 vitro_cli_smoke 双臂
  // 对拍承担（逻辑层 println 无捕获面，这里锚 rc 语义）。
  assert_eq(api(["help"], () => b"", channel=fake_channel()), 0) // 改前红位：help 走 invoke=未知方法帧 rc=1
}

///|
test "cli_api_help_detail_单方法与未知方法" {
  // 接线后：help compile → 0；help no.such → 4（用法错）
  assert_eq(api(["help", "compile"], () => b"", channel=fake_channel()), 0)
  assert_eq(
    api(["help", "no.such.method"], () => b"", channel=fake_channel()),
    4,
  )
}

///|
/// 病 87 残留⑤⑦锚（2026-10-13 方案 A，用户拍板）：compile 多余位置
/// 参数 / step 未知旗标与多余位置参数 → rc=4 fail loud（run 域 DX P1
/// 已严格——子命令间不一致尾巴收口；rc=4 语义在 spec §2 契约内零变更）。
test "b87_compile_step_strict_args" {
  // compile 多余位置参数（旧 rc=0 静默丢 extra）
  let rc1 = compile(
    ["tmp_probe.c", "extra.c"],
    () => b"int main(){return 0;}",
    channel=fake_channel(),
  )
  assert_eq(rc1, 4, msg="compile 多余位置参数须 rc=4")
  // compile 未知旗标
  let rc2 = compile(
    ["--bogus", "a.c"],
    () => b"int main(){return 0;}",
    channel=fake_channel(),
  )
  assert_eq(rc2, 4, msg="compile 未知旗标须 rc=4")
  // step 未知旗标（旧 rc=0 静默吞照常出帧）
  let out3 = []
  let rc3 = step(
    ["a.c", "--xyz"],
    () => b"int main(){return 0;}",
    channel=fake_channel(),
    fn(b) { out3.push(b) },
  )
  assert_eq(rc3, 4, msg="step 未知旗标须 rc=4")
  // 合法参数不受影响（回归面：--max-steps 正常路径；源走 stdin "-"
  // 通道——wbtest 沙箱读不到磁盘 a.c，rc=4 会是 IO 语义混入参数断言）
  let rc4 = step(
    ["-", "--max-steps", "50"],
    () => b"int main(){return 0;}",
    channel=fake_channel(),
    fn(_b) { () },
  )
  assert_true(
    rc4 != 4,
    msg="合法路径不因参数被拒（引擎态 rc 任意）",
  )
}
