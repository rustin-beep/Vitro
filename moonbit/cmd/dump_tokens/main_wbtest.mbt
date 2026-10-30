// #378 锚：目录段函数根级 POSIX 与归一语义（gateway 系 dir_of 对齐）。
// dump 包 native-only——裸 moon test 静默跳过本文件，
// 验证口径 `MOON_CC=clang moon test --target native -p dump_tokens`。

///|
/// #378：唯一分隔符在 0 位 = POSIX 根级文件（"/x.c"），目录段须返回
/// "/"——旧实现返回 "" 作 base_dir ⇒ 根级主文件 quote-include 候选链失配。
test "dir_of POSIX 根级文件返回 /" {
  inspect(dir_of("/x.c"), content="/")
  inspect(dir_of("/main.c"), content="/")
}

///|
/// 存量语义钉住：无分隔符 = "."（collect_files 裸名键约定依赖此值）；
/// 中段分隔符取前段；反斜杠归一为 "/"（候选键 normalize_path 同口径）。
test "dir_of 无分隔符与常规路径" {
  inspect(dir_of("x.c"), content=".")
  inspect(dir_of("sub/x.c"), content="sub")
  inspect(dir_of("a/b/c.c"), content="a/b")
  inspect(dir_of("a\\b.c"), content="a")
  inspect(dir_of("C:\\data\\x.c"), content="C:\\data")
}
