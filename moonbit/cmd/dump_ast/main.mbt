///|
/// S3 差分出口（开发工具，native only）：批量产出解析层 dump——AST JSON
///（E1 面，@ast.ast_dump_json 与 Rust serde 输出经 Go canonicalizer 归一
/// 后逐字节比对）+ 诊断序列 TSV（E2 面：code/line/column/保序，message
/// 单列）+ 活性计数（勘察 6-3 观测义务）。
///
/// 用法：moon run cmd/dump_ast -- <corpus_dir|file.c> <out_dir>
///
/// 输出（每输入 <name>.c）：
/// - <name>.ast.json：与 Rust serve `ast.dump` 响应同构——
///   {"ok":bool,"parse_error_count":N,"ast":{...}|null,
///    "parse_errors":[{code,line,column,message},...],"stall_count":N}
/// - 病态样本对齐：两侧崩溃即硬失败（E3 由 Go 驱动断言退出码）
/// 用法错（缺参）= 用法行 + rc=4（#230 治理，2026-10-27——旧走未捕获
/// Failure 的 PanicError 栈 + rc=127）。
extern "C" fn c_exit(code : Int32) -> Unit = "exit"

///|
fn main raise {
  let args = @env.args()
  if args.length() < 3 {
    println("用法: dump_ast <corpus_dir|file.c> <out_dir>")
    c_exit(4)
  }
  let target = args[1]
  let out_dir = args[2]
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir)
  }
  let files : Array[String] = []
  let target_is_dir = @fs.is_dir(target) catch { _ => false }
  // 自定义 include 的 Vfs 目录级收集一次共享（S2 §7.5 性能教训）
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
    files.sort()
  } else {
    files.push(target)
  }
  for path in files {
    let src = @fs.read_file_to_string(path)
    let stem = basename_no_ext(path)
    let lexed = if target_is_dir {
      // BUG-C 修复（2026-10-05，S9 修复批批一后继）：补 base_dir——VFS 键
      // 带目录前缀而解析走裸名，include 恒 miss（"两侧同失败偶然对齐"
      // S2 §7-5 在案）；对齐 dump_tokens 先例。单文件模式连坐同款装配
      @lexer.tokenize_with_vfs(src, files=shared_vfs, base_dir=dir_of(path))
    } else {
      let v : Map[String, String] = Map([])
      collect_files(dir_of(path), v)
      @lexer.tokenize_with_vfs(src, files=v, base_dir=dir_of(path))
    }
    let out = dump_one(lexed)
    @fs.write_string_to_file("\{out_dir}/\{stem}.ast.json", out)
  }
  println("dump_ast: \{files.length()} 个输入 -> \{out_dir}")
}

///|
/// 单输入 dump：词法错误 → ok:false 同构（AST 无从谈起）；解析层带
/// 完整 parse_errors（E2 面——Rust 侧同批补齐，见防线维护提交）。
fn dump_one(lexed : @lexer.LexResult) -> String {
  let buf = StringBuilder()
  if !lexed.errors.is_empty() {
    buf.write_string("{\"ok\": false, \"lex_error_count\": ")
    buf.write_string(lexed.errors.length().to_string())
    buf.write_string(
      ", \"ast\": null, \"parse_errors\": [], \"stall_count\": 0}",
    )
    return buf.to_string()
  }
  let r = @parser.parse(lexed.tokens)
  buf.write_string("{\"ok\": ")
  buf.write_string(if r.program is Some(_) { "true" } else { "false" })
  buf.write_string(", \"parse_error_count\": ")
  buf.write_string(r.errors.length().to_string())
  buf.write_string(", \"ast\": ")
  match r.program {
    Some(p) => buf.write_string(@ast.ast_dump_json(p))
    None => buf.write_string("null")
  }
  buf.write_string(", \"parse_errors\": [")
  for i, e in r.errors {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(
      "{\"code\": \{e.code}, \"line\": \{e.line}, \"column\": \{e.column}, \"message\": \{@ast.json_escape_string(e.message)}}",
    )
  }
  buf.write_string("], \"stall_count\": \{r.stall_count}}")
  buf.to_string()
}

// 字符串转义已收口 @ast.json_escape_string（转义体在 vitro/engine/util，
// issue #55 六份收一；原本地副本语义一致——带引号包裹 + 全量控制字符转义）。

///|
fn basename_no_ext(path : String) -> String {
  let mut name = path
  let mut i = path.length() - 1
  while i >= 0 {
    let slash = '/'.to_int()
    let bslash = 92 // '\'
    let dot = '.'.to_int()
    match path[i].to_int() {
      c if c == slash || c == bslash => {
        name = path[i + 1:].to_owned()
        break
      }
      c if c == dot => if name == path { name = path[0:i].to_owned() }
      _ => ()
    }
    i -= 1
  }
  name
}

///|

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
