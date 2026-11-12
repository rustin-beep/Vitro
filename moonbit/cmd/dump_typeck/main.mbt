///|
/// S4 差分出口（开发工具，native only）：批量产出类型检查层 dump——
/// typed_ast JSON（E4 面：lowering 后 ProgramNode）+ 三段诊断序列
/// （E1 面：type_errors/type_warnings/type_hints，{code,line,column,
/// message} push 序保序）。
///
/// 用法：moon run cmd/dump_typeck -- <corpus_dir|file.c> <out_dir>
///
/// 输出（每输入 <name>.c）：
/// - <name>.c.typeck.json：与 Rust serve `typeck.dump` 响应同构——
///   {"ok":bool,"parse_error_count":N,"typed_ast":{...}|null,
///    "parse_errors":[...],
///    "type_errors":[...],"type_warnings":[...],"type_hints":[...]}
///
/// **当前形态**：typeck C 子集 4 Pass **全量接线**（T5-b/c/d 批收官，
/// 2026-09-20）——Pass 1（struct/union 注册 + T-P0-8 环检测）/ Pass 2
/// （函数签名两轨）/ Pass 2.5（全局 auto/typeof 先定型 + 数组/struct
/// 初始化器 + 尺寸推断回写）/ Pass 3（函数体 visitor：语句族 + VarDecl
/// 巨臂 + goto/label 闭合）；表达式定型全变体（运算符/Call/CallPtr/
/// CompoundLiteral）。598 语料 E1–E4 归一逐字节一致（2 条 F3-v2 白
/// 名单 FORK(known)，见 scripts/typeck_diff）。E2/E3 面不独立出口
/// （驱动从 typed_ast 投影派生——改形登记见总计划 §10 S4 行）。
///
/// **载体观察（2026-09-20 审阅登记；2026-10-05 已修——BUG-C）**：目录
/// 模式曾因 base_dir 缺失令 dir-wide vfs 注入实际无效（quote-include
/// 候选键与 vfs 路径键结构性不命中，include 恒 lex-fail——"两侧同失败"
/// 的一致属偶然对齐）；修复 = tokenize_with_vfs 补 base_dir=
/// dir_of(path)（dump_tokens 先例同款），哨兵 gap/include_quote_
/// sentinel.c 已翻转并随 golden 重刷（哨兵设计兑现：任一侧 vfs 行为
/// 独立变化即红）。
///
/// 用法错（缺参/参数过多/输出目录与语料目录相同）= 原因行 + rc=4
///（#230 治理，2026-10-27——旧走未捕获 Failure 的 PanicError 栈 +
/// rc=127；参数过多与 out==target 门禁 B3 批 2026-11-02 四家连坐补齐，
/// 模板 = dump_compile 既有防御形态，详见 dump_ast 头注 M36 C2 注记）。
/// 输入不可读（不存在/无权限）= 原因行 + rc=4（#445 C1，2026-11-12——
/// #230 治理在 dump 族读文件面的收尾，详见 dump_ast 头注）。
extern "C" fn c_exit(code : Int32) -> Unit = "exit"

///|
fn main raise {
  @content_data.install_baked() // #130 批③a：烘焙教学表装载（lean 拆包后引擎默认空表）
  let args = @env.args()
  if args.length() < 3 {
    println("用法: dump_typeck <corpus_dir|file.c> <out_dir>")
    c_exit(4)
  }
  if args.length() > 3 {
    println(
      "参数过多：期望 <corpus_dir|file.c> <out_dir>（实测 \{args.length() - 1} 个位置参数）",
    )
    c_exit(4)
  }
  let target = args[1]
  let out_dir = args[2]
  if norm_path(target) == norm_path(out_dir) {
    println("输出目录与语料目录相同——拒绝写入门禁")
    c_exit(4)
  }
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir)
  }
  let files : Array[String] = []
  let target_is_dir = @fs.is_dir(target) catch { _ => false }
  // 自定义 include 的 Vfs 目录级收集一次共享（S2 §7-5 性能教训）
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
    // 码元字典序（#445 B2，2026-11-12：自内置 files.sort() 迁入——内置序是
    // 长度优先 + 等长码元序（util 探针实测 cmp("e2_x.c","e10_y.c")=-1 而字典
    // 序应 +1），与 compile 壳既有 sort_files_lex 统一，四壳处理序同形）
    sort_files_lex(files)
  } else {
    files.push(target)
  }
  for path in files {
    // 不可读输入 = 原因行 + rc=4（#445 C1，2026-11-12：#230 治理收口——旧
    // 裸调 read_file_to_string，不存在路径走未捕获 IOError 的 PanicError 栈
    // + rc=127，差分驱动传错路径时拿栈噪声而非一行原因）
    let src = match read_input_or_reason(path) {
      Ok(s) => s
      Err(reason) => {
        println(reason)
        c_exit(4)
        abort("unreachable：c_exit 已退出")
      }
    }
    let stem = basename_keep_ext(path)
    let lexed = if target_is_dir {
      // BUG-C 修复（2026-10-05，S9 修复批批一后继）：补 base_dir——头注
      // 2020-09-20 审阅登记的「注入实际无效」（./x.h 与 VFS 绝对键结构性
      // 不命中）就此销案；对齐 dump_tokens 先例。单文件模式连坐同款装配
      @lexer.tokenize_with_vfs(src, files=shared_vfs, base_dir=dir_of(path))
    } else {
      let v : Map[String, String] = Map([])
      collect_files(dir_of(path), v)
      @lexer.tokenize_with_vfs(src, files=v, base_dir=dir_of(path))
    }
    let out = dump_one(lexed)
    // stem 含 .c（F11 规格：与 parser_diff/typeck_diff 既有对拍约定同源）——
    // 旧注「basename_no_ext 实为取 basename 不去扩展名、勿修正」只在目录
    // 模式成立（裸名单文件丢 .c），B3 批正名 basename_keep_ext 后两模式同果
    @fs.write_string_to_file("\{out_dir}/\{stem}.typeck.json", out)
  }
  println("dump_typeck: \{files.length()} 个输入 -> \{out_dir}")
}

