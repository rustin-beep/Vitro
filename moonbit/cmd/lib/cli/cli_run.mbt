// cmd/lib/run：CLI `run` 子命令逻辑（#37 批② 自 cmd/run/main.mbt 下沉，
// 2026-10-04）。薄壳 cmd/run 与总入口 cmd/vitro 共享本入口——
// `run(args)` 的 args 约定 = **已剥子命令名的参数**（薄壳传
// args[1:]、总入口传 args[2:]——偏移约定锚见 parse_run_args wbtest）。
//
// 进程退出码全表（#37 v3 定案；标记行协议不变——防线全走文本行，
// 进程码唯一消费方 = shell/agent）：
//   0=正常（含 return 0） / 1=编译错 / 2=trap / 3=步数超限 / 4=用法/IO 错
//
// 输出协议（与 cmd/run 历史形态逐字节兼容——vm_diff/clang_direct 消费面）：
//   stdout 程序输出原样 + 末行 `// EXIT <ret>`（ret=0 省略）+ `// TRAP`
//   + 三级诊断行（批①：`// COMPILE-ERROR E<code> …` 等）。

///|
/// 参数解析结果（pub 纯函数形态——wbtest 锚对象）。
pub(all) struct RunArgs {
  mut file : String
  mut dump_mem : String
  mut stdin_file : String
  mut json_mode : Bool // --json（批③：事件流 NDJSON——gateway 帧单源）
  argv_passthrough : Array[String] // `--` 之后的 argv 透传（Rust 口径）
}

///|
/// 解析 run 参数（args = 已剥子命令名）。`--` 之后全部进 argv 透传
/// （含 `-` 形态字面量——透传域不解析）；文件位取首个非 `-` 前缀参数。
pub fn parse_run_args(args : Array[String]) -> RunArgs {
  let ra : RunArgs = {
    file: "",
    dump_mem: "",
    stdin_file: "",
    json_mode: false,
    argv_passthrough: [],
  }
  let mut i = 0
  let mut passthrough = false
  while i < args.length() {
    let a = args[i]
    if passthrough {
      ra.argv_passthrough.push(a)
      i += 1
      continue
    }
    if a == "--" {
      passthrough = true
    } else if a == "--json" {
      ra.json_mode = true
    } else if a == "--dump-memory" && i + 1 < args.length() {
      i += 1
      ra.dump_mem = args[i]
    } else if a == "-i" && i + 1 < args.length() {
      // stdin 注入（2026-09-29 层 2 遗留 stdin 34 例批）：文件 → host
      // 单源切行（行含尾换行）；Batch 模式（headless——输入耗尽即 EOF
      // 不交互，oracle CLI -i 同语义：while(scanf...)!=EOF 习语不挂起）
      i += 1
      ra.stdin_file = args[i]
    } else if !a.has_prefix("-") || a == "-" {
      // `-`（stdin 源）在批③接线——占位接收避免落用法提示
      ra.file = a
    }
    i += 1
  }
  ra
}

///|
/// 文件系统 provider：把 resolver 拼好的候选路径（"/" 分隔的规范形态，
/// 相对/绝对均可——Windows fs 接受正斜杠）交给宿主文件系统。未命中统一
/// `NotFound`（由 pp 层按候选链继续或最终报 E1021，与 Rust E1021 对拍）。
enum FsProvider {
  Fs
}

///|
impl @token.SourceProvider for FsProvider with fn read(
  self : FsProvider,
  path : String,
) -> String raise @token.SourceError {
  match self {
    Fs => ()
  }
  @fs.read_file_to_string(path) catch {
    _ => raise @token.SourceError::NotFound(path~)
  }
}

///|
/// 源文件目录（quote-include 候选链 base_dir——oracle compile_pipeline
/// `base_path = Path(filename).parent()` 口径）。
fn dir_of(file : String) -> String {
  // 从尾找 '/'（含 ''——Windows 路径双兼容，全域纪律 9）
  let cs = file.to_array()
  let mut idx = -1
  let mut i = cs.length() - 1
  while i >= 0 {
    if cs[i] == '/' || cs[i] == '\\' {
      idx = i
      break
    }
    i -= 1
  }
  if idx <= 0 {
    "."
  } else {
    file.substring(start=0, end=idx)
  }
}

