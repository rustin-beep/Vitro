// cmd/lib/compile：CLI `compile` 子命令（#37 批②）——只编译+诊断，
// 不执行。文本模式：三级诊断行（与 run 同源——lib/run.compile_and_report）
// + 成功标记 `// COMPILE-OK`。--json 模式（批③）：gateway compile 帧直透
// （NDJSON 单行——含 fix_suggestion 七元组，比文本形态更富；帧单源与
// demo/serve 同通道）。退出码：0=编译通过 / 1=编译错 / 4=用法/IO。

///|
pub fn compile(args : Array[String], read_stdin : () -> Bytes) -> Int {
  let mut file = ""
  let mut json_mode = false
  for a in args {
    if a == "--json" {
      json_mode = true
    } else if (!a.has_prefix("-") || a == "-") && file == "" {
      file = a
    }
  }
  if file == "" {
    println("用法: compile <file.c> [--json]")
    return 4
  }
  // `-` = 源码走 stdin（Rust read_source 全命令通用品类——B2；2026-10-04
  // 手册对照复核补齐：初版仅 run 有，缩面未登记属实现漂移）
  let src = if file == "-" {
    @util.utf8_text_partial(read_stdin())
  } else {
    @fs.read_file_to_string(file) catch {
      _ => ""
    }
  }
  guard src != "" else {
    println("// COMPILE-ERROR io 1:1 源文件不可读或为空：\{file}")
    return 4
  }
  if json_mode {
    // escape 与 lib/run / lib/step 三份同源复制连坐
    let mut id = 0
    let inv = fn(method : String, params : String) -> String {
      id += 1
      @gateway.invoke(
        "{\"id\":\{id},\"method\":\"\{method}\",\"params\":\{params}}",
      )
    }
    @gateway.reset()
    ignore(inv("session.create", "{}"))
    // filename 装配（BUG-A 修复，2026-10-05）：协议 compile 帧支持可选
    // filename（gateway 侧 base_dir = dir_of(filename)，与文本模式
    // compile_and_report 同语义）；此前只传 source 令 base_dir 退化为
    // 缺省 "main.c" 所在目录，同目录 include 全断。stdin（"-"）无路径
    // 语义不传。cli_run_json / cli_step 同款连坐
    let compile_params = if file == "-" {
      "{\"source\":\"\{escape_json(src)}\"}"
    } else {
      "{\"source\":\"\{escape_json(src)}\",\"filename\":\"\{escape_json(file)}\"}"
    }
    let comp = inv("compile", compile_params)
    println(comp)
    if comp.contains("\"ok\":false") {
      return 1
    }
    return 0
  }
  let (_, code) = compile_and_report(src, file)
  if code == 0 {
    println("// COMPILE-OK")
  }
  code
}
