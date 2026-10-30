///|
/// S5 差分出口（开发工具，native only）：批量产出 codegen 层 dump——
/// CompileOutput 13 字段全量 JSON（A 级产物对拍面）。
///
/// 用法：moon run cmd/dump_compile -- <corpus_dir|file.c> <out_dir>
///
/// 输出（每输入 <name>.c）：
/// - <name>.c.compile.json：
///   成功 → {"ok":true,"slot_strategy":N,"verify":{...},"dump":{...14 键（version+13 字段）...}}
///   （dump 键内的形态与 Rust `vitro_cli dump-compile` 的 CompileDump
///   逐字段同构——`@bytecode.compile_output_dump_json` emitter；外层
///   slot_strategy/verify 为本侧包装层附加，不参与 14 键比对——verify 是
///   #200 P0 bytecode 结构验证器的出口面）
///   失败 → {"ok":false,"stage":"lex|parse|type|gen","errors":[...]}
///
/// 管线语义对齐 Rust dump-compile（Lexer→Parser→TypeChecker→BytecodeGen，
/// 任一层失败即止）；stage 供差分驱动双错时按层对齐（Rust 侧由驱动按
/// stderr 文本归类，同为"该层失败"记 AGREE-error，一错一成记 DIFF）。
///
/// **当前形态（S5 开工批）**：codegen 骨架——Pass 1 全量（全局注册/
/// 初始化位模式/字符串延迟回填）+ Pass 2/3 最小集（Block/Expr(stmt)/
/// Return + 四字面量/Identifier 表达式）+ 入口 wrapper；其余语句/表达式
/// 族 fail loud（`…未实现（S5 在途）`错误文本）。语料大面积 gen 失败
/// 属预期红面基线期（同 S4 typeck_diff 模式），扩展批逐族收敛。
///
/// 用法错（缺参/参数过多/输出目录与语料目录相同）= 原因行 + rc=4
///（#230 治理，2026-10-27——旧走未捕获 Failure 的 PanicError 栈 +
/// rc=127）。
extern "C" fn c_exit(code : Int32) -> Unit = "exit"

///|
fn main raise {
  @content_data.install_baked() // #130 批③a：烘焙教学表装载（lean 拆包后引擎默认空表）
  let args = @env.args()
  // --library：library mode（预编译 Bytecode Libc 自身——不预注册固定索引段、
  // 全局偏移自 0 起；见 @codegen.compile_library）。**main 检查不豁免**，与
  // Rust `vitro_cli export` 的 stub 口径同构（那边也要求自带 main）。
  let mut library = false
  let positional : Array[String] = []
  let mut idx = 1
  while idx < args.length() {
    if args[idx] == "--library" {
      library = true
    } else {
      positional.push(args[idx])
    }
    idx = idx + 1
  }
  if positional.length() < 2 {
    println("用法: dump_compile <corpus_dir|file.c> <out_dir> [--library]")
    c_exit(4)
  }
  if positional.length() > 2 {
    // 防御（2026-09-21 实踩：两语料目录连传时 out_dir 落成语料目录，
    // 81 个 dump 产物污染 native/tests/cases——本工具契约单语料 + 单
    // 输出目录，多余参数直接 fail loud）
    println(
      "参数过多：期望 <corpus_dir|file.c> <out_dir> [--library]（实测 \{positional.length()} 个位置参数）",
    )
    c_exit(4)
  }
  let target = positional[0]
  let out_dir = positional[1]
  if target == out_dir {
    println("输出目录与语料目录相同——拒绝写入门禁")
    c_exit(4)
  }
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir)
  }
  let files : Array[String] = []
  let target_is_dir = @fs.is_dir(target) catch { _ => false }
  let shared_vfs : Map[String, String] = if target_is_dir {
    let vfs : Map[String, String] = Map([])
    collect_files(target, vfs)
    vfs
  } else {
    Map([])
  }
  if target_is_dir {
    for name in @fs.read_dir(target) {
      if name.length() > 2 && name[name.length() - 2:] == ".c" {
        files.push("\{target}/\{name}")
      }
    }
    // 字典序排序（内置 String sort 非字典序——陷阱 #29；与 codegen_diff
    // 的 Go sort.Strings 对齐，报告序稳定）
    sort_files_lex(files)
  } else {
    files.push(target)
  }
  for path in files {
    let src = @fs.read_file_to_string(path)
    let stem = basename_keep_ext(path)
    // BUG-C 修复（2026-10-05，S9 修复批批一后继）：目录模式补 base_dir——
    // VFS 键带目录前缀而解析走裸名，quote-include 恒 miss → include 族
    // 全部 lex-fail（存量 e2_include* 五条既如此，S2 §7-5 与 dump_typeck
    // 头注"注入实际无效"在案）；对齐 dump_tokens 先例（base_dir=
    // dir_of(path)，候选链与 VFS 键同口径）。单文件模式连坐：现场
    // 收集所在目录 .h 进 VFS + 同款 base_dir
    let lexed = if target_is_dir {
      @lexer.tokenize_with_vfs(src, files=shared_vfs, base_dir=dir_of(path))
    } else {
      let v : Map[String, String] = Map([])
      collect_files(dir_of(path), v)
      @lexer.tokenize_with_vfs(src, files=v, base_dir=dir_of(path))
    }
    let out = dump_one(lexed, library)
    // stem 含 .c（F11 规格：与 parser_diff/typeck_diff 既有对拍约定同源）
    @fs.write_string_to_file("\{out_dir}/\{stem}.compile.json", out)
  }
  println("dump_compile: \{files.length()} 个输入 -> \{out_dir}")
}