///|
/// 编译 + 诊断输出（三级文本行——批① fixes #16）。run 与 compile 命令
/// 同源消费（一处实现两出口）。返回 (CompileOutput?, 退出码)：ok 时
/// output 非空码 0；编译错输出诊断行后码 1。
pub fn compile_and_report(
  src : String,
  file : String,
) -> (@bytecode.CompileOutput?, Int) {
  let provider = FsProvider::Fs
  let lexed = @lexer.tokenize_with(src, provider~, base_dir=dir_of(file))
  // 诊断通道三级文本行（2026-10-04，fixes #16）：错误行带码（`E<code>
  // <line:col> <文案>`——码与 serve 帧 code 字段同源；phase 段移除，
  // 码即层级）；警告/提示不再丢弃（`// COMPILE-WARNING W<code> …` /
  // `// COMPILE-HINT H<code> …`——双剥离器白名单连坐已先行）；错误
  // 早退前也输出已收集警告（agent 修错不丢信息）
  let print_lex_warnings = fn() {
    for w in lexed.warnings {
      println(
        "// COMPILE-WARNING W\{w.code.code()} \{w.loc.line}:\{w.loc.column} \{w.message}",
      )
    }
  }
  guard lexed.errors.is_empty() else {
    for e in lexed.errors {
      println(
        "// COMPILE-ERROR E\{e.code.code()} \{e.loc.line}:\{e.loc.column} \{e.message}",
      )
    }
    print_lex_warnings()
    return (None, 1)
  }
  let r = @parser.parse(lexed.tokens)
  guard r.errors.is_empty() && r.program is Some(p) else {
    for e in r.errors {
      println("// COMPILE-ERROR E\{e.code} \{e.line}:\{e.column} \{e.message}")
    }
    print_lex_warnings()
    return (None, 1)
  }
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, warns, hints) = tc.check(p)
  guard type_errors.is_empty() else {
    for e in type_errors {
      println("// COMPILE-ERROR E\{e.code} \{e.line}:\{e.column} \{e.message}")
    }
    print_lex_warnings()
    for w in warns {
      println(
        "// COMPILE-WARNING W\{w.code} \{w.line}:\{w.column} \{w.message}",
      )
    }
    return (None, 1)
  }
  for w in warns {
    println("// COMPILE-WARNING W\{w.code} \{w.line}:\{w.column} \{w.message}")
  }
  for h in hints {
    println("// COMPILE-HINT H\{h.code} \{h.line}:\{h.column} \{h.message}")
  }
  print_lex_warnings()
  let (output_opt, gen_errors) = @codegen.compile(typed)
  guard gen_errors.is_empty() && output_opt is Some(output) else {
    for e in gen_errors {
      println("// COMPILE-ERROR codegen \{e}")
    }
    return (None, 1)
  }
  (Some(output), 0)
}

