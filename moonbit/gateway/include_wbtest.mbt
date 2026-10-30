// quote-include 宿主形态分叉锚（2026-09-29 审阅 P2 补——此前修复零锚：
// 突变回 vfs 空表缺陷形态时 58/58 全绿 + serve_smoke 全绿，防线全盲）。
// 双分支锁定：注册 reader ⇒ include 真解析（宏链进 trace）；未注册/
// None-reader ⇒ E1021（wasm-gc 形态同路径）。锚内自恢复（注入 None-
// reader 等效未注册——无撤销接口，见 include_reader 注释）。

///|
test "include_reader_registered_parses_local_header" {
  set_include_reader(fn(path : String) -> String? {
    if path.has_suffix("myinc.h") {
      Some("#define VALUE 7\n")
    } else {
      None
    }
  })
  let (resp, _) = serve_handle(
    session, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include \\\"myinc.h\\\"\\nint main(){ return VALUE; }\\n\",\"filename\":\"d:/x/main.c\"}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="注册形态 include 真解析",
  )
  assert_true(
    session.compile.compiled,
    msg="编译成功（宏 VALUE 展开后 return 7）",
  )
  assert_true(
    session.compile.preprocessor_trace.length() > 0,
    msg="宏展开链进 preprocessor_trace",
  )
  // 自恢复：None-reader 等效未注册（后续锚不受全局状态污染）
  set_include_reader(fn(_path : String) -> String? { None })
}

///|
test "include_reader_absent_reports_e1021" {
  // None-reader ⇒ HostIncludeProvider NotFound ⇒ E1021（wasm-gc 形态
  // 未注册走同一 vfs 空表路径——本锚同时锁 wasm 侧行为面；2026-10-05
  // files-vfs 批后本锚语义收窄为「单 source 形态」：files 集合内互引
  // 已可解析，集合外仍 E1021，见 wasm_files_vfs 系锚）
  set_include_reader(fn(_path : String) -> String? { None })
  let (resp, _) = serve_handle(
    session, "{\"id\":2,\"method\":\"compile\",\"params\":{\"source\":\"#include \\\"myinc.h\\\"\\nint main(){ return VALUE; }\\n\",\"filename\":\"d:/x/main.c\"}}",
  )
  assert_true(resp.contains("\"ok\":false"), msg="未注册 ⇒ 编译失败")
  assert_true(resp.contains("E1021"), msg="E1021 not found（wasm 同路径）")
  assert_false(session.compile.compiled)
}

///|
test "wasm_files_vfs_resolves_in_set_quote_include" {
  // wasm 形态 = include_reader 未注册（None）——注意 set_include_reader(
  // None-reader) 落 Some 分支（宿主 provider），对 vfs 分叉不等价，故
  // wbtest 同包直写 include_reader.val（None 即 wasm-gc 出口的真初始态）
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":3,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"value.h\\\"\\nint main(){ return VALUE; }\\n\"}," +
    "{\"filename\":\"value.h\",\"source\":\"#define VALUE 7\\n\"}]}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="files 集合内 quote-include 真解析",
  )
  assert_true(
    session.compile.compiled,
    msg="宏 VALUE 自 value.h 展开后编译通过",
  )
}

///|
test "wasm_files_vfs_outside_set_still_e1021" {
  // 集合外文件仍 E1021（教学诊断保留：wasm 无文件系统，宁诊断不静默——
  // 勘察 H-5 语义不因 files 注入而松动）
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":4,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"nope.h\\\"\\nint main(){ return 0; }\\n\"}]}}",
  )
  assert_true(resp.contains("E1021"), msg="集合外 include 仍 E1021")
  assert_false(session.compile.compiled)
}

///|
test "wasm_files_vfs_header_unit_not_merged" {
  // .h unit 只进 vfs 不进拼接（C 语义对齐：头文件不被"编译"，仅 include
  // 可达）——否则 .h 物理拼接在尾部 + include 点展开 = 双重定义
  //（typedef/全局变量撞重复定义诊断）。锚：typedef 头 + include 展开
  // 编译通过，且 file_ranges 不含 .h 区间
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":6,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"t.h\\\"\\nint main(){ struct P p; p.x = 1; return p.x; }\\n\"}," +
    "{\"filename\":\"t.h\",\"source\":\"typedef struct { int x; } P;\\n\"}]}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="typedef 头不双重定义（修前红：拼接+展开各一次 P）",
  )
  let has_header_range = session.compile.file_ranges
    .iter()
    .any(r => r.filename == "t.h")
  assert_false(has_header_range, msg=".h unit 不产 file_ranges 区间")
}