///|
/// 单输入 dump：管线逐层 fail loud——stage 标注失败层。
/// `library`：以 library mode 生成（见 @codegen.compile_library——预编译
/// Bytecode Libc 自身用；不预注册固定索引段、全局偏移自 0 起）。
fn dump_one(lexed : @lexer.LexResult, library : Bool) -> String {
  if !lexed.errors.is_empty() {
    return fail_json(
      "lex",
      lexed.errors.length().to_string() + " 个词法错误",
    )
  }
  let r = @parser.parse(lexed.tokens)
  if !r.errors.is_empty() || r.program is None {
    let count = if r.program is None && r.errors.is_empty() {
      "1"
    } else {
      r.errors.length().to_string()
    }
    return fail_json("parse", count + " 个解析错误")
  }
  let p = match r.program {
    Some(p) => p
    None => abort("unreachable：None 已在上方拦截")
  }
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, _w, _h) = tc.check(p)
  if type_errors.length() > 0 {
    return fail_json(
      "type",
      type_errors.length().to_string() + " 个类型错误",
    )
  }
  let (output, gen_errors) = if library {
    @codegen.compile_library(typed)
  } else {
    @codegen.compile(typed)
  }
  match output {
    // 包装层携带 slot_strategy + verify（#200 P0：bytecode 结构验证器——
    // 每例产物编译即过验，违约结构化外发；两字段都不参与 14 键 dump 对拍
    // 面（零 digest 扰动），codegen_diff 按外层字段计红：verify 失败 =
    // CONTENT 级真红、字段缺失 = 协议缺位红）
    Some(o) => {
      let violations = @bytecode.verify_compile_output(o, library)
      // 插值嵌套转义引号撑爆 lexer（陷阱 #12 同族）——buf 拼接
      let buf = StringBuilder()
      buf.write_string("{\"ok\":true,\"slot_strategy\":")
      buf.write_string(@codegen.SLOT_STRATEGY_VERSION.to_string())
      buf.write_string(",\"verify\":{\"ok\":")
      buf.write_string(violations.is_empty().to_string())
      buf.write_string(",\"violations\":")
      buf.write_string(@bytecode.verify_violations_json(violations))
      buf.write_string("},\"dump\":")
      buf.write_string(@bytecode.compile_output_dump_json(o))
      buf.write_string("}")
      buf.to_string()
    }
    None =>
      // #223：gen_errors 结构化（GenError）——join 消费面取 message 域
      fail_json("gen", gen_errors.map(fn(e) { e.message }).join("\n"))
  }
}

