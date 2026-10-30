// #378 锚：dir_of 族语义同义性（gateway/dump 系对齐——#378 起六处：本处
// + gateway + dump×4；根级/无分隔符语义一致，中段原文透传按族分叉）。
// 本包 supported_targets = "+js"——验证口径
// `moon test --target js -p vitro_wasm`。

///|
/// POSIX 根级与中段原文透传语义（根级/无分隔符与 gateway/dump 系同义钉住）。
test "dir_of 根级与原文透传" {
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