///|
/// 单输入 dump：词法错误 → ok:false 同构（typeck 无从谈起，lex_error_count
/// 面）；解析层带完整 parse_errors；parse 错误 → typeck 不跑（管线语义：
/// parse_errors 非空即止，与 Rust compile_pipeline 对齐）。
fn dump_one(lexed : @lexer.LexResult) -> String {
  let buf = StringBuilder()
  if !lexed.errors.is_empty() {
    buf.write_string("{\"ok\": false, \"lex_error_count\": ")
    buf.write_string(lexed.errors.length().to_string())
    buf.write_string(
      ", \"typed_ast\": null, \"parse_errors\": [], \"type_errors\": [], \"type_warnings\": [], \"type_hints\": []}",
    )
    return buf.to_string()
  }
  let r = @parser.parse(lexed.tokens)
  // 管线语义：parse 错误非空（无论 program 是否带占位）→ typeck 不跑
  if !r.errors.is_empty() || r.program is None {
    buf.write_string("{\"ok\": false, \"parse_error_count\": ")
    buf.write_string(r.errors.length().to_string())
    buf.write_string(", \"typed_ast\": null, \"parse_errors\": [")
    for i, e in r.errors {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string(
        "{\"code\": \{e.code}, \"line\": \{e.line}, \"column\": \{e.column}, \"message\": \{@ast.json_escape_string(e.message)}}",
      )
    }
    buf.write_string(
      "], \"type_errors\": [], \"type_warnings\": [], \"type_hints\": []}",
    )
    return buf.to_string()
  }
  // —— typeck 实接线（C 子集 4 Pass；表达式族/初始化器/函数体 visitor
  // 随下批补——当前 Pass 1/2/2.5 部分面）——
  let p = match r.program {
    Some(p) => p
    None => abort("unreachable：None 已在上方拦截")
  }
  let tc = @typeck.TypeChecker::new()
  let (typed, type_errors, type_warnings, type_hints) = tc.check(p)
  buf.write_string("{\"ok\": true, \"parse_error_count\": 0, \"typed_ast\": ")
  buf.write_string(@ast.ast_dump_json(typed))
  buf.write_string(", \"parse_errors\": [], \"type_errors\": [")
  write_diag_array(buf, type_errors)
  buf.write_string("], \"type_warnings\": [")
  write_diag_array(buf, type_warnings)
  buf.write_string("], \"type_hints\": [")
  write_diag_array(buf, type_hints)
  buf.write_string("]}")
  buf.to_string()
}

///|
/// 三段诊断序列序列化（{code,line,column,message} push 序保序——与
/// parse_errors 同形态）。
fn write_diag_array(
  buf : StringBuilder,
  diags : Array[@typeck.TypeError],
) -> Unit {
  for i, e in diags {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(
      "{\"code\": \{e.code}, \"line\": \{e.line}, \"column\": \{e.column}, \"message\": \{@ast.json_escape_string(e.message)}}",
    )
  }
}

// 字符串转义已收口 @ast.json_escape_string（转义体在 vitro/engine/util，
// issue #55 六份收一；原本地副本语义一致——带引号包裹 + 全量控制字符转义）。

