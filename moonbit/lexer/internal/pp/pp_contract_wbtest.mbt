///|
/// #338 批四（2026-10-27）：pp 包首个直接单测——此前 3425 行零直接锚
///（行为只经上层 lexer/parser 黑盒间接覆盖）。最小契约集：BOM 剥除、
/// splice 续行拼接、#ifdef 真/假臂、#define 对象宏展开（经 finish_pp
/// 收尾）。完整 include/递归面留给差分域，此处锁主管线不变量。

///|
/// 内存单表 provider（include 解析后的候选路径查表——trait 语义只查表）。
struct MapProvider {
  files : Map[String, String]
}

///|
fn MapProvider::of(entries : Array[(String, String)]) -> MapProvider {
  let m : Map[String, String] = Map([])
  for e in entries {
    m.set(e.0, e.1)
  }
  { files: m, }
}

///|
impl @token.SourceProvider for MapProvider with fn read(self, path : String) -> String raise @token.SourceError {
  match self.files.get(path) {
    Some(s) => s
    None => raise @token.SourceError::NotFound(path~)
  }
}

///|
/// 全管线便捷：run_pp(emit_eof) → finish_pp（宏展开 + 未闭合组报错）。
fn pp_full(src : String) -> @token.LexResult {
  let pp = Pp::new(provider=MapProvider::of([]), cpp_mode=false)
  let toks = pp.run_pp(src, emit_eof=true)
  pp.finish_pp(toks)
}

///|
fn summary(r : @token.LexResult) -> String {
  r.tokens
  .map(t => {
    "\{t.ty.to_name()}:\{t.text.replace(old="\n", new="\\n")}@\{t.loc.line}"
  })
  .join(" ")
}

///|
test "pp_bom_stripped" {
  // BOM 剥除（修复 ⑥-8 已知差异面：L2 剥、L1 不剥保持可比）
  let r = pp_full("﻿int x;\n")
  assert_eq(r.errors.length(), 0, msg="BOM 后首 token 不得报错")
  inspect(
    summary(r),
    content=(
      #|Int:int@1 Identifier:x@1 Semicolon:;@1 Eof:@2
    ),
  )
}

///|
test "pp_splice_continuation_line" {
  // 反斜杠续行拼接成一行逻辑行；行号 = 首物理行
  let r = pp_full("int\\\n x;\n")
  assert_eq(r.errors.length(), 0)
  inspect(
    summary(r),
    content=(
      #|Int:int@1 Identifier:x@1 Semicolon:;@1 Eof:@3
    ),
  )
}

///|
test "pp_ifdef_true_and_false_arms" {
  let src = "#define A\n#ifdef A\nint yes;\n#else\nint no;\n#endif\n"
  let r = pp_full(src)
  assert_eq(r.errors.length(), 0)
  inspect(
    summary(r),
    content=(
      #|Int:int@3 Identifier:yes@3 Semicolon:;@3 Eof:@7
    ),
  )
  // 假臂整体跳过：无 no 标识符
  assert_false(
    r.tokens.any(t => t.text == "no"),
    msg="#else 假臂 token 不得进流",
  )
}

///|
test "pp_object_macro_expansion" {
  let r = pp_full("#define N 5\nint a[N];\n")
  assert_eq(r.errors.length(), 0)
  // 对象宏展开：N → 5（finish_pp 内 expand_tokens_all）
  assert_true(
    r.tokens.any(t => t.ty is Number && t.text == "5"),
    msg="N 须展开为 5",
  )
  assert_false(r.tokens.any(t => t.text == "N"), msg="N 不得残留")
}

///|
test "pp_unclosed_ifdef_reports_open_line" {
  let r = pp_full("#ifdef A\nint x;\n")
  // E1013 按开启行报告（⑥-23 修复面——Rust 报 EOF 行为差异登记）
  assert_eq(r.errors.length(), 1)
  let e = r.errors[0]
  assert_eq(e.loc.line, 1)
  assert_true(e.code is E1013_UnclosedConditional)
}

///|
test "normalize_path_posix_absolute_anchor_issue356" {
  // #356 红锚（2026-10-29）：normalize_path 不得丢 POSIX 绝对路径前导 /
  // ——修前 "/home/x/h.h" → "home/x/h.h"，绝对路径主文件的 quote-include
  // 候选键与 reader/VFS 侧键永不相等（Linux 宿主 100% E1021）。盘符/
  // 相对/.. 回退三形态为既有行为守卫（修前后均须绿）。
  assert_eq(
    normalize_path("/home/x/h.h"),
    "/home/x/h.h",
    msg="绝对锚保留（修前红）",
  )
  assert_eq(normalize_path("/h.h"), "/h.h", msg="根级文件绝对锚保留")
  assert_eq(normalize_path("/"), "/", msg="根本身")
  assert_eq(
    normalize_path("D:/x/h.h"),
    "D:/x/h.h",
    msg="盘符形态不变（守卫）",
  )
  assert_eq(
    normalize_path("./h.h"),
    "h.h",
    msg="相对形态不变（守卫）",
  )
  assert_eq(
    normalize_path("a/../b.h"),
    "b.h",
    msg="相对 .. 回退不变（守卫）",
  )
  assert_eq(
    normalize_path("/a/../b.h"),
    "/b.h",
    msg="绝对 .. 回退到根不越锚",
  )
}

///|
test "resolver_posix_absolute_quote_include_issue356" {
  // #356 行为红锚：base_dir 为 POSIX 绝对路径时，quote-include 候选键
  // 保留前导 / 才能命中 provider（修前键 "home/x/hd.h" ⇒ E1021）
  let pp = Pp::new(
    provider=MapProvider::of([("/home/x/hd.h", "#define V 7\n")]),
    cpp_mode=false,
    base_dir="/home/x",
  )
  let toks = pp.run_pp("#include \"hd.h\"\nint a[V];\n", emit_eof=true)
  let r = pp.finish_pp(toks)
  assert_eq(
    r.errors.length(),
    0,
    msg="绝对 base_dir 下 include 可解析（修前红：E1021）",
  )
  assert_true(
    r.tokens.any(t => t.ty is Number && t.text == "7"),
    msg="宏 V 自绝对路径头展开",
  )
}

///|
test "resolver_absolute_operand_include_issue356r2" {
  // 审阅 P2-2（2026-10-29）：绝对路径 include 操作数直接取（C11
  // §6.10.2p3——clang/gcc 对 `#include "/abs/h.h"` 不搜索候选链）——
  // 修前无条件 cur_dir 拼接得 "/home/x/abs/h.h" ⇒ E1021
  let pp = Pp::new(
    provider=MapProvider::of([("/abs/h.h", "#define A 3\n")]),
    cpp_mode=false,
    base_dir="/home/x",
  )
  let toks = pp.run_pp("#include \"/abs/h.h\"\nint a[A];\n", emit_eof=true)
  let r = pp.finish_pp(toks)
  assert_eq(
    r.errors.length(),
    0,
    msg="绝对 include 操作数直接命中（修前红：E1021）",
  )
  assert_true(
    r.tokens.any(t => t.ty is Number && t.text == "3"),
    msg="宏 A 自绝对路径头展开",
  )
}
