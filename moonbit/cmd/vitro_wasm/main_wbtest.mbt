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

///|
/// #377 锚（2026-10-30）：vfs 登记键 = 父键目录 + include 原文的规范化
/// 拼写（resolver 候选链 cur_dir 臂同式）。旧逻辑（登记 include 原文）
/// 下跨目录同名 include 共键 ⇒ seen 误吞（clang clean vs E3023 实锤）；
/// 键/查找对齐后各文件独立键。修前实现（strip_dot_segments(inc)）跑本
/// 锚必红——J9 双向验。
test "issue377_vfs_key_follows_resolver_candidate" {
  // 主文件（键 basename，目录 "."）的首层 include：键 = 规范化原文
  inspect(vfs_key_for("main.c", "sub/a.h"), content="sub/a.h")
  inspect(vfs_key_for("main.c", "./sub/a.h"), content="sub/a.h")
  // 嵌套：sub/a.h 内 include "b.h" ⇒ 键 sub/b.h（旧逻辑登记 "b.h"——红）
  inspect(vfs_key_for("sub/a.h", "b.h"), content="sub/b.h")
  // 跨目录同名：other/c.h 内同名 include 各得独立键（旧逻辑同撞 "b.h"）
  inspect(vfs_key_for("other/c.h", "b.h"), content="other/b.h")
  // ".." 回退与 "//" 折叠（resolver normalize_path 同语义）
  inspect(vfs_key_for("sub/a.h", "../top.h"), content="top.h")
  inspect(vfs_key_for("sub/a.h", "deep//d.h"), content="sub/deep/d.h")
}