///|
/// errors 数组单元素（json_escape_string 返回带引号的完整 JSON 串——
/// 转义单源在 ast，此处不再重复包裹）。
fn fail_json(stage : String, msg : String) -> String {
  "{\"ok\":false,\"stage\":\"\{stage}\",\"errors\":[\{@ast.json_escape_string(msg)}]}"
}

///|
/// basename 保留扩展名（F11：对拍键约定 = stem 含 .c；函数名即语义——
/// 此前叫 basename_no_ext 名实相反，2026-09-21 审阅更名）。
fn basename_keep_ext(path : String) -> String {
  let mut name = path
  let mut i = path.length() - 1
  while i >= 0 {
    if path[i] == '/' || path[i].to_int() == 92 {
      name = path[i + 1:].to_owned()
      break
    }
    i -= 1
  }
  name
}

///|
/// 路径目录段（dir_of 族同义复制件——cmd 层互不可 import；唯一分隔符
/// 在 0 位 = POSIX 根级文件（"/x.c"）返回 "/"——#378：旧 dirname_of 返回
/// "" 作 base_dir ⇒ 根级主文件 quote-include 候选链失配；无分隔符返回
/// "."（collect_files 裸名键约定依赖此值）。**中段原文透传不归一**——
/// 目录模式 VFS 键 = target 参数原文拼装（Windows 反斜杠形态），base_dir
/// 须与其同源；归一会让候选键与 VFS 键结构性失配 ⇒ include 恒 miss
/// （2026-10-29 diff_gate typeck 五案例回归实证后回退，与 gateway 系
/// dir_of 的归一形态有意分叉：gateway 侧候选键经 normalize_path 消费）。
/// 修改须与其余 dump 三包的 dir_of 同步）。
fn dir_of(path : String) -> String {
  let mut last = -1
  for i = 0; i < path.length(); i = i + 1 {
    let c = path[i]
    if c.to_int() == 47 || c.to_int() == 92 {
      last = i
    }
  }
  if last == 0 {
    "/"
  } else if last < 0 {
    "."
  } else {
    path[0:last].to_owned()
  }
}

///|
fn collect_files(dir : String, vfs : Map[String, String]) -> Unit raise {
  for name in @fs.read_dir(dir) {
    let full = vfs_join(dir, name)
    let sub_is_dir = @fs.is_dir(full) catch { _ => false }
    if sub_is_dir {
      collect_files(full, vfs)
    } else if name.length() > 2 && name[name.length() - 2:] == ".h" {
      // 目录级 vfs：同目录头文件供 quote-include 候选（S2 §7-5 教训：
      // 两侧同无解析属偶然对齐，哨兵用例在 gap 监测）
      vfs.set(full, @fs.read_file_to_string(full))
    }
  }
}

///|
/// collect_files 的 VFS 键拼装（PR #380 审阅 P2-1 从内联提取单点锚定）：
/// "." 裸名（与 resolver 候选键 normalize_path 丢 "." 段一致——2026-10-06
/// 审阅 P2-b，旧 "./hdr.h" 键结构性失配致同目录 include 恒 lex-fail）；
/// "/"（dir_of 根级产物）直拼 "/"+name——中段风格拼装会产 "//x.h"，与
/// 候选键经 normalize_path 折叠的 "/x.h" 失配（VfsProvider 纯内存精确
/// 匹配无回落）⇒ 根级 include 恒 E1021；其余 dir+"/"+name 原文（中段
/// 原文透传——与目录模式 VFS 收集键=target 原文同源约束，#378 回归实证）。
fn vfs_join(dir : String, name : String) -> String {
  if dir == "." {
    name
  } else if dir == "/" {
    "/" + name
  } else {
    "\{dir}/\{name}"
  }
}

///|
/// 码元字典序排序（陷阱 #29：内置 String 比较疑似长度优先，禁用于排序）。
fn sort_files_lex(files : Array[String]) -> Unit {
  let mut i = 1
  while i < files.length() {
    let k = files[i]
    let mut j = i - 1
    while j >= 0 && @util.str_cmp(files[j], k) > 0 {
      files[j + 1] = files[j]
      j -= 1
    }
    files[j + 1] = k
    i += 1
  }
}
