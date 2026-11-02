// #378/#380 锚：目录段函数 + VFS 键拼装的根级 POSIX 全链路。
// dump 包 native-only——裸 moon test 静默跳过本文件，
// 验证口径 `MOON_CC=clang-cl moon test --target native -p dump_compile`（Windows——
// test 面须 cl 兼容驱动，裸 clang 被忽略回落 MSVC，M37 D-6；Linux 用 clang）。

///|
/// #378：唯一分隔符在 0 位 = POSIX 根级文件（"/x.c"），目录段须返回
/// "/"——旧实现返回 "" 作 base_dir ⇒ 根级主文件 quote-include 候选链失配。
test "dir_of POSIX 根级文件返回 /" {
  inspect(dir_of("/x.c"), content="/")
  inspect(dir_of("/main.c"), content="/")
}

///|
/// 存量语义钉住：无分隔符 = "."（collect_files 裸名键约定依赖此值）；
/// 中段取前段；**中段原文透传不归一**（含反斜杠——base_dir 与目录模式
/// VFS 收集键 = target 原文同源，归一即候选键↔VFS 键结构性失配，#378
/// 初版回归实证后回退）。
test "dir_of 无分隔符与常规路径" {
  inspect(dir_of("x.c"), content=".")
  inspect(dir_of("sub/x.c"), content="sub")
  inspect(dir_of("a/b/c.c"), content="a/b")
  inspect(dir_of("a\\b.c"), content="a")
  inspect(dir_of("C:\\data\\x.c"), content="C:\\data")
}

///|
/// PR #380 审阅 P2-1：VFS 键拼装链路——dir_of 修到 "/" 后键若按中段
/// 风格拼 "//hd.h"，则与 resolver 候选键经 normalize_path 折叠出的
/// "/hd.h" 失配（VfsProvider 纯内存精确匹配无回落）⇒ include 恒 E1021。
test "vfs_join 键形态（含根级）" {
  inspect(vfs_join(".", "x.h"), content="x.h")
  inspect(vfs_join("/", "hd.h"), content="/hd.h")
  inspect(vfs_join("sub", "x.h"), content="sub/x.h")
  inspect(vfs_join("D:\\dir", "x.h"), content="D:\\dir/x.h")
}

///|
/// PR #380 审阅 P2-1 行为级锚：base_dir="/" + VFS 键 "/hd.h" 的
/// quote-include 必须可解析（纯内存 VFS、无 fs 依赖，三平台可跑）。
/// 锚打在链路上而非 dir_of 返回值——纯函数断言证明不了键形态两侧一致
/// （typeck_diff 语料路径全含目录段，永远走不到 dir="/"）。
test "根级链路：base_dir=/ + 键 /hd.h 可解析 include" {
  let vfs : Map[String, String] = Map([("/hd.h", "#define V 7\n")])
  let r = @lexer.tokenize_with_vfs(
    "#include \"hd.h\"\nint main(void) { return 7; }\n",
    files=vfs,
    base_dir="/",
  )
  inspect(r.errors.length(), content="0")
}

///|
/// B3 批（2026-11-02，M36 A1）basename 锚：产物名 stem 恒保留扩展名（F11
/// 对拍键约定 = stem 含 .c）——裸名单文件与带目录段必须同果。旧
/// basename_no_ext 点 arm 在「尚未遇分隔符」时截扩展名：目录模式
/// `good.c.ast.json` / 裸名 `good.ast.json` 两形态（native exe 实测），
/// 同函数两种行为、单文件模式违反头注 F11 规格；现与 dump_compile 同形。
/// 四份 wbtest 此前均未锚 basename（M36 报告发现项）。
test "basename_keep_ext 裸名与带目录同果（F11 stem 含 .c）" {
  inspect(basename_keep_ext("good.c"), content="good.c")
  inspect(basename_keep_ext("corpus/good.c"), content="good.c")
  inspect(basename_keep_ext("a/b/good.c"), content="good.c")
  inspect(basename_keep_ext("a\\b\\good.c"), content="good.c")
  inspect(basename_keep_ext("/good.c"), content="good.c")
  // 多点名与无扩展名：只剥目录段，不碰点
  inspect(basename_keep_ext("x/good.min.c"), content="good.min.c")
  inspect(basename_keep_ext("x/Makefile"), content="Makefile")
}

///|
/// PR #450 审阅 P2-3 锚：out==target 门禁的归一比较——同义路径（./ 前缀、尾分隔符、
/// 重复分隔符、.. 折返、反斜杠）必须判等；相对上溯（栈空 ..）保留不吞。旧裸字符串
/// 相等形态下 `dump_ast corpus ./corpus` rc=0 且产物写进语料目录（审阅实测）。
test "norm_path 同义路径归一（out==target 门禁不裸比）" {
  inspect(norm_path("corpus"), content="corpus")
  inspect(norm_path("./corpus"), content="corpus")
  inspect(norm_path("corpus/"), content="corpus")
  inspect(norm_path("corpus//"), content="corpus")
  inspect(norm_path("a/../corpus"), content="corpus")
  inspect(norm_path(".\\corpus\\"), content="corpus")
  inspect(norm_path("sub/corpus"), content="sub/corpus")
  inspect(norm_path("../out"), content="../out")
  inspect(norm_path("../../out"), content="../../out")
  inspect(norm_path("a/../../out"), content="../out")
  // 门禁判据：两侧归一后相等即拒
  assert_true(norm_path("corpus") == norm_path("./corpus/"))
  assert_true(norm_path("corpus") != norm_path("corpus_out"))
}
