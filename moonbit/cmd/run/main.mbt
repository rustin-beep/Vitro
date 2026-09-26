// cmd/run：D 级三联 diff 的 MoonBit 侧 runner（批五号）——编译 → setup →
// run → stdout / 返回码 / 1MB 内存映像三通道。
//
// 用法（仓库根）：moon run moonbit/cmd/run -- <file.c> [--dump-memory out.bin]
//   --dump-memory  最终 1MB 映像落盘（D 级第三通道；hex dump 由 Go 侧
//                  scripts/vm_diff 统一归一后 diff）
//
// 输出协议（Go 驱动侧解析）：
//   - stdout 通道：程序 C 层输出原样（Bytes → 逐字节写出；非 UTF-8 按
//     Latin-1 落文本——D 级 diff 在 Go 侧字节级归一）
//   - 末行标记：`// EXIT <ret>`（返回码通道；ret=0 时省略）

///|
/// 文件系统 provider：把 resolver 拼好的候选路径（"/" 分隔的规范形态，
/// 相对/绝对均可——Windows fs 接受正斜杠）交给宿主文件系统。未命中统一
/// `NotFound`（由 pp 层按候选链继续或最终报 E1021，与 Rust E1021 对拍）。
enum FsProvider {
  Fs
}

///|
impl @token.SourceProvider for FsProvider with fn read(self, path : String) -> String raise @token.SourceError {
  match self {
    Fs => ()
  }
  @fs.read_file_to_string(path) catch {
    _ => raise @token.SourceError::NotFound(path~)
  }
}

///|
/// 路径的目录段（末个 `/` 或 `\` 之前；无分隔符 = "."）。分隔符统一转
/// `/`。与 oracle 的等价性经 7 形态端到端探针对拍实证（裸文件名 / ./x /
/// 绝对路径 / 子目录 / 嵌套 include 链 / 取不到的根相对路径 / 根斜杠）：
/// 本函数返 "." 时 oracle base_path = Some("")——**两侧并不逐字相同**
/// （MoonBit resolver 跳过空串 cur_dir，Rust Path("").join(p) 不跳过），
/// 但两级候选链的最终解析行为逐形态一致——等价是行为级非文本级。
fn dir_of(path : String) -> String {
  let mut last = -1
  for i = 0; i < path.length(); i = i + 1 {
    let c = path[i]
    if c.to_int() == 47 || c.to_int() == 92 {
      last = i
    }
  }
  if last <= 0 {
    "."
  } else {
    let buf = StringBuilder()
    for i = 0; i < last; i = i + 1 {
      let c = path[i]
      if c.to_int() == 92 {
        buf.write_char('/')
      } else {
        buf.write_char(c.to_int().unsafe_to_char())
      }
    }
    buf.to_string()
  }
}

///|
fn main raise {
  let args = @env.args()
  let mut file = ""
  let mut dump_mem = ""
  let mut i = 1
  while i < args.length() {
    if args[i] == "--dump-memory" && i + 1 < args.length() {
      i = i + 1
      dump_mem = args[i]
    } else if !args[i].starts_with("-") {
      file = args[i]
    }
    i = i + 1
  }
  if file == "" {
    println(
      "用法: moon run moonbit/cmd/run -- <file.c> [--dump-memory out.bin]",
    )
    return
  }
  // P3-10（2026-09-26 审阅）：源文件不可读此前抛裸 IOError（exit 127、非
  // 协议形态）——协议化为 // COMPILE-ERROR io 行，harness 报文可读。
  let src = @fs.read_file_to_string(file) catch { _ => "" }
  guard src != "" else {
    println("// COMPILE-ERROR io 1:1 源文件不可读或为空：\{file}")
    return
  }
  // ── 编译管线（照 dump_compile 的 fail loud 样板）──
  // SourceProvider 接线（2026-09-26，消 vm_diff e2 include 族 SKIP）：对齐
  // Rust oracle 口径 = 首个源文件目录作 quote-include 候选链 base_dir，
  // resolver 拼好候选路径后 provider 直读文件系统（compile_pipeline.rs
  // `base_path = Path(filename).parent()` → directives.rs `fs::read_to_string`）。
  let provider = FsProvider::Fs
  let lexed = @lexer.tokenize_with(src, provider~, base_dir=dir_of(file))
  guard lexed.errors.is_empty() else {
    for e in lexed.errors {
      println("// COMPILE-ERROR lex \{e.loc.line}:\{e.loc.column} \{e.message}")
    }
    return
  }
  let r = @parser.parse(lexed.tokens)
  guard r.errors.is_empty() && r.program is Some(p) else {
    for e in r.errors {
      println("// COMPILE-ERROR parse \{e.line}:\{e.column} \{e.message}")
    }
    return
  }
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, _w, _h) = tc.check(p)
  guard type_errors.is_empty() else {
    for e in type_errors {
      println("// COMPILE-ERROR type \{e.line}:\{e.column} \{e.message}")
    }
    return
  }
  let (output_opt, gen_errors) = @codegen.compile(typed)
  guard gen_errors.is_empty() && output_opt is Some(output) else {
    for e in gen_errors {
      println("// COMPILE-ERROR codegen \{e}")
    }
    return
  }
  // ── setup + run（批四号 12 步组装）──
  let vm = @vm.VitroVM::new()
  // argv[0] = 源文件路径（对齐 oracle CLI 口径：main 解析处 argv 以 file_path
  // 为首元素——C 惯例 argv[0]=程序名；第三联映像 diff 的 argv 区一致性前提）
  let argv0 : Array[String] = [file]
  vm.setup_from_output(output, 1, argv0)
  // R1 ① 动态堆起点（对齐 oracle reset_runtime：argv 非空 ⇒ heap_base 上移
  // GLOBAL_REGION_LIMIT）。须在 setup_from_output **之后**——其内部 reset 会
  // 整体重建 mem_map（heap_base 回默认），预设注入前落位即可（oracle 的
  // set_heap_base 虽在 setup_vm 前，但其 setup 不重建 MemoryState，语义等价）。
  vm.mem_map.set_heap_base(
    @bytecode.compute_heap_base(output.global_data_end, 1, argv0),
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
  if dump_mem != "" {
    @fs.write_bytes_to_file(dump_mem, vm.dump_memory_raw())
  }
  // 返回码通道
  if ret != 0 {
    println("// EXIT \{ret}")
  }
}