///|
/// CLI `run` 子命令主体（编译 → setup → run → stdout/返回码/1MB 映像
/// 三通道 + 进程退出码）。read_stdin 由薄壳注入（`-` 源码通道——批③；
/// 平台绑定归 exe 层，同 clock 注入模式）。
pub fn run(
  args : Array[String],
  clock_millis : () -> UInt64,
  read_stdin : () -> Bytes,
) -> Int {
  let ra = parse_run_args(args)
  if ra.file == "" {
    println(
      "用法: run <file.c> [--dump-memory out.bin] [-i input.in] [-- <argv...>]",
    )
    return 4
  }
  // `-` = 源码走 stdin（Rust read_source 全命令通用品类——批③ B2）
  let src = if ra.file == "-" {
    utf8_decode(read_stdin())
  } else {
    // P3-10（2026-09-26 审阅）：源文件不可读此前抛裸 IOError（非协议形态）
    // ——协议化为 // COMPILE-ERROR io 行，harness 报文可读。
    @fs.read_file_to_string(ra.file) catch {
      _ => ""
    }
  }
  guard src != "" else {
    println("// COMPILE-ERROR io 1:1 源文件不可读或为空：\{ra.file}")
    return 4
  }
  if ra.json_mode {
    return json_event_stream(src)
  }
  let (output_opt, code) = compile_and_report(src, ra.file)
  guard output_opt is Some(output) else { return code }
  // ── setup + run（批四号 12 步组装）──
  let vm = @vm.VitroVM::new()
  // 墙钟注册（2026-10-02 deterministic 销分叉接线——oracle run 通道
  // current_time_millis 真值）。clock 由薄壳注入（extern 声明与 stub 属
  // 平台绑定归 exe 层——lib 包零 native 依赖；构建实锤：lib 包的
  // native-stub 不进引用方 exe 的链接）
  vm.set_clock_source(clock_millis)
  // argv[0] = 源文件路径（对齐 oracle CLI 口径：main 解析处 argv 以 file_path
  // 为首元素——C 惯例 argv[0]=程序名；第三联映像 diff 的 argv 区一致性前提）
  // `--` 透传参数跟随（Rust vitro_cli :1010-1012 口径）
  let argv_full : Array[String] = [ra.file]
  for a in ra.argv_passthrough {
    argv_full.push(a)
  }
  // vis 行恒空（cmd/run 纯编译通道不跑 detect，无 algorithm_matches 产物
  // ——issue #29 #4 登记等价：两侧 cmd/run 输出面均无 vis_events 观察
  //（stdout/返回码/第三联 1MB 映像都不含 vm 内部 vis 状态），服务面
  // 消费走 serve step 流）
  vm.setup_from_output(output, argv_full.length(), argv_full, [])
  // R1 ① 动态堆起点（对齐 oracle reset_runtime：argv 非空 ⇒ heap_base 上移
  // GLOBAL_REGION_LIMIT）。须在 setup_from_output **之后**——其内部 reset 会
  // 整体重建 mem_map（heap_base 回默认），预设注入前落位即可（oracle 的
  // set_heap_base 虽在 setup_vm 前，但其 setup 不重建 MemoryState，语义等价）。
  vm.mem_map.set_heap_base(
    @bytecode.compute_heap_base(output.global_data_end, 1, argv_full),
  )
  // vfs 预设注入（对齐 oracle CLI 口径：execute_run 无条件注入 test.txt/
  // numbers.txt——教学演示通道，file_fopen/file_fread 族的依赖面；亦使
  // 第三联映像的 vfs 预设区一致）
  ignore(
    vm.vfs.inject_preset_file(
      vm.mem_map,
      vm.memory,
      "test.txt",
      b"hello\nworld\n",
    ),
  )
  ignore(
    vm.vfs.inject_preset_file(
      vm.mem_map,
      vm.memory,
      "numbers.txt",
      b"1 2 3 4 5\n",
    ),
  )
  if ra.stdin_file != "" {
    let text = @fs.read_file_to_string(ra.stdin_file) catch { _ => "" }
    vm.set_input(@host.InputState::from_stdin_text(text, true))
  }
  let ret = vm.run()
  // ── stdout 通道（Buffer 聚合 + print 整串——字节经 Char 直转；
  // 非 UTF-8 字节按 Latin-1 落文本，Go 侧归一时统一字节口径）──
  let buf = StringBuilder()
  for chunk in vm.output.chunks_of(@host.OutputKind::Stdout) {
    for j = 0; j < chunk.length(); j = j + 1 {
      buf.write_char(chunk[j].to_int().unsafe_to_char())
    }
  }
  let mut text = buf.to_string()
  let nl : String = "\n"
  if !text.has_suffix(nl) {
    text = text + nl
  }
  println(text)
  // trap 时 stderr 通道附注
  if !vm.error.is_empty() {
    println("// TRAP \{vm.error}")
  }
  // ── 1MB 映像（第三通道）──
  if ra.dump_mem != "" {
    @fs.write_bytes_to_file(ra.dump_mem, vm.dump_memory_raw()) catch {
      _ => ()
    }
  }
  // 返回码通道（标记行——防线消费面，与进程退出码双轨）
  if ret != 0 {
    println("// EXIT \{ret}")
  }
  // 进程退出码（全表）：trap 判定序 = 步数超限优先（超限也是 trap 形态，
  // format_infinite_loop_error 文案——按步数事实判免文案匹配脆）
  if !vm.error.is_empty() {
    if vm.step_count >= vm.max_steps {
      return 3
    }
    return 2
  }
  0
}

///|
/// UTF-8 字节 → String（`-` stdin 通道——C stub 返回原始字节，解码在
/// MoonBit 侧纯逻辑完成可 wbtest。截断序列静默止（尾不完整多字节——
/// 文本源码域足够）。
pub fn utf8_decode(b : Bytes) -> String {
  let buf = StringBuilder()
  let n = b.length()
  let mut i = 0
  while i < n {
    let c0 = b[i].to_int() & 0xff
    if c0 < 0x80 {
      buf.write_char(c0.unsafe_to_char())
      i += 1
    } else if c0 < 0xe0 && i + 1 < n {
      let c1 = b[i + 1].to_int() & 0x3f
      buf.write_char((((c0 & 0x1f) << 6) | c1).unsafe_to_char())
      i += 2
    } else if c0 < 0xf0 && i + 2 < n {
      let c1 = b[i + 1].to_int() & 0x3f
      let c2 = b[i + 2].to_int() & 0x3f
      buf.write_char((((c0 & 0x0f) << 12) | (c1 << 6) | c2).unsafe_to_char())
      i += 3
    } else if i + 3 < n {
      let c1 = b[i + 1].to_int() & 0x3f
      let c2 = b[i + 2].to_int() & 0x3f
      let c3 = b[i + 3].to_int() & 0x3f
      let cp = ((c0 & 0x07) << 18) | (c1 << 12) | (c2 << 6) | c3
      // MoonBit Char 是 Unicode 码点（非 UTF-16 码元）——直接写码点，
      // String 内部自管 UTF-16 编码（wbtest 代理对锚抓过手拆形态的错）
      buf.write_char(cp.unsafe_to_char())
      i += 4
    } else {
      break
    }
  }
  buf.to_string()
}
