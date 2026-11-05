// cmd/lib/cli·script 子命令（WASI 期 0，2026-11-05——设计单《WASI拓展面
// ——能力授权制与C脚本裁判形态》§3.1/§5.2 期 0 行 + O5 拍板落位：cli 扩
// 子命令，三臂单源最短路径）：C 脚本体验的 run 态包装——零 WASI 面，三件
// 独立小改在此收口：
//
//   ① argv 收口：文件位后**零解析全透传**（python/node 惯例——2026-11-05
//      本机 python 3.14 实测：argv.py 下 `-- -i --json a` 全部原样进
//      sys.argv，`--` 无特殊语义）。与 run 的分叉 = run 在文件位后仍解析
//      `-i`/`--json` 且吃掉 `--`（教学 CLI 面向学生、旗标显式）；script
//      面向脚本作者、文件位即边界——旗标形参数是脚本的 argv 不是 vitro 的。
//      文件位**之前**的 `-` 前缀参数（非 `-` 占位）= 用法错 rc=4（python
//      --bogus 报错同形；病 87 族：零信号最危险）。
//   ② shebang 剥行：源码首行 `#!` 剥离（壳层预处理一步，不进 lexer——
//      C 预处理域外）。行号语义对齐 python 惯例（2026-11-05 实测：err.py
//      第 2 行错报 line 2、err3.py 报 line 3——`#!` 行忽略但行号照常
//      计数）：实现 = 首行替换**等长空格**（换行符保留），行数/列偏移
//      零变化。run 态不剥（教学诊断面零扰动）。
//   ③ exit code 透传：进程 rc = C 返回值 & 0xFF（POSIX 惯例；python
//      sys.exit(256)→0 / 42→42 实测锚）。`// EXIT N` 标记行照打（观测
//      通道——rc 同码位歧义〔C return 2 vs trap 2〕的区分出口）。
//
// 退出码表（spec CLI_PROTOCOL_V1 §4.6 在册）：正常结束 = C 返回值 & 0xFF
// 透传（域 0..255）；框架错同 run 五值表的 1/2/3/4（编译错/trap/步数
// 超限/用法 IO 错——与透传域同码位重叠是 python/node 同款接受形态，
// 区分走 stderr 标记行）。
//
// 骨架期边界（期 1 起 WASI 面解锁，设计单 §3.1）：不支持 --json/-i/
// --dump-memory/--max-steps/--realtime（零旗标面——文件位后零解析的直接
// 推论）；stdin 程序输入面未开（Batch EOF 语义——fd_read 直通是期 1 级
// 2）；`-` 源码走进程 stdin（python `-` 同品类）。

///|
/// script 参数解析结果（pub 纯函数形态——wbtest 锚对象）。
pub(all) struct ScriptArgs {
  mut file : String
  argv : Array[String] // 文件位后全部参数原样透传（零解析）
  mut unknown_flag : String? // 文件位之前的 `-` 前缀参数（fail loud rc=4）
}

///|
/// 解析 script 参数（args = 已剥子命令名）。首个非 `-` 前缀参数（或 `-`
/// 占位）= 源文件位；其后全部参数原样进 argv（含旗标形与 `--` 字面量）
/// ——透传域零解析（python 惯例）。
pub fn parse_script_args(args : Array[String]) -> ScriptArgs {
  let sa : ScriptArgs = { file: "", argv: [], unknown_flag: None, }
  for a in args {
    if sa.file == "" {
      // 文件位之前的解释器选项位：script 零选项，`-` 前缀一律 fail loud
      //（`-` 单独 = stdin 源占位，run 同品类）
      if !a.has_prefix("-") || a == "-" {
        sa.file = a
      } else {
        sa.unknown_flag = Some(a)
        break
      }
    } else {
      sa.argv.push(a)
    }
  }
  sa
}

///|
/// shebang 剥行（script 态专属）：源码以 `#!` 开头时，首行（到首个 `\n`
/// 为止，不含 `\n`——CRLF 源的 `\r` 一并）替换为**等长空格**。行号/行数
/// 零偏移（python 惯例：`#!` 行忽略但行号照常计数）；无 `#!` 前缀原样
/// 返回（`#include` 等预处理合法域不受染）。BOM 前置源 `#!` 不在位 0，
/// 不剥（lexer 现状对 BOM 的处理照旧，无新面）。
pub fn strip_shebang(src : String) -> String {
  if !src.has_prefix("#!") {
    return src
  }
  // 首行长度 = 首个换行符偏移（无换行 = 全串）
  let cs = src.to_array()
  let mut nl = cs.length()
  for i = 0; i < cs.length(); i = i + 1 {
    if cs[i] == '\n' {
      nl = i
      break
    }
  }
  let b = StringBuilder()
  for i = 0; i < nl; i = i + 1 {
    b.write_char(' ')
  }
  if nl < cs.length() {
    b.write_string(src[nl:].to_owned())
  }
  b.to_string()
}

///|
/// CLI `script` 子命令主体（读源 → 剥 shebang → frame_pipeline 全速跑
/// + exit 透传）。IO 注入与 run 同款（`-` 源码通道 + stdout 字节直写）。
pub fn script(
  args : Array[String],
  clock_millis : () -> UInt64,
  read_stdin : () -> Bytes,
  write_stdout : (Bytes) -> Unit,
  channel~ : EngineChannel,
) -> Int32 {
  ensure_include_reader(channel)
  let sa = parse_script_args(args)
  if sa.unknown_flag is Some(msg) {
    say(
      "vitro script: 文件位前不接受旗标（'\{msg}'）——vitro 旗标请查阅 vitro run；脚本参数请放源文件名之后（全部透传给 C 程序 argv）",
    )
    say("用法: script <file.c | -> [argv...]")
    return 4
  }
  if sa.file == "" {
    say("用法: script <file.c | -> [argv...]")
    return 4
  }
  // 源码读取：`-` = 进程 stdin（run 同款）；不可读/空 = io 诊断行 + rc=4
  let src = if sa.file == "-" {
    @util.utf8_text_partial(read_stdin())
  } else {
    @fs.read_file_to_string(sa.file) catch {
      _ => ""
    }
  }
  guard src != "" else {
    say("// COMPILE-ERROR io 1:1 源文件不可读或为空：\{sa.file}")
    return 4
  }
  // 帧管线复用（run 全速态——VisEvent/帧流零参与）：shebang 剥行在送
  // 编译之前；exit_passthrough=true 落 rc 透传（run 态缺省 false 零扰动）
  return frame_pipeline(
    strip_shebang(src),
    sa.file,
    "",
    sa.argv,
    "",
    clock_millis,
    write_stdout,
    false,
    channel~,
    exit_passthrough=true,
  )
}
