// #378 锚：dir_of 族语义同义性（gateway/dump 系对齐——#378 起七处同义）。
// 本包 supported_targets = "+js"——验证口径
// `moon test --target js -p vitro_wasm`。

///|
/// POSIX 根级与归一语义（与 gateway/dump 系 dir_of 同义钉住）。
test "dir_of 根级与归一" {
  inspect(dir_of("/x.c"), content="/")
  inspect(dir_of("a\\b.c"), content="a")
  inspect(dir_of("C:\\data\\x.c"), content="C:\\data")
}

///|
/// 存量语义钉住：无分隔符 = "."；中段取前段。
test "dir_of 无分隔符与常规路径" {
  inspect(dir_of("x.c"), content=".")
  inspect(dir_of("sub/x.c"), content="sub")
  inspect(dir_of("a/b/c.c"), content="a/b")
}
