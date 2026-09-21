///|
/// S5 差分出口（开发工具，native only）：批量产出 codegen 层 dump——
/// CompileOutput 13 字段全量 JSON（A 级产物对拍面）。
///
/// 用法：moon run cmd/dump_compile -- <corpus_dir|file.c> <out_dir>
///
/// 输出（每输入 <name>.c）：
/// - <name>.c.compile.json：
///   成功 → {"ok":true,"dump":{...14 键（version+13 字段）...}}
///   （dump 键内的形态与 Rust `vitro_cli dump-compile` 的 CompileDump
///   逐字段同构——`@bytecode.compile_output_dump_json` emitter）
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
fn main raise {
  let args = @env.args()
  if args.length() < 3 {
    println("用法: dump_compile <corpus_dir|file.c> <out_dir>")
    fail("参数不足")
  }
  if args.length() > 3 {
    // 防御（2026-09-21 实踩：两语料目录连传时 out_dir 落成语料目录，
    // 81 个 dump 产物污染 native/tests/cases——本工具契约单语料 + 单
    // 输出目录，多余参数直接 fail loud）
    fail("参数过多：期望 <corpus_dir|file.c> <out_dir> 两个参数（实测 \{args.length() - 1} 个）")
  }
  let target = args[1]
  let out_dir = args[2]
  if target == out_dir {
    fail("输出目录与语料目录相同——拒绝写入门禁")
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
    let lexed = if target_is_dir {
      @lexer.tokenize_with_vfs(src, files=shared_vfs)
    } else {
      @lexer.tokenize(src)
    }
    let out = dump_one(lexed)
    // stem 含 .c（F11 规格：与 parser_diff/typeck_diff 既有对拍约定同源）
    @fs.write_string_to_file("\{out_dir}/\{stem}.compile.json", out)
  }
  println("dump_compile: \{files.length()} 个输入 -> \{out_dir}")
}

///|
/// 单输入 dump：管线逐层 fail loud——stage 标注失败层。
fn dump_one(lexed : @lexer.LexResult) -> String {
  if !lexed.errors.is_empty() {
    return fail_json("lex", lexed.errors.length().to_string() + " 个词法错误")
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
    return fail_json("type", type_errors.length().to_string() + " 个类型错误")
  }
  let (output, gen_errors) = @codegen.compile(typed)
  match output {
    // 包装层携带 slot_strategy（槽位策略版本进产物出口——§6"版本化"
    // 的消费点；对拍面只取 .dump，本字段不参与 14 键比对，v2 切换时
    // codegen_diff 可按此分档）
    Some(o) => "{\"ok\":true,\"slot_strategy\":\{@codegen.SLOT_STRATEGY_VERSION},\"dump\":\{@bytecode.compile_output_dump_json(o)}}"
    None => fail_json("gen", gen_errors.join("\n"))
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
fn collect_files(dir : String, vfs : Map[String, String]) -> Unit raise {
  for name in @fs.read_dir(dir) {
    let full = "\{dir}/\{name}"
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
/// 码元字典序排序（陷阱 #29：内置 String 比较疑似长度优先，禁用于排序）。
fn sort_files_lex(files : Array[String]) -> Unit {
  let mut i = 1
  while i < files.length() {
    let k = files[i]
    let mut j = i - 1
    while j >= 0 && str_cmp(files[j], k) > 0 {
      files[j + 1] = files[j]
      j -= 1
    }
    files[j + 1] = k
    i += 1
  }
}

///|
fn str_cmp(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a[i].to_int()
    let y = b[i].to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if a.length() == b.length() {
    0
  } else if a.length() < b.length() {
    -1
  } else {
    1
  }
}
