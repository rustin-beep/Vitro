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
  let src = @fs.read_file_to_string(file)
  // ── 编译管线（照 dump_compile 的 fail loud 样板）──
  let lexed = @lexer.tokenize(src)
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
  vm.setup_from_output(output, 0, [])
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
