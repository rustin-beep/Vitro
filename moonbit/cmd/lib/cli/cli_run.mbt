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
      // 首个位置参数 = 源文件；其余位置参数进 argv 透传（Rust vitro_cli
      // :1010 语义「未识别的位置参数视为传给 main 的 argv」——2026-10-04
      // 用户实测抓到旧形态取最后一个的分叉后对齐）
      if ra.file == "" {
        ra.file = a
      } else if a != "-" {
        ra.argv_passthrough.push(a)
      }
    }
    i += 1
  }
  ra
}

///|

///|
/// CLI `run` 子命令主体（编译 → setup → run → stdout/返回码/1MB 映像
/// 三通道 + 进程退出码）。read_stdin / write_stdout 由薄壳注入（`-` 源码
/// 通道与 stdout 字节直写——平台绑定归 exe 层，同 clock 注入模式）。
pub fn run(
  args : Array[String],
  clock_millis : () -> UInt64,
  read_stdin : () -> Bytes,
  write_stdout : (Bytes) -> Unit,
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
    @util.utf8_text_partial(read_stdin())
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
  // #70 第二步（2026-10-11）：run 全帧单源管线——文本/json 两模式共用
  // frame_pipeline（旧 compile_and_report 直调管线 + vm setup 直驱段拆除；
  // stdout/stderr/note/EXIT/TRAP/--dump-memory 全走帧渲染，与 wasm 壳
  // 同一出口——CLI_PROTOCOL_V1「帧单源」自此成真）
  return frame_pipeline(
    src,
    ra.file,
    ra.stdin_file,
    ra.argv_passthrough,
    ra.dump_mem,
    clock_millis,
    write_stdout,
    ra.json_mode,
  )
}
