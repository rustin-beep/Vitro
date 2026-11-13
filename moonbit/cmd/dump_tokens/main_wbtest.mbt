// #378/#380 锚：目录段函数 + VFS 键拼装的根级 POSIX 全链路。
// dump 包 native-only——裸 moon test 静默跳过本文件，
// 验证口径 `MOONBIT_NEW_NATIVE=0 MOON_CC=clang moon test --target native -p dump_tokens`（Windows——
// test 面是 debug 档——direct-object 新后端忽略裸 clang 回落 MSVC，且裸名
// clang-cl 会被静默解析成发现的 cl.exe（moon#2480 零警告假绿）——故总闸
// MOONBIT_NEW_NATIVE=0 回 legacy 后端让 clang 生效（陷阱 43 勘正 2026-11-12；
// Linux/CI 用裸 clang）。

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
/// B3 批（2026-11-02，M36 A1 对照面）basename 锚：dump_tokens 产物名
/// `<name>.l1.tsv` stem **去扩展名**——两段式 basename_no_ext（先剥目录段
/// 再剥最后一个点之后），裸名与带目录段同果，是本工具既定契约（与
/// ast/typeck/compile 三家「stem 含 .c」F11 口径有意不同，正名面不含此处）。
test "basename_no_ext 两段式：裸名与带目录同果（去扩展名）" {
  inspect(basename_no_ext("good.c"), content="good")
  inspect(basename_no_ext("corpus/good.c"), content="good")
  inspect(basename_no_ext("a\\b\\good.c"), content="good")
  // 多点名只剥最后一段；无扩展名原样；点在 0 位（隐藏文件形态）不剥
  inspect(basename_no_ext("x/good.min.c"), content="good.min")
  inspect(basename_no_ext("x/Makefile"), content="Makefile")
  inspect(basename_no_ext("x/.hidden"), content=".hidden")
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

///|
/// #445 C1 红→绿锚（2026-11-12）：不可读输入 → Err(原因行)——main 侧
/// println + c_exit(4)。修前形态：主循环裸调 \@fs.read_file_to_string，
/// 不存在路径走未捕获 IOError 的 PanicError 栈 + rc=127（native exe 实测，
/// #230 治理在 dump 族读文件面落空）；进程级 rc=4 断言由 exe 实测面承担
/// （wbtest 同进程——c_exit 杀测试进程，不直接跑 main）。
test "i445_c1_read_input_or_reason_不可读与可读两态" {
  match read_input_or_reason("tmp_i445_definitely_missing_zz9q.c") {
    Ok(_) => fail("不可读输入必须 Err（#445 C1）")
    Err(reason) =>
      inspect(reason.has_prefix("输入不可读："), content="true")
  }
  // Ok 态不在此锚（native 测试 cwd 非包目录——moon.pkg 相对路径实测 Err，
  // 无从构造免清理的可读探针；fs pub 面无 remove）；回归面由 exe 实测真实
  // 语料全覆盖（Ok 路径是主路径，任何回归即 dump 产物全空）。
}

///|
/// #445 B2 锚（2026-11-12）：处理序 = 码元字典序（sort_files_lex）。内置
/// String 序是长度优先 + 等长码元序（util 包探针实测 cmp("e2_x.c","e10_y.c")
/// = -1 而字典序应 +1——e2_x.c 被排到 e10_y.c 前面），语料文件名域两序
/// 必然分叉；本批 ast/typeck/tokens 三家自内置 files.sort() 迁入（compile
/// 既有），四壳处理序统一为字典序（与 codegen_diff 的 Go sort.Strings 字节
/// 字典序对齐——ASCII 域等价；非 ASCII 键域码元序 vs 字节序仍可能分叉，
/// 语料域全 ASCII）。
test "i445_b2_sort_files_lex_字典序含非_ascii" {
  let files : Array[String] = [
    "e10_y.c", "中文.c", "e2_x.c", "ab.c", "a.c", "aa.c",
  ]
  sort_files_lex(files)
  inspect(files.length(), content="6")
  inspect(files[0], content="a.c")
  inspect(files[1], content="aa.c")
  inspect(files[2], content="ab.c")
  inspect(files[3], content="e10_y.c")
  inspect(files[4], content="e2_x.c")
  inspect(files[5], content="中文.c")
}
