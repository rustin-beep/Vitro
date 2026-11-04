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

///|
/// #432 A1（2026-11-04）：`#elifndef`/`#elifdef` 缺宏名——诊断 E1006 且
/// 分支不激活。真值（Win/WSL gcc+clang 四编译器 -E 一致）：两形态均
/// `error: macro name missing / no macro name given` 且假分支不进 -E 输出
///（gcc 对缺名 #elifndef 的错误恢复 = 分支跳过，`$$$$$$$` 不进流）。
/// 修前：read_ident("") 空串 → contains("") 恒假——`#elifndef` 取非
/// **激活假分支**（E1001 × N 进流 = 分支激活铁证）且零缺名诊断；
/// `#elifdef` 方向零诊断静默吞块。病 73（2026-10-13）修了
/// ifdef/ifndef/undef 的缺名面，elif 族漏网。
test "elifdef_missing_name_diag" {
  // 形态 1：#elifndef 缺名——修前红（E1001×7 进流 + 零 E1006）
  let r1 = pp_full(
    "#if 0\n#error no\n#elifndef\n$$$$$$$\n#endif\nint main(void){ return 0; }\n",
  )
  assert_true(
    r1.errors.any(e => e.code is E1006_UnsupportedFeature),
    msg="#elifndef 缺宏名必须有 E1006 诊断（修前零诊断）",
  )
  assert_false(
    r1.errors.any(e => e.code is E1001_UnknownChar),
    msg="缺名 #elifndef 假分支不得激活（修前 $$$$$$$ 进流报 E1001×7）",
  )
  // 形态 2：#elifdef 缺名——修前红（COMPILE-OK 零诊断吞块）
  let r2 = pp_full(
    "#ifdef NOT_DEF\nint a;\n#elifdef\nint x;\n#endif\nint main(void){ return 0; }\n",
  )
  assert_true(
    r2.errors.any(e => e.code is E1006_UnsupportedFeature),
    msg="#elifdef 缺宏名必须有 E1006 诊断（修前静默吞块）",
  )
  assert_false(
    r2.tokens.any(t => t.text == "x"),
    msg="缺名 #elifdef 分支内容不进流（两侧一致守卫）",
  )
  // 形态 3（对照）：#elif 缺表达式已有 E1014——诊断路径在（修前后均绿）
  let r3 = pp_full(
    "#if 0\n#error no\n#elif\n#endif\nint main(void){ return 0; }\n",
  )
  assert_true(r3.errors.any(e => e.code is E1014_CondExprError))
  // 守卫：正向 #elifndef Y（Y 已定义 → 取假）走 #else 分支（修前后均绿）
  let r4 = pp_full(
    "#define Y\n#if 0\n#error no\n#elifndef Y\nint a;\n#else\nint b;\n#endif\n",
  )
  assert_eq(r4.errors.length(), 0)
  assert_true(r4.tokens.any(t => t.text == "b"))
  assert_false(r4.tokens.any(t => t.text == "a"))
}

