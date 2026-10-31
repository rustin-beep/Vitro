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

///|
/// #390 审阅 P2（2026-10-31）：#377 真缺陷（collect_walk 同名吞文件）的
/// 自动化 E2E 锚——read 注入内存表，对 collect_walk 本体断言登记键集。
/// 旧逻辑（登记 include 原文）下跑本锚必红：场景② keys 缺 "other/b.h"
/// 且 "b.h" 内容被 sub 侧抢占。三场景 = CHANGELOG 一次性手工 E2E 的
/// 可回归替身。
fn mem_read(files : Map[String, String]) -> (String) -> String? {
  // 复刻 OS 路径解析（join_dir 不折 `..`，真 fs 由 OS 回退）：查表前
  // normalize_rel 归一——与 vfs_key_for 同源，语义对齐
  fn(path : String) -> String? { files.get(normalize_rel(path)) }
}

///|
fn keys_of(entries : Array[(String, String)]) -> Array[String] {
  let ks : Array[String] = []
  for kv in entries {
    ks.push(kv.0)
  }
  ks
}

///|
test "issue377_collect_walk_registry_e2e" {
  // 场景①嵌套（#377 issue 原形态）：main.c → sub/a.h → b.h
  let fs1 : Map[String, String] = Map::from_array([
    ("main.c", "#include \"sub/a.h\"\nint main(void){ return B; }\n"),
    ("sub/a.h", "#include \"b.h\"\n"),
    ("sub/b.h", "#define B 7\n"),
  ])
  let e1 : Array[(String, String)] = []
  let s1 : Array[String] = []
  collect_walk("main.c", "main.c", fs1["main.c"], e1, s1, read=mem_read(fs1))
  inspect(keys_of(e1), content="[main.c, sub/a.h, sub/b.h]")
  // 场景②跨目录同名（#377 真缺陷形态）：seen 以原文为键时 other/b.h
  // 被 sub/b.h 抢注吞掉（clang clean vs E3023 实锤）
  let fs2 : Map[String, String] = Map::from_array([
    (
      "main.c", "#include \"sub/a.h\"\n#include \"other/c.h\"\nint main(void){ return sb_val + ob_val; }\n",
    ),
    ("sub/a.h", "#include \"b.h\"\n"),
    ("sub/b.h", "int sb_val = 1;\n"),
    ("other/c.h", "#include \"b.h\"\n"),
    ("other/b.h", "int ob_val = 2;\n"),
  ])
  let e2 : Array[(String, String)] = []
  let s2 : Array[String] = []
  collect_walk("main.c", "main.c", fs2["main.c"], e2, s2, read=mem_read(fs2))
  inspect(
    keys_of(e2),
    content="[main.c, sub/a.h, sub/b.h, other/c.h, other/b.h]",
  )
  // 场景③嵌套 ".." 回退：sub/a.h include "../top.h" → 根级键
  let fs3 : Map[String, String] = Map::from_array([
    ("main.c", "#include \"sub/a.h\"\nint main(void){ return T; }\n"),
    ("sub/a.h", "#include \"../top.h\"\n"),
    ("top.h", "#define T 1\n"),
  ])
  let e3 : Array[(String, String)] = []
  let s3 : Array[String] = []
  collect_walk("main.c", "main.c", fs3["main.c"], e3, s3, read=mem_read(fs3))
  inspect(keys_of(e3), content="[main.c, sub/a.h, top.h]")
}
