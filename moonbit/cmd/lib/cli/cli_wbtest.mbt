// cmd/lib/run 白盒锚（#37 批②③）——参数解析偏移约定与 UTF-8 解码。
// J9：锚先于行为存在（parse_run_args 是本批新面；utf8_decode 三态锚
// 2026-10-06 随函数上提 util_wbtest〔util.utf8_text_partial〕，本文件不再持锚）。
// main.js 退役批（2026-10-16）：lib/cli 纯逻辑化（gateway 依赖出走
// engine_direct）后，本文件引擎路径用 fake channel（method-aware 桩——
// 测试与引擎隔离，浅路径断言零引擎依赖）。

///|
/// #366：api 帧出口注入通道的测试桩（白盒锚只判 rc 语义——stdout 字节
/// 对拍由 vitro_cli_smoke 承担）。
fn noop_write(_b : Bytes) -> Unit {
  ()
}

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
  assert_eq(
    api(["help"], () => b"", write_stdout=noop_write, channel=fake_channel()),
    0,
  ) // 改前红位：help 走 invoke=未知方法帧 rc=1
}

///|
test "cli_api_help_detail_单方法与未知方法" {
  // 接线后：help compile → 0；help no.such → 4（用法错）
  assert_eq(
    api(
      ["help", "compile"],
      () => b"",
      write_stdout=noop_write,
      channel=fake_channel(),
    ),
    0,
  )
  assert_eq(
    api(
      ["help", "no.such.method"],
      () => b"",
      write_stdout=noop_write,
      channel=fake_channel(),
    ),
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

///|
/// PR #280 审阅 P2-1 锚（2026-10-23）：--realtime 生效面——解析锚之外，
/// 「旗标 → config.set 下行串」的 deterministic 值两态锁定（旧形态该面
/// 全防线零锚：把 cli_frame 的 det_flag 写死 true 单测全绿）。
test "frame_pipeline_realtime_reaches_config_set" {
  let captured : Array[String] = []
  let ok_frame = fn(m : String) -> String {
    if m == "compile" {
      "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"diagnostics\":[],\"preprocessor_trace\":[]}}"
    } else if m == "run" {
      "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"status\":\"finished\",\"return_value\":0,\"trap\":\"\",\"waiting_input\":false,\"steps_executed\":1}}"
    } else {
      "{\"id\":1,\"ok\":true,\"result\":{\"delta\":\"\",\"cursor\":0,\"total\":0,\"stream\":\"stdout\",\"truncated_bytes\":0}}"
    }
  }
  let chan : EngineChannel = {
    invoke: fn(line : String) -> String {
      if line.contains("\"method\":\"config.set\"") {
        captured.push(line)
      }
      if line.contains("\"method\":\"compile\"") {
        ok_frame("compile")
      } else if line.contains("\"method\":\"run\"") {
        ok_frame("run")
      } else {
        ok_frame("delta")
      }
    },
    invoke_parsed: fn(_line : String) -> Json? {
      // compile 帧走 inv_tree（invoke_parsed）——固定回 ok 帧（json_parse
      // 会 raise，桩内 catch 兜底同 engine_direct 形态）
      Some(
        @util.json_parse(
          "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"diagnostics\":[],\"preprocessor_trace\":[]}}",
        ) catch {
          _ => Json::number(0)
        },
      )
    },
    reset: fn() { () },
    set_clock: fn(_c) { () },
    set_include_reader: fn(_r) { () },
    compile_params: fn(file : String, _src : String) -> String {
      "{\"source\":\"\",\"filename\":\"\{file}\"}"
    },
  }
  let clock = fn() { 0UL }
  let wout = fn(_b : Bytes) { () }
  ignore(
    frame_pipeline(
      "int main(){return 0;}",
      "x.c",
      "",
      [],
      "",
      clock,
      wout,
      false,
      channel=chan,
      realtime=true,
    ),
  )
  assert_true(captured.length() == 1, msg="config.set 恰一次下发")
  assert_true(
    captured[0].contains("\"deterministic\":false"),
    msg="--realtime 下行 deterministic:false",
  )
  captured.clear()
  ignore(
    frame_pipeline(
      "int main(){return 0;}",
      "x.c",
      "",
      [],
      "",
      clock,
      wout,
      false,
      channel=chan,
      realtime=false,
    ),
  )
  assert_true(
    captured[0].contains("\"deterministic\":true"),
    msg="缺省下行 deterministic:true（判分口径）",
  )
}

///|
/// #207/#319（2026-10-31）：run 文本模式 stdout 原样直写锚——不补尾换行。
/// spec §1 契约「stdout 只承载程序输出（字节精确，下游无需剥离）」四口径
/// 统一（clang / `--json` delta / step 文本 / run 文本）。修前形态 = run
/// 文本路径无条件补 `\n`（空输出也补 1 字节，native 经 CRT 再翻成 2 字节
/// CRLF）——下方三断言修前全红（J9：原样 3 字节 / 空输出零调用 / 自带
/// 换行不双补）。
fn stdout_passthrough_channel(stdout_delta : String) -> EngineChannel {
  let delta_json = @util.json_escape(stdout_delta)
  let frame_of = fn(line : String) -> String {
    if line.contains("\"method\":\"compile\"") {
      "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"diagnostics\":[],\"preprocessor_trace\":[]}}"
    } else if line.contains("\"method\":\"run\"") {
      "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"status\":\"finished\",\"return_value\":0,\"trap\":\"\",\"waiting_input\":false,\"steps_executed\":1}}"
    } else if line.contains("\"stream\":\"stdout\"") {
      "{\"id\":1,\"ok\":true,\"result\":{\"delta\":\"\{delta_json}\",\"cursor\":0,\"total\":0,\"stream\":\"stdout\",\"truncated_bytes\":0}}"
    } else {
      "{\"id\":1,\"ok\":true,\"result\":{\"delta\":\"\",\"cursor\":0,\"total\":0,\"stream\":\"stderr\",\"truncated_bytes\":0}}"
    }
  }
  {
    invoke: fn(line : String) -> String { frame_of(line) },
    invoke_parsed: fn(line : String) -> Json? {
      Some(@util.json_parse(frame_of(line)) catch { _ => Json::number(0) })
    },
    reset: fn() { () },
    set_clock: fn(_c) { () },
    set_include_reader: fn(_r) { () },
    compile_params: fn(file : String, _src : String) -> String {
      "{\"source\":\"\",\"filename\":\"\{file}\"}"
    },
  }
}

///|
/// #394 审阅 P2-1 锚（2026-10-31）：stdout 直写后首条 stderr 标记行前的
/// 边界换行决策——无尾换行补 1 字节 `\n`（到 stderr，stdout 字节不动）、
/// 空 stdout 与自带尾换行不补。修前该决策不存在（js 臂 `2>&1` 实测
/// `abc// NOTE …` 粘连成行、native 臂缓冲序反转——三臂合流形态互不一致）。
/// stderr 侧行为锚（子进程捕获字节）在 vitro_cli_smoke B[run 文本口径]。
test "stderr_boundary_newline_三态" {
  // ① 无尾换行：恰 1 字节 \n
  assert_eq(stderr_boundary_newline(b"abc"), b"\n", msg="无尾换行补边界")
  // ② 空 stdout：不补（无行可粘——空输出 stderr 首字节即 //）
  assert_eq(stderr_boundary_newline(b""), b"", msg="空输出不补")
  // ③ 自带尾换行：不双补（行已对齐）
  assert_eq(stderr_boundary_newline(b"a\n"), b"", msg="自带换行不双补")
  // ④ 尾字节恰 \n 前有内容的复合形态
  assert_eq(
    stderr_boundary_newline(b"x\r"),
    b"\n",
    msg="CR 结尾同属无换行形态",
  )
}

///|
test "frame_pipeline_text_stdout_passthrough_no_newline" {
  // ① 程序输出无尾换行：stdout 恰 3 字节原样（修前补 \n 成 4 字节）
  let s1 : Array[Bytes] = []
  let rc1 = frame_pipeline(
    "int main(){return 0;}",
    "x.c",
    "",
    [],
    "",
    fn() { 0UL },
    fn(b : Bytes) { s1.push(b) },
    false,
    channel=stdout_passthrough_channel("abc"),
  )
  assert_true(rc1 == 0, msg="正常结束 rc=0")
  assert_true(s1.length() == 1, msg="stdout 恰一次写出")
  assert_eq(s1[0], b"abc", msg="无尾换行原样直写（#207：不补行）")
  // ② 空输出：write_stdout 零调用（修前写 1 字节 \\n——空输出多 1~2 字节）
  let s2 : Array[Bytes] = []
  let rc2 = frame_pipeline(
    "int main(){return 0;}",
    "x.c",
    "",
    [],
    "",
    fn() { 0UL },
    fn(b : Bytes) { s2.push(b) },
    false,
    channel=stdout_passthrough_channel(""),
  )
  assert_true(rc2 == 0, msg="正常结束 rc=0")
  assert_true(
    s2.length() == 0,
    msg="空输出零写出（clang 同口径 0 字节）",
  )
  // ③ 自带尾换行：原样保留不双补
  let s3 : Array[Bytes] = []
  let rc3 = frame_pipeline(
    "int main(){return 0;}",
    "x.c",
    "",
    [],
    "",
    fn() { 0UL },
    fn(b : Bytes) { s3.push(b) },
    false,
    channel=stdout_passthrough_channel("a\n"),
  )
  assert_true(rc3 == 0, msg="正常结束 rc=0")
  assert_true(s3.length() == 1, msg="stdout 恰一次写出")
  assert_eq(s3[0], b"a\n", msg="自带换行原样（不双补）")
}