///|
test "wasm_files_vfs_subdir_base_dir_chain" {
  // 子目录形态：主文件目录段进 base_dir 候选链（与 CLI 形态 dir_of 语义
  // 对齐）——"sub/main.c" 的 `#include "util.h"` 命中 key "sub/util.h"
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":5,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"sub/main.c\",\"source\":\"#include \\\"util.h\\\"\\nint main(){ return U; }\\n\"}," +
    "{\"filename\":\"sub/util.h\",\"source\":\"#define U 5\\n\"}]}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="子目录 base_dir 候选链命中",
  )
  assert_true(session.compile.compiled)
}

///|
test "wasm_files_c_unit_included_not_double_defined_issue364" {
  // #364 红锚（2026-10-29）：main.c quote-include sibling.c 且 sibling.c
  // 同时作为 unit 登记——wasm 臂 collect_walk（include 目标逐个登记为
  // 独立编译单元）与浏览器工作区「全量文件送 files」两形态共有。修前
  // sibling.c 拼接 + main.c 内 include 展开各一份 ⇒ E3003 重复定义；
  // 修后被展开命中的 .c unit 与 .h 同语义（只进 vfs 不进拼接）。
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":9,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"sibling.c\\\"\\nint main(){ return sibling_value(); }\\n\"}," +
    "{\"filename\":\"sibling.c\",\"source\":\"int sibling_value(){ return 7; }\\n\"}]}}",
  )
  assert_false(
    resp.contains("E3003"),
    msg="被 include 的 .c unit 不双重定义（修前红：E3003）",
  )
  assert_true(session.compile.compiled, msg="编译通过（返回 7）")
  let has_sibling_range = session.compile.file_ranges
    .iter()
    .any(r => r.filename == "sibling.c")
  assert_false(
    has_sibling_range,
    msg="被 include 的 .c unit 不产 file_ranges 区间（vfs-only）",
  )
}

///|
test "wasm_files_c_unit_chain_include_not_double_defined_issue364" {
  // #364 链式形态：main.c → sibling.c → grand.c 两级 quote-include——
  // 不动点剔除须传导到传递闭包（grand.c 由 sibling.c 的展开拉入，本身
  // 也不得再拼接）
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":10,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"sibling.c\\\"\\nint main(){ return sibling_value() + grand_value(); }\\n\"}," +
    "{\"filename\":\"sibling.c\",\"source\":\"#include \\\"grand.c\\\"\\nint sibling_value(){ return grand_value() + 1; }\\n\"}," +
    "{\"filename\":\"grand.c\",\"source\":\"int grand_value(){ return 6; }\\n\"}]}}",
  )
  assert_false(
    resp.contains("E3003"),
    msg="链式 include 的 .c unit 全部只展开一次（修前红：E3003）",
  )
  assert_true(
    session.compile.compiled,
    msg="链式编译通过（sibling_value=7+grand_value=6）",
  )
}

///|
test "wasm_files_c_unit_independent_still_merged_issue364" {
  // #364 守卫锚（修前后均须绿）：无互引的独立 .c unit 仍全量拼接——
  // main.c 声明+调用 lib.c 定义的函数，lib.c 若被误剔出拼接即 E3089
  //（已声明未定义）/链接面失败。防不动点过度剔除。审阅 P3-1（PR #372）
  // ：首断言原写 resp.contains("\"ok\":true") 命中的是 RPC 信封（恒
  // true，零判别力）——改锚 E3089 缺席（过度剔除突变 M2 直红）。
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":11,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"int lib_fn(void);\\nint main(){ return lib_fn(); }\\n\"}," +
    "{\"filename\":\"lib.c\",\"source\":\"int lib_fn(){ return 7; }\\n\"}]}}",
  )
  assert_false(
    resp.contains("E3089"),
    msg="独立 .c unit（无互引）不被剔出拼接（防过度剔除）",
  )
  assert_true(session.compile.compiled, msg="守卫形态编译通过")
}