///|
/// basename 保留扩展名（F11：对拍键约定 = stem 含 .c——产物名
/// `<name>.c.typeck.json` 与头注承诺同源）。B3 批（2026-11-02，M36 A1）：
/// 旧 basename_no_ext 点 arm 在「尚未遇分隔符」时截扩展名——目录模式保留
/// .c、裸名单文件丢 .c，同函数两种行为；现与 dump_compile/dump_ast 同形
/// 恒保留（详见 dump_ast 同名函数注）。
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

///|
/// 路径归一（纯字符串域、零 fs 依赖——PR #450 审阅 P2-3，2026-11-02）：`\` 折叠为
/// `/`、剥 `.` 与空段、`..` 弹栈（栈空或栈顶已是 `..` 则保留——相对上溯语义）、
/// 尾分隔符忽略。out==target 门禁旧形态是裸字符串相等——`corpus` vs `./corpus` vs
/// `corpus/` vs `a/../corpus` 同义路径全放行，实测产物仍写进语料目录（审阅亲踩）。
/// **与 realpath 的差异**：不触盘、不解析符号链接/盘符大小写/当前目录——教学工具
/// 本地调用域足够，真要绝对化需 fs 层 realpath（本包 vendored fs 无此 API）。
/// dir_of 族同义复制件——修改须与其余 dump 三包同步。
fn norm_path(p : String) -> String {
  // 反斜杠折叠：String::replace 只替换首个（陷阱 #37），循环到不含为止——先例
  // host_io.mbt from_stdin_text 的 CRLF 规整
  let mut unified = p
  while unified.contains("\\") {
    unified = unified.replace(old="\\", new="/")
  }
  let segs : Array[String] = []
  for seg in unified.split("/") {
    let s : String = seg.to_owned()
    if s == "" || s == "." {
      continue
    }
    if s == ".." {
      if segs.length() > 0 && segs[segs.length() - 1] != ".." {
        ignore(segs.remove(segs.length() - 1))
      } else {
        segs.push("..")
      }
      continue
    }
    segs.push(s)
  }
  segs.join("/")
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
/// IOError 的一行文本（#445 C1：输入不可读原因行——suberror IOError(String)
/// 单字段形态）。四 dump 同形复制件——cmd 层互不可 import。
fn io_error_text(e : @fs.IOError) -> String {
  let IOError(msg) = e
  msg
}

///|
/// 输入不可读的退出决策文案（#445 C1，纯函数——wbtest 锚打此面）：一行
/// 原因 + rc=4 与用法错同档；#230 治理收尾（旧走未捕获 raise 的
/// PanicError 栈 + rc=127，对脚本与 IDE 都是噪声——native 侧子进程锚在
/// scripts/vitro_cli_smoke D 组）。目录模式此面不可达（文件名来自
/// read_dir 快照、collect_files 侧已 catch），单文件模式 typo 路径直达。
fn unreadable_reason(path : String, e : @fs.IOError) -> String {
  "输入不可读：\{path}（\{io_error_text(e)}）"
}

///|
/// 主循环输入源读取（#445 C1 fail loud 收口）。
fn read_source_or_exit(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    e => {
      println(unreadable_reason(path, e))
      c_exit(4)
      ""
    }
  }
}

///|
/// 字典序排序（内置 String sort 是**长度优先序**——陷阱 #29；SWEEP1
/// #445 B2 探针实锤：ASCII 域亦分叉〔corpus 1176 文件名内置序 vs 字典序
/// 逐位全异，定向样本 `b.c < aa.c`——长度优先铁证〕，非「非 ASCII 域才
/// 需裁定」）。与 codegen_diff 的 Go sort.Strings 对齐（报告序稳定）；
/// 四 dump 同形复制件——cmd 层互不可 import。
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

///|
fn collect_files(dir : String, vfs : Map[String, String]) -> Unit raise {
  for name in @fs.read_dir(dir) {
    let full = vfs_join(dir, name)
    let is_dir = @fs.is_dir(full) catch { _ => false }
    if is_dir {
      collect_files(full, vfs)
    } else {
      let content = @fs.read_file_to_string(full) catch { _ => continue }
      vfs.set(full, content)
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
/// 输入读取单点出口（#445 C1，2026-11-12）：不可读输入（不存在/无权限/
/// 目录形态）→ Err(原因行文案)，main 侧 println + c_exit(4)——与用法错
/// 门禁同构（#230 治理面）。四 dump 壳同义复制件——修改须与其余三家同步。
fn read_input_or_reason(path : String) -> Result[String, String] {
  Ok(
    @fs.read_file_to_string(path) catch {
      IOError(msg) => return Err("输入不可读：\{path}（\{msg}）")
    },
  )
}

///|
/// 码元字典序排序（陷阱 #29：内置 String 比较是长度优先序，禁用于排序）。
/// 四 dump 壳同义复制件——修改须与其余三家同步。
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