///|
/// #432 A2/A3（2026-11-04）：环检测文本级扫描的注释剥离 + `#if 0` 条件态
/// ——块注释内 / `#if 0` 块内的 `#include` 不是依赖边。真值（Win/WSL
/// gcc+clang -E 一致）：两形态 rc=0 正常编译；`#if 0 … #else` 内的自
/// include 是真边（gcc/clang 报嵌套过深拦截——vitro E1015 提前拦截同向）。
/// 修前：custom_includes_of 不剥注释无条件态 → 注释/if0 内 include 被
/// 当真边 → E1015 误报拒编译。
test "commented_include_not_edge" {
  // 形态 1：块注释内自 include（修前红：E1015 误报）
  let pp1 = Pp::new(
    provider=MapProvider::of([
      (
        "inc/selfc.h", "/* 历史引用示意：\n   #include \"selfc.h\"\n*/\n#define SELFC 1\n",
      ),
    ]),
    cpp_mode=false,
  )
  let toks1 = pp1.run_pp(
    "#include \"inc/selfc.h\"\nint v[SELFC];\n",
    emit_eof=true,
  )
  let r1 = pp1.finish_pp(toks1)
  assert_eq(
    r1.errors.length(),
    0,
    msg="注释内 include 不是边（修前红：E1015 依赖环误报）",
  )
  assert_true(
    r1.tokens.any(t => t.ty is Number && t.text == "1"),
    msg="SELFC 宏自头文件展开",
  )
  // 形态 2：#if 0 块内自 include（修前红：E1015 误报）
  let pp2 = Pp::new(
    provider=MapProvider::of([
      (
        "inc/selfc0.h", "#if 0\n#include \"selfc0.h\"\n#endif\n#define SELFC0 2\n",
      ),
    ]),
    cpp_mode=false,
  )
  let toks2 = pp2.run_pp(
    "#include \"inc/selfc0.h\"\nint v[SELFC0];\n",
    emit_eof=true,
  )
  let r2 = pp2.finish_pp(toks2)
  assert_eq(
    r2.errors.length(),
    0,
    msg="#if 0 内 include 不是边（修前红：E1015 依赖环误报）",
  )
  assert_true(
    r2.tokens.any(t => t.ty is Number && t.text == "2"),
    msg="SELFC0 宏自头文件展开",
  )
  // 守卫 1：`#if 0 … #else` 内自 include 是真边——仍报 E1015
  //（gcc/clang 嵌套过深拦截同向；修前后均绿）
  let pp3 = Pp::new(
    provider=MapProvider::of([
      (
        "inc/selfc1.h", "#if 0\n#include \"never.h\"\n#else\n#include \"selfc1.h\"\n#endif\n#define SELFC1 3\n",
      ),
    ]),
    cpp_mode=false,
  )
  let toks3 = pp3.run_pp("#include \"inc/selfc1.h\"\n", emit_eof=true)
  let r3 = pp3.finish_pp(toks3)
  assert_true(
    r3.errors.any(e => e.code is E1015_IncludeCycle),
    msg="#else 分支激活后的真环仍须拦截（防过剥）",
  )
  // 守卫 2：无守卫互含真环（e2_cycle 形态）仍报 E1015（修前后均绿）
  let pp4 = Pp::new(
    provider=MapProvider::of([
      ("inc/ca.h", "#include \"cb.h\"\nint ca(void);\n"),
      ("inc/cb.h", "#include \"ca.h\"\nint cb(void);\n"),
    ]),
    cpp_mode=false,
  )
  let toks4 = pp4.run_pp("#include \"inc/ca.h\"\n", emit_eof=true)
  let r4 = pp4.finish_pp(toks4)
  assert_true(
    r4.errors.any(e => e.code is E1015_IncludeCycle),
    msg="真环检测能力不回归（防过剥）",
  )
}

///|
/// #432 A4（2026-11-04）：函数式宏体为 `{…}` 块时**不再自动包装
/// do{…}while(0)**——`{…}` 复合语句本就是合法单语句，宏体内 break/
/// continue 须绑定外层循环。真值（Win/WSL gcc+clang 编译运行一致）：
/// `#define CHK(x) {if(x) break;}` 在 while 内调用 → break 跳出 while
///（exit=1）；continue 同理（c 只累加 2 次）。修前：
/// body_is_brace_block && followed_by_semicolon 插 do/while(0) 合成
/// token——break/continue 被劫持跳包装层（exit=3 / c=3），零诊断反转。
test "fn_macro_brace_no_dowhile_wrap" {
  // 修前红：展开序列含合成 do/while token
  let r1 = pp_full("#define CHK(x) {if(x) break;}\nCHK(1);\n")
  assert_eq(r1.errors.length(), 0)
  let has_do = r1.tokens.any(t => t.text == "do" || t.text == "while")
  assert_false(
    has_do,
    msg="{…} 宏体展开不得插入合成 do/while(0) 包装（修前红）",
  )
  inspect(
    summary(r1),
    content=(
      #|LBrace:{@2 If:if@2 LParen:(@2 Number:1@2 RParen:)@2 Break:break@2 Semicolon:;@2 RBrace:}@2 Semicolon:;@2 Eof:@3
    ),
  )
  // 守卫：宏体显式 do{…}while(0) 原样保留（包装语义正确的对照组——
  // 用户显式写 do-while 时 break 跳包装层是本意；修前后均绿）
  let r2 = pp_full("#define D(x) do{if(x) break;}while(0)\nD(1);\n")
  assert_eq(r2.errors.length(), 0)
  assert_true(r2.tokens.any(t => t.text == "do"))
  assert_true(r2.tokens.any(t => t.text == "while"))
  // continue 变体同族（修前红：SKIP 展开 do/while 包装劫持 continue）
  let r3 = pp_full("#define SKIP(x) {if(x) continue;}\nSKIP(1);\n")
  assert_false(
    r3.tokens.any(t => t.text == "do" || t.text == "while"),
    msg="{…} 宏体（continue 形态）同样不得包装",
  )
}