///|
test "wasm_files_block_comment_include_target_still_merged_issue364r2" {
  // 审阅 P2-1（PR #372，2026-10-29）：钉住「不用行级预扫描」的设计理由
  // ——块注释内的 #include 不被词法展开，其目标 unit **不得被剔出拼接**
  // （预扫描实现按行匹配会把 sib.c 误剔 ⇒ 其定义静默丢失 ⇒ E3089）。
  // 断言 compiled 且 file_ranges 仍含 sib.c（未被剔除）。
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":15,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"int sib_value(void);\\n/* #include \\\"sib.c\\\" */\\nint main(){ return sib_value(); }\\n\"}," +
    "{\"filename\":\"sib.c\",\"source\":\"int sib_value(){ return 7; }\\n\"}]}}",
  )
  assert_false(
    resp.contains("E3089"),
    msg="块注释内 include 的目标不被误剔（预扫描突变红：E3089）",
  )
  assert_true(
    session.compile.compiled,
    msg="编译通过（拼接供给定义）",
  )
  let has_sib_range = session.compile.file_ranges
    .iter()
    .any(r => r.filename == "sib.c")
  assert_true(
    has_sib_range,
    msg="sib.c 仍进拼接（file_ranges 含其区间——未被剔除）",
  )
}

///|
test "wasm_files_if0_guarded_include_target_still_merged_issue364r2" {
  // 审阅 P2-1（PR #372，2026-10-29）：同上——#if 0 包住的 #include 同样
  // 不被词法展开（条件栈跳过态），目标 unit 不得被剔出拼接。预扫描按行
  // 匹配两形态都误剔 ⇒ 本锚与块注释锚共同钉死「展开命中集必须出自词法
  // 真实决策」的设计理由。
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":16,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#if 0\\n#include \\\"sib.c\\\"\\n#endif\\nint sib_value(void);\\nint main(){ return sib_value(); }\\n\"}," +
    "{\"filename\":\"sib.c\",\"source\":\"int sib_value(){ return 7; }\\n\"}]}}",
  )
  assert_false(
    resp.contains("E3089"),
    msg="#if 0 内 include 的目标不被误剔（预扫描突变红：E3089）",
  )
  assert_true(
    session.compile.compiled,
    msg="编译通过（拼接供给定义）",
  )
  let has_sib_range = session.compile.file_ranges
    .iter()
    .any(r => r.filename == "sib.c")
  assert_true(
    has_sib_range,
    msg="sib.c 仍进拼接（file_ranges 含其区间——未被剔除）",
  )
}

///|
test "host_reader_files_vheader_resolves_issue202" {
  // #202 红锚（2026-10-21）：宿主形态（reader 已注册——js/native CLI 壳
  // 经 ensure_include_reader 都注册）下 files 数组内的虚拟头文件须可被
  // quote-include 解析。修前 HostIncludeProvider 只查磁盘 ⇒ E1021
  //（空目录对照实验：磁盘无 a.h 即红，files 声明被完全忽略）。
  set_include_reader(fn(_path : String) -> String? { None })
  let (resp, _) = serve_handle(
    session,
    "{\"id\":7,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"a.h\",\"source\":\"#define V 7\\n\"}," +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"a.h\\\"\\nint main(void){ return V; }\\n\"}]}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="files 内虚拟头文件宿主形态可解析（#202：修前 E1021）",
  )
  assert_true(session.compile.compiled)
  // 自恢复：None-reader 等效未注册（后续锚不受全局状态污染）
  set_include_reader(fn(_path : String) -> String? { None })
}

///|
test "host_reader_mem_table_takes_precedence_issue202" {
  // #202 语义锚：files 内存表优先于磁盘 reader——磁盘版 a.h 是 include
  // 炸弹（引用不存在的 bomb.h），files 版 a.h 合法；mem 优先则编译过，
  // 磁盘优先/只查磁盘则 E1021。
  set_include_reader(fn(path : String) -> String? {
    if path.has_suffix("a.h") {
      Some("#include \"bomb.h\"\n")
    } else {
      None
    }
  })
  let (resp, _) = serve_handle(
    session,
    "{\"id\":8,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"a.h\",\"source\":\"#define F 7\\n\"}," +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"a.h\\\"\\nint main(void){ return F; }\\n\"}]}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="files 内存表优先于磁盘 reader（虚拟工程自足语义）",
  )
  set_include_reader(fn(_path : String) -> String? { None })
}

