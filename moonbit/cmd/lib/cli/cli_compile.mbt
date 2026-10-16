// cmd/lib/compile：CLI `compile` 子命令（#37 批②；#70 第二步帧单源化
// 2026-10-11）——只编译+诊断，不执行。文本/json 两模式共用 frame_pipeline
// 的 compile_mode（gateway compile 帧单源；旧 compile_and_report 直调管线
// 拆除——诊断行渲染与 COMPILE-OK 由管线出口统一）。退出码：0=编译通过 /
// 1=编译错 / 4=用法/IO。

///|
pub fn compile(
  args : Array[String],
  read_stdin : () -> Bytes,
  channel~ : EngineChannel,
) -> Int32 {
  ensure_include_reader(channel)
  // 病 87 残留⑤（2026-10-13，方案 A 用户拍板）：未知旗标/多余位置参数
  // fail loud——旧静默丢（extra.c 被吞只编译第一个，用户以为多文件编译）
  let mut file = ""
  let mut json_mode = false
  let mut bad_arg : String? = None
  for a in args {
    if a == "--json" {
      json_mode = true
    } else if (!a.has_prefix("-") || a == "-") && file == "" {
      file = a
    } else if !a.has_prefix("-") || a == "-" {
      bad_arg = Some(
        "多余位置参数 '\{a}'（compile 是单文件编译——多文件请用 serve/api 的 files 数组）",
      )
      break
    } else {
      bad_arg = Some(a)
      break
    }
  }
  if bad_arg is Some(msg) {
    say("vitro compile: 未知旗标或多余参数：\{msg}")
    say("用法: compile <file.c> [--json]")
    return 4
  }
  if file == "" {
    say("用法: compile <file.c> [--json]")
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
    say("// COMPILE-ERROR io 1:1 源文件不可读或为空：\{file}")
    return 4
  }
  // compile 子命令无 clock/stdout 语义——占位注入（compile_mode 段不消费
  // run 输出通道）
  let zero_clock : () -> UInt64 = fn() { 0UL }
  let drop_stdout : (Bytes) -> Unit = fn(_b) { () }
  return frame_pipeline(
    src,
    file,
    "",
    [],
    "",
    zero_clock,
    drop_stdout,
    json_mode,
    compile_mode=true,
    channel~,
  )
}
