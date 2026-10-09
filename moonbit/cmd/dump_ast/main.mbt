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
fn main raise {
  let args = @env.args()
  if args.length() < 3 {
    println("用法: dump_ast <corpus_dir|file.c> <out_dir>")
    fail("参数不足")
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
      @lexer.tokenize_with_vfs(src, files=shared_vfs, base_dir=dirname_of(path))
    } else {
      let v : Map[String, String] = Map([])
      collect_files(dirname_of(path), v)
      @lexer.tokenize_with_vfs(src, files=v, base_dir=dirname_of(path))
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
/// 路径目录段（dump_tokens 同款复制——cmd 层互不可 import）。
fn dirname_of(path : String) -> String {
  let mut i = path.length() - 1
  while i >= 0 {
    let c = path[i].to_int()
    if c == '/' || c == '\\' {
      return path[0:i].to_owned()
    }
    i -= 1
  }
  "."
}

///|
fn collect_files(dir : String, vfs : Map[String, String]) -> Unit raise {
  for name in @fs.read_dir(dir) {
    // 审阅 P2-b（2026-10-06）：dir 为 "."（裸名/./x.c 形态的 dirname_of 产物）
    // 时键用裸名——与 resolver 候选键经 normalize_path（丢 "." 段）一致；
    // 旧 "./hdr.h" 键结构性失配致同目录 include 恒 lex-fail
    let full = if dir == "." { name } else { "\{dir}/\{name}" }
    let is_dir = @fs.is_dir(full) catch { _ => false }
    if is_dir {
      collect_files(full, vfs)
    } else {
      let content = @fs.read_file_to_string(full) catch { _ => continue }
      vfs.set(full, content)
    }
  }
}