///|
/// #419（2026-11-03）：sanitize_surrogates 口径锚——孤立代理各替换一个
/// U+FFFD（WHATWG 最大子部分，#363 同口径），合法代理对整码点保留；
/// 快路径零重写。W4 对抗帧形态 `\ud800\udfff\udc00`（孤立高 + 孤立低×2）。
test "sanitize_surrogates_ufffd_replacement" {
  // 快路径：无代理区码元原样返回
  assert_eq(sanitize_surrogates("int main(){}"), "int main(){}")
  // 孤立高代理 → U+FFFD（EF BF BD）
  let lone_hi = (0xD800).unsafe_to_char().to_string()
  let b1 = @utf8.encode(sanitize_surrogates(lone_hi))
  assert_eq(b1.length(), 3)
  assert_true(
    b1[0] == b'\xEF' && b1[1] == b'\xBF' && b1[2] == b'\xBD',
    msg="U+FFFD 字节级替换",
  )
  // 孤立低代理 → U+FFFD（对称）
  let lone_lo = (0xDFFF).unsafe_to_char().to_string()
  let b2 = @utf8.encode(sanitize_surrogates(lone_lo))
  assert_eq(b2.length(), 3)
  assert_true(b2[0] == b'\xEF' && b2[1] == b'\xBF' && b2[2] == b'\xBD')
  // 合法代理对（D800 DC00 = U+10000 → F0 90 80 80 四字节）原样保留
  let pair = (0xD800).unsafe_to_char().to_string() +
    (0xDC00).unsafe_to_char().to_string()
  let b3 = @utf8.encode(sanitize_surrogates(pair))
  assert_eq(b3.length(), 4)
  assert_true(b3[0] == b'\xF0', msg="代理对未被误替换")
  // W4 对抗帧三连 D800 DFFF DC00：前两码元恰组合成合法对（U+103FF →
  // F0 90 8F BF 四字节），仅尾码元孤立 → 4 + 3 = 7 字节（配对优先）
  let triple = (0xD800).unsafe_to_char().to_string() +
    (0xDFFF).unsafe_to_char().to_string() +
    (0xDC00).unsafe_to_char().to_string()
  let b4 = @utf8.encode(sanitize_surrogates(triple))
  assert_eq(
    b4.length(),
    7,
    msg="合法对组合 4B + 孤立低代理 U+FFFD 3B",
  )
  assert_true(b4[0] == b'\xF0', msg="D800+DFFF 组合 U+103FF 首字节 F0")
  // 源码语境：注释位孤立代理清洗后 tokenize 正常（finish_pp 零错误）
  let pp = Pp::new(provider=MapProvider::of([]), cpp_mode=false)
  let src = "int main() { /* " +
    (0xD800).unsafe_to_char().to_string() +
    " */ return 0; }\n"
  let toks = pp.run_pp(src)
  let r = pp.finish_pp(toks)
  assert_eq(r.errors.length(), 0, msg="清洗后注释位代理项不再炸 pp")
}
