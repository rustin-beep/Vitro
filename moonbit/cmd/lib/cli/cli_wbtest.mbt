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
    write_stdout=noop_write,
    channel=fake_channel(),
  )
  assert_eq(rc1, 4, msg="compile 多余位置参数须 rc=4")
  // compile 未知旗标
  let rc2 = compile(
    ["--bogus", "a.c"],
    () => b"int main(){return 0;}",
    write_stdout=noop_write,
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
  // 通道——wbtest 沙箱读不到磁盘 a.c，rc=4 会是 IO 语义混入参数断言）。
  // B3 批（M35 C5）：原 `rc4 != 4` 宽松断言收紧——fake_channel 的 step.next
  // 回 finished:true，合法路径确定 rc=0
  let rc4 = step(
    ["-", "--max-steps", "50"],
    () => b"int main(){return 0;}",
    channel=fake_channel(),
    fn(_b) { () },
  )
  assert_eq(rc4, 0, msg="合法路径 finished → rc=0")
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

///|
/// B3 批 M35 A6 红→绿锚（2026-11-02）：compile --json 的 diag 帧出口。
/// 修前形态：compile 签名无 write_stdout 注入、frame_pipeline 的 type:diag
/// 帧落 lib 内 drop 通道——失败/成功两路 stdout 均 0 字节（js 臂子进程实测
/// `compile err.c --json` rc=1 且 stdout 0B / stderr 0B，下游拿 rc=1 却无法
/// 得知失败原因；对照 `run err.c --json` 同路径 diag 帧 463B 正常）。本锚
/// 断言注入通道收到 type:diag 帧——帧字节三臂对拍由 vitro_cli_smoke 承担。
fn compile_fail_channel() -> EngineChannel {
  {
    invoke: fn(line : String) -> String {
      if line.contains("\"method\":\"compile\"") {
        // 真实 gateway 形态：外层 ok:true（协议成功执行）+ result.ok:false
        //（编译失败）——frame_pipeline 以 result 段 ok:false 子串判 rc=1
        "{\"id\":1,\"ok\":true,\"result\":{\"ok\":false,\"diagnostics\":[{\"code\":\"E3004\"}]}}"
      } else {
        "{\"id\":1,\"ok\":true,\"result\":{}}"
      }
    },
    invoke_parsed: fn(_line : String) -> Json? { None },
    reset: fn() { () },
    set_clock: fn(_c) { () },
    set_include_reader: fn(_r) { () },
    compile_params: fn(file : String, _src : String) -> String {
      "{\"source\":\"\",\"filename\":\"\{file}\"}"
    },
  }
}

///|
test "m35_a6_compile_json_diag_帧落注入通道" {
  // ① 失败路径：diag 帧必须落 stdout（修前 0 字节——rc=1 只剩退出码）
  let captured : Array[Bytes] = []
  let rc = compile(
    ["-", "--json"],
    () => b"int main() { int x = \"s\"; return 0; }",
    write_stdout=fn(b : Bytes) { captured.push(b) },
    channel=compile_fail_channel(),
  )
  assert_eq(rc, 1, msg="编译失败 rc=1")
  assert_true(
    captured.length() >= 1,
    msg="diag 帧须落注入通道（修前 drop 通道 0 字节）",
  )
  let text = @util.utf8_text_partial(captured[0])
  assert_true(
    text.contains("\"type\":\"diag\""),
    msg="首帧 type:diag 包装（与 run --json 同形）",
  )
  assert_true(text.contains("E3004"), msg="诊断码随帧透出")
  // ② 成功路径：diag 帧同样落 stdout（compile --json 恒出一帧——下游 NDJSON
  // 消费面不因编译成功而拿空流；修前同样 0 字节）
  let ok_captured : Array[Bytes] = []
  let rc_ok = compile(
    ["-", "--json"],
    () => b"int main(){return 0;}",
    write_stdout=fn(b : Bytes) { ok_captured.push(b) },
    channel=fake_channel(),
  )
  assert_eq(rc_ok, 0, msg="编译通过 rc=0")
  assert_true(
    ok_captured.length() >= 1,
    msg="成功路径 diag 帧同样落注入通道",
  )
  // ③ 文本模式不受影响：COMPILE-OK 走 stderr（say），stdout 零写出（文本
  // 模式 compile 帧走 inv_tree——须 invoke_parsed 桩，fake_channel 恒 None
  // 会落「协议破损」臂，故用 stdout_passthrough_channel）
  let txt_captured : Array[Bytes] = []
  let rc_txt = compile(
    ["-"],
    () => b"int main(){return 0;}",
    write_stdout=fn(b : Bytes) { txt_captured.push(b) },
    channel=stdout_passthrough_channel(""),
  )
  assert_eq(rc_txt, 0, msg="文本模式 rc=0")
  assert_true(
    txt_captured.length() == 0,
    msg="文本模式 stdout 恒空（spec §1 不变式）",
  )
}

///|
/// B3 批 M35 A2' 红→绿锚（2026-11-02）：step 子命令 rc=3（步数超限）判定串
/// 与引擎现行文案失配——修前匹配「程序执行步数超过限制」，而引擎 step-limit
/// 模板（teaching/assets/trap_messages_gen.mbt）已是「[step-limit] 程序执行
/// 步数**达到预算上限**（N 步）被安全截断」形态，子串永不命中 → 所有 step-limit
/// 恒落 rc=2；js 臂子进程实测 `step spin.c --max-steps 100` rc=2（契约 §2
/// 应 3），shell 判 `$? == 3` 的教学预算墙脚本全部失灵。
fn step_trap_channel(trap_message_json : String) -> EngineChannel {
  {
    invoke: fn(line : String) -> String {
      if line.contains("\"method\":\"compile\"") {
        "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"diagnostics\":[]}}"
      } else if line.contains("\"method\":\"step.next\"") {
        "{\"id\":1,\"ok\":true,\"result\":{\"payloads\":[],\"finished\":false,\"trapped\":true,\"waiting_input\":false,\"trap_message\":\"\{trap_message_json}\"}}"
      } else if line.contains("\"method\":\"output.delta\"") {
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
test "m35_a2_step_rc3_step_limit_文案匹配" {
  // ① step-limit trap：引擎现行模板渲染形态（trap_messages_gen.mbt 单源；
  // 值内 \n 为 JSON 转义——extract_json_string_field 可见）→ 必须 rc=3
  let rc3 = step(
    ["-", "--max-steps", "100"],
    () => b"int main(){while(1){}return 0;}",
    fn(_b : Bytes) { () },
    channel=step_trap_channel(
      "[step-limit] 程序执行步数达到预算上限（100 步）被安全截断——这是资源墙，不一定是你程序的错误。\\n\\n[cause] 两种可能",
    ),
  )
  assert_eq(
    rc3,
    3,
    msg="step-limit 必须 rc=3（修前匹配旧文案恒 rc=2）",
  )
  // ② 对照：普通 trap（divide-zero 文案）仍 rc=2——判定窄面不外溢
  let rc2 = step(
    ["-"],
    () => b"int main(){int a=1,b=0;return a/b;}",
    fn(_b : Bytes) { () },
    channel=step_trap_channel("[divide-zero] 整数除以零"),
  )
  assert_eq(rc2, 2, msg="非 step-limit trap 仍 rc=2")
  // ③ M35 A2 红→绿：--max-steps 下界域检对齐 run（上界由 parse_int Int32 预检承担——PR #450 审阅 P3-1 勘正）——修前
  // `0` 无下界检查、下发 config.set 被 gateway #94 钳成 1 静默按 1 步跑
  //（fake_channel 下 finished → rc=0）；修后 rc=4 用法错（run 同参数同码）
  assert_eq(
    step(
      ["-", "--max-steps", "0"],
      () => b"int main(){return 0;}",
      fn(_b : Bytes) { () },
      channel=fake_channel(),
    ),
    4,
    msg="--max-steps 0 须 rc=4（修前静默钳 1 跑 rc=0）",
  )
  // ④ M35 A3：尾置缺值 rc=4（修前也 4——但走「未知旗标：--max-steps」误报
  // 臂；文案无捕获面，本锚只锚 rc 回归，文案对齐 run 由代码注释自证）
  assert_eq(
    step(
      ["-", "--max-steps"],
      () => b"int main(){return 0;}",
      fn(_b : Bytes) { () },
      channel=fake_channel(),
    ),
    4,
    msg="--max-steps 尾置缺值 rc=4",
  )
}

///|
/// WASI 期 0（2026-11-05，设计单 §3.1/§5.2 期 0 行）：script 子命令
/// 断言集——argv 收口（文件位后零解析全透传，python/node 惯例）/
/// shebang 剥行（行号零偏移，python 对拍实测 2026-11-05：`#!` 行忽略
/// 但行号照常计数——err.py 报 line 2 / err3.py 报 line 3）/ exit code
/// 透传（C 返回值 & 0xFF——python sys.exit(256)→0 实测锚）。J9：锚先于
/// 实现存在（script 函数族入库前本节编译红——新面无「修前行为」可跑，
/// 编译红即红锚留痕形态）。
test "script_parse_args_文件位后零解析全透传" {
  // python 惯例（实测 argv.py）：文件名后全部参数原样进 argv——含
  // `-i`/`--json` 旗标形与 `--` 字面量（透传域零解析、`--` 无特殊语义）
  let sa = parse_script_args(["x.c", "a", "--json", "-i", "--", "b", "-c"])
  inspect(sa.file, content="x.c")
  inspect(sa.argv.length(), content="6")
  inspect(sa.argv[0], content="a")
  inspect(sa.argv[3], content="--")
  inspect(sa.argv[5], content="-c")
  inspect(sa.unknown_flag is None, content="true")
  // 与 run 的分叉锚：同参数下 run 解析 --json/-i（`-i` 吞 `--` 作值）且
  // 尾部旗标形 `-c` 落未知旗标（fail loud）——script 收口语义 = 文件位后
  // 透传域无死角（`-c` 是脚本的 argv 不是 vitro 的旗标）
  let ra = parse_run_args(["x.c", "a", "--json", "-i", "--", "b", "-c"])
  inspect(ra.json_mode, content="true")
  inspect(ra.stdin_file, content="--")
  inspect(ra.argv_passthrough.length(), content="2") // [a, b]——旗标被解析消化
  inspect(ra.unknown_flag is Some("-c"), content="true")
}

///|
test "script_parse_args_前置旗标_fail_loud" {
  // python 惯例（实测 --bogus）：解释器选项位（文件位之前）的未知旗标
  // 报错不静默——script 零解释器选项，文件位前任何 `-` 前缀参数（非
  // `-` stdin 占位）= 用法错 rc=4（病 87 族防线：零信号最危险）
  let sa = parse_script_args(["--json", "x.c"])
  inspect(sa.unknown_flag is Some("--json"), content="true")
  inspect(sa.file, content="")
  // `-` 单独 = stdin 源占位（run 同品类；python `-` 同形）
  let sb = parse_script_args(["-", "a"])
  inspect(sb.file, content="-")
  inspect(sb.argv[0], content="a")
  inspect(sb.unknown_flag is None, content="true")
  // 空参 = 缺文件位（主体 rc=4）
  let sc = parse_script_args([])
  inspect(sc.file, content="")
}

///|
test "script_strip_shebang_等长空行_行号零偏移" {
  // python 对拍锚（2026-11-05 实测）：`#!` 首行被忽略但**行号不减一**
  // ——实现形态 = 首行替换等长空格（换行符保留，行数与列偏移零变化）
  let s1 = strip_shebang("#!/usr/bin/env vitro\nint main(){return 0;}\n")
  inspect(s1.length(), content="43") // 总长不变（20+1+21+1——首行→20 空格）
  inspect(s1.split("\n").to_array().length(), content="3") // 行数不变（2 换行）
  inspect(s1.has_prefix("  "), content="true") // 首行非 #! 已替换
  inspect(s1.contains("#!"), content="false")
  // `#` 开头但非 `#!`（预处理合法域）不剥——教学诊断面零扰动
  let s2 = strip_shebang("#include <stdio.h>\nint main(){return 0;}\n")
  inspect(s2, content="#include <stdio.h>\nint main(){return 0;}\n")
  // 单行无换行形态：整串替换（等长）
  let s3 = strip_shebang("#!/bin/vitro")
  inspect(s3.length(), content="12")
  inspect(s3.contains("#"), content="false")
  // CRLF 形态：\r 一并入首行替换、\n 保留（Windows 源常见形态）
  let s4 = strip_shebang("#!/x\r\nint main(){return 0;}\n")
  inspect(s4.split("\n").to_array().length(), content="3")
  inspect(s4.contains("\r"), content="false")
  // 无 shebang 原样返回（含空串）
  let s5 = strip_shebang("int main(){return 0;}")
  inspect(s5, content="int main(){return 0;}")
  inspect(strip_shebang(""), content="")
}

///|
/// script 主体 rc 语义桩：return_value 参数化（透传域锚用）。invoke_parsed
/// 必须 method-aware（compile/run/delta 各回各帧——恒回 compile 帧会让
/// run 帧解析出空 return_value，透传锚全 0 假红）。
fn script_retval_channel(retval : Int32) -> EngineChannel {
  let frame_of = fn(line : String) -> String {
    if line.contains("\"method\":\"compile\"") {
      "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"diagnostics\":[],\"preprocessor_trace\":[]}}"
    } else if line.contains("\"method\":\"run\"") {
      "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"status\":\"finished\",\"return_value\":\{retval},\"trap\":\"\",\"waiting_input\":false,\"steps_executed\":1}}"
    } else {
      "{\"id\":1,\"ok\":true,\"result\":{\"delta\":\"\",\"cursor\":0,\"total\":0,\"stream\":\"stdout\",\"truncated_bytes\":0}}"
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
test "script_exit_code_透传与0xFF折叠" {
  // ① return_value=7 → 进程 rc=7（run 态对照 = 恒 0——frame_pipeline
  // 缺省 exit_passthrough=false）
  let rc7 = script(
    ["-", "a"],
    fn() { 0UL },
    () => b"int main(){return 7;}",
    noop_write,
    channel=script_retval_channel(7),
  )
  inspect(rc7, content="7")
  // ② & 0xFF（POSIX 惯例；python sys.exit(256)→0 / 42→42 实测锚）
  let rc256 = script(
    ["-"],
    fn() { 0UL },
    () => b"int main(){return 256;}",
    noop_write,
    channel=script_retval_channel(256),
  )
  inspect(rc256, content="0")
  let rc300 = script(
    ["-"],
    fn() { 0UL },
    () => b"int main(){return 300;}",
    noop_write,
    channel=script_retval_channel(300),
  )
  inspect(rc300, content="44")
  let rcneg = script(
    ["-"],
    fn() { 0UL },
    () => b"int main(){return -1;}",
    noop_write,
    channel=script_retval_channel(-1),
  )
  inspect(rcneg, content="255")
  // ③ return 0 → rc=0
  let rc0 = script(
    ["-"],
    fn() { 0UL },
    () => b"int main(){return 0;}",
    noop_write,
    channel=script_retval_channel(0),
  )
  inspect(rc0, content="0")
}

///|
test "script_框架错路径不透传" {
  // 编译错 rc=1 / 用法错 rc=4 不受 exit 透传影响（框架码位语义同 run）
  let rc1 = script(
    ["-"],
    fn() { 0UL },
    () => b"int main(){ return = ; }",
    noop_write,
    channel=compile_fail_channel(),
  )
  inspect(rc1, content="1")
  let rc4 = script(
    ["--bogus", "x.c"],
    fn() { 0UL },
    () => b"",
    noop_write,
    channel=script_retval_channel(0),
  )
  inspect(rc4, content="4")
  let rc4b = script(
    [],
    fn() { 0UL },
    () => b"",
    noop_write,
    channel=script_retval_channel(0),
  )
  inspect(rc4b, content="4")
}

///|
test "script_shebang_剥行后送管线" {
  // shebang 剥行发生在「送编译之前」——compile_params 桩捕获 src 断言
  // 首行为空格行（非 #!）；run 态同源码不剥（cli_run 直调对照锚）
  let captured : Array[String] = []
  let chan : EngineChannel = {
    invoke: fn(line : String) -> String {
      if line.contains("\"method\":\"compile\"") {
        "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"diagnostics\":[],\"preprocessor_trace\":[]}}"
      } else if line.contains("\"method\":\"run\"") {
        "{\"id\":1,\"ok\":true,\"result\":{\"ok\":true,\"status\":\"finished\",\"return_value\":0,\"trap\":\"\",\"waiting_input\":false,\"steps_executed\":1}}"
      } else {
        "{\"id\":1,\"ok\":true,\"result\":{\"delta\":\"\",\"cursor\":0,\"total\":0,\"stream\":\"stdout\",\"truncated_bytes\":0}}"
      }
    },
    invoke_parsed: fn(_line : String) -> Json? {
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
    compile_params: fn(_file : String, src : String) -> String {
      captured.push(src)
      "{\"source\":\"\",\"filename\":\"-\"}"
    },
  }
  ignore(
    script(
      ["-"],
      fn() { 0UL },
      () => b"#!/usr/bin/env vitro script\nint main(){return 0;}",
      noop_write,
      channel=chan,
    ),
  )
  inspect(captured.length(), content="1")
  let src = captured[0]
  let lines = src.split("\n").to_array()
  inspect(lines.length(), content="2") // 行数不变（行号零偏移前提）
  inspect(lines[0].contains("#"), content="false") // 首行已剥
  inspect(lines[1], content="int main(){return 0;}") // 第二行起原样
}

///|
/// B3 批 M35 A1 红→绿锚（2026-11-02）：api 子命令旗标 fail loud——修前解析
/// 循环无未知旗标分支：前置形态 `api --xyz ping` 旗标静默吞、正常执行 rc=0
///（病 87 形态——用户以为旗标生效，零信号最危险）；尾随形态 `api ping --bogus`
/// 被抓进 params 位再被前缀校验拦下 rc=4、但文案「params 须为 JSON 对象字面量」
/// 把旗标误报成 params（run/compile/step 三子命令 2026-10-13 方案 A 已 fail
/// loud，api 独漏）。js 臂子进程实测 `api --xyz ping` rc=0。
test "m35_a1_api_未知旗标_fail_loud" {
  // ① 前置旗标（修前 rc=0 静默吞）
  assert_eq(
    api(
      ["--xyz", "ping"],
      () => b"",
      write_stdout=noop_write,
      channel=fake_channel(),
    ),
    4,
    msg="前置未知旗标须 rc=4（修前静默吞 rc=0）",
  )
  // ② 尾随旗标（修前 rc=4 碰巧对但走 params 误报路径）
  assert_eq(
    api(
      ["ping", "--bogus"],
      () => b"",
      write_stdout=noop_write,
      channel=fake_channel(),
    ),
    4,
    msg="尾随未知旗标须 rc=4",
  )
  // ③ 合法形态不受影响：--batch 仍认（回归面）；单帧 ping 正常 rc=0
  assert_eq(
    api(["ping"], () => b"", write_stdout=noop_write, channel=fake_channel()),
    0,
    msg="合法单帧不受影响",
  )
  assert_eq(
    api(
      ["--batch"],
      () => b"{\"id\":1,\"method\":\"ping\",\"params\":{}}\n",
      write_stdout=noop_write,
      channel=fake_channel(),
    ),
    0,
    msg="--batch 仍为合法旗标",
  )
}