///|
test "posix_absolute_main_include_candidate_key_issue356" {
  // #356 行为锚（2026-10-29）：POSIX 绝对路径主文件的 quote-include 候选
  // 键须保留前导 / ——记录型 reader 直证 resolver 产键。修前键
  // "home/x/hd.h"（剥 /）⇒ Linux 宿主 100% E1021；Windows 盘符形态
  // （首段 "D:" 非空本就保留，绝对性靠盘符侥幸保住）为守卫锚。
  let asked : Array[String] = []
  set_include_reader(fn(path : String) -> String? {
    asked.push(path)
    if path == "/home/x/hd.h" || path == "D:/x/hd.h" {
      Some("#define V 7\n")
    } else {
      None
    }
  })
  let (resp, _) = serve_handle(
    session, "{\"id\":12,\"method\":\"compile\",\"params\":{\"source\":\"#include \\\"hd.h\\\"\\nint main(){ return V; }\\n\",\"filename\":\"/home/x/main.c\"}}",
  )
  assert_false(
    resp.contains("E1021"),
    msg="绝对路径主文件 include 可解析（修前红：E1021）",
  )
  assert_true(session.compile.compiled, msg="宏 V 展开后编译通过")
  assert_true(
    asked.contains("/home/x/hd.h"),
    msg="候选键保留前导 /（修前被剥：home/x/hd.h）",
  )
  // 守卫：Windows 盘符绝对路径同链路（既有行为不回归）
  let asked2 : Array[String] = []
  set_include_reader(fn(path : String) -> String? {
    asked2.push(path)
    if path == "D:/x/hd.h" {
      Some("#define W 9\n")
    } else {
      None
    }
  })
  let (resp2, _) = serve_handle(
    session, "{\"id\":13,\"method\":\"compile\",\"params\":{\"source\":\"#include \\\"hd.h\\\"\\nint main(){ return W; }\\n\",\"filename\":\"D:/x/main.c\"}}",
  )
  assert_false(
    resp2.contains("E1021"),
    msg="盘符绝对路径 include 可解析（守卫）",
  )
  assert_true(session.compile.compiled, msg="守卫形态编译通过")
  assert_true(
    asked2.contains("D:/x/hd.h"),
    msg="盘符候选键形态不变（守卫）",
  )
  // 自恢复：None-reader 等效未注册（后续锚不受全局状态污染）
  set_include_reader(fn(_path : String) -> String? { None })
}

///|
test "root_level_absolute_main_include_issue356r2" {
  // 审阅 P2-1（2026-10-29）：根级绝对主文件 "/main.c" 的 base_dir 须取
  // "/"——修前 gateway dir_of 对唯一分隔符在 0 位的路径返回 "." ⇒ 候选
  // 键按 cwd 相对解析（"hd.h"）⇒ Linux 真 fs 下 E1021。记录型 reader
  // 直证候选键 "/hd.h"。既有 include 锚的 filename 全带目录段，根级
  // 形态此前零覆盖。
  let asked : Array[String] = []
  set_include_reader(fn(path : String) -> String? {
    asked.push(path)
    if path == "/hd.h" {
      Some("#define R 4\n")
    } else {
      None
    }
  })
  let (resp, _) = serve_handle(
    session, "{\"id\":14,\"method\":\"compile\",\"params\":{\"source\":\"#include \\\"hd.h\\\"\\nint main(){ return R; }\\n\",\"filename\":\"/main.c\"}}",
  )
  assert_false(
    resp.contains("E1021"),
    msg="根级绝对主文件 include 可解析（修前红：E1021）",
  )
  assert_true(session.compile.compiled, msg="宏 R 展开后编译通过")
  assert_true(
    asked.contains("/hd.h"),
    msg="根级候选键为绝对形态（修前：hd.h 相对 cwd）",
  )
  // 自恢复：None-reader 等效未注册（后续锚不受全局状态污染）
  set_include_reader(fn(_path : String) -> String? { None })
}

///|
test "issue376_included_file_diag_attributed" {
  // #376（2026-10-30）：被 include 展开文件内的错误必须归属自身文件 +
  // 文件内正行号——此前 resolve_location 查 merge_units 拼接坐标 ranges，
  // 而错误 loc.line 是词法仿古坐标（展开段为负行号），两坐标系永不相交
  // ⇒ 回落 ("main.c", 负行号) 直出。修后走 LineMap.spans（词法真坐标，
  // 探针实证展开段主坐标区间即负区间 [-2..-1]）+ file_id → 主名/included
  // 键映射。锚断言 sib.c 首行语法错归属 ("sib.c", 1)——修前红：
  // filename=="main.c" 且 line==-1。
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":15,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"sib.c\\\"\\nint main(void){ return 0; }\\n\"}," +
    "{\"filename\":\"sib.c\",\"source\":\"int f( {\\nint g(void){ return 1; }\\n\"}]}}",
  )
  assert_false(session.compile.compiled, msg="语法错在场编译必败")
  let hit = session.compile.diagnostics
    .iter()
    .any(fn(d) { d.filename == "sib.c" && d.line == 1 && d.error_code != 0 })
  assert_true(
    hit,
    msg="sib.c 首行语法错归属 (sib.c, 1)——修前 (main.c, -1)",
  )
}
