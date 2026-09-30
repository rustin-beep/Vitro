// serve 三段白盒锚（S7 批三号三段）：静态元数据族（capabilities/
// error_catalog/semantic_labels/contracts）+ 交互 IO 族（input.feed 续跑
// / output.delta 四通道游标）+ memory.regions 三段式（C2）。
// 转义口径同 serve_run_wbtest（JSON 结构引号 = \"；C 源码内嵌引号 = \\\"；
// JSON 换行 = \\n）。

///|
test "serve_capabilities_static_tracks" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"capabilities\"}")
  assert_true(resp.contains("\"engine\":\"vitro\""))
  assert_true(resp.contains("\"version\":\"v0.1\""))
  assert_true(resp.contains("\"frozen_at\":\"2026-09-12\""))
  assert_true(resp.contains("\"behavior_contracts\""))
  assert_true(resp.contains("\"semantic_label_kinds\":14"))
  assert_true(
    resp.contains("\"mem_size\":1048576"),
    msg="内存常量单源 @bytecode",
  )
  assert_true(resp.contains("\"global_start\":4096"))
  assert_true(resp.contains("\"languages\""))
  // 分叉登记：abi_version/engine_version 不出（无 capi 层——.mbti 取代）
  assert_false(
    resp.contains("abi_version"),
    msg="分叉①：无 capi 层字段",
  )
  assert_false(resp.contains("cpp"), msg="分叉②：F-2 已裁 C++")
}

///|
test "serve_static_catalogs_parse_channels" {
  let s = @session.Session::new()
  let (r1, _) = serve_handle(s, "{\"id\":1,\"method\":\"error_catalog\"}")
  assert_true(r1.contains("\"ok\":true"))
  assert_true(r1.contains("\"code\""), msg="码表条目字段")
  let (r2, _) = serve_handle(s, "{\"id\":2,\"method\":\"semantic_labels\"}")
  assert_true(r2.contains("\"ok\":true"))
  assert_true(
    r2.contains("\"id\":\"swap\""),
    msg="active c 域词汇在表（落盘探真：compare 非本表词汇——AlgoFrame 呈现色词表概念勿混）",
  )
  let (r3, _) = serve_handle(s, "{\"id\":3,\"method\":\"contracts\"}")
  assert_true(r3.contains("\"ok\":true"))
  assert_true(
    r3.contains("v0.2") || r3.contains("reserved"),
    msg="预留位台账在表",
  )
}

// ── input.feed 族（A2：增量喂入续跑）──

///|
test "serve_input_feed_continues_waiting" {
  // **input.feed 主路径锚**：run → waiting → feed 追加 → finished
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n; scanf(\\\"%d\\\", &n); printf(\\\"got %d\\\", n); return 0; }\\n\"}}",
  )
  let (r1, _) = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  assert_true(r1.contains("\"waiting_input\":true"))
  let (r2, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"input.feed\",\"params\":{\"text\":\"42\\n\"}}",
  )
  assert_true(r2.contains("\"status\":\"finished\""), msg="feed 续跑完成")
  assert_true(stdout_text(s).contains("got 42"))
}

///|
test "serve_input_feed_not_compiled_frame" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"input.feed\",\"params\":{\"text\":\"x\"}}",
  )
  assert_true(resp.contains("\"status\":\"not_compiled\""))
}

///|
test "serve_input_feed_multi_line_appends" {
  // 多行追加（split_stdin 同口径切行）：两次 scanf 一次喂齐
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int a; int b; scanf(\\\"%d\\\", &a); scanf(\\\"%d\\\", &b); printf(\\\"%d+%d\\\", a, b); return 0; }\\n\"}}",
  )
  let (r1, _) = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  assert_true(r1.contains("\"waiting_input\":true"))
  let (r2, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"input.feed\",\"params\":{\"text\":\"3\\n4\\n\"}}",
  )
  assert_true(r2.contains("\"status\":\"finished\""))
  assert_true(stdout_text(s).contains("3+4"), msg="两行各自喂入")
}

// ── output.delta 族（E-P1-5 四通道游标）──

///|
test "serve_output_delta_cursor_semantics" {
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { printf(\\\"hello\\\"); return 0; }\\n\"}}",
  )
  let _ = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  let (r1, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"output.delta\",\"params\":{\"cursor\":0,\"stream\":\"stdout\"}}",
  )
  assert_true(r1.contains("\"delta\":\"hello\""))
  assert_true(r1.contains("\"total\":5"))
  assert_true(r1.contains("\"cursor\":5"))
  let (r2, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"output.delta\",\"params\":{\"cursor\":2,\"stream\":\"stdout\"}}",
  )
  assert_true(r2.contains("\"delta\":\"llo\""), msg="中段增量")
  let (r3, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"output.delta\",\"params\":{\"cursor\":100,\"stream\":\"stdout\"}}",
  )
  assert_true(r3.contains("\"delta\":\"\""), msg="越界按末尾处理")
  assert_true(r3.contains("\"cursor\":5"))
  let (r4, _) = serve_handle(
    s, "{\"id\":5,\"method\":\"output.delta\",\"params\":{\"cursor\":-3,\"stream\":\"stdout\"}}",
  )
  assert_true(r4.contains("\"delta\":\"hello\""), msg="负游标从 0 起")
}

///|
test "serve_output_delta_stream_channels" {
  // stdout/stderr/note 三通道分流 + display 拼接
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { printf(\\\"out\\\"); fprintf(stderr, \\\"err\\\"); return 7; }\\n\"}}",
  )
  let _ = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  let (r1, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"output.delta\",\"params\":{\"cursor\":0,\"stream\":\"stdout\"}}",
  )
  assert_true(r1.contains("\"delta\":\"out\""))
  let (r2, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"output.delta\",\"params\":{\"cursor\":0,\"stream\":\"stderr\"}}",
  )
  assert_true(r2.contains("\"delta\":\"err\""))
  let (r3, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"output.delta\",\"params\":{\"cursor\":0,\"stream\":\"note\"}}",
  )
  // delta 是 Latin-1 折回形态（serve_io 文件头分叉登记——中文 UTF-8 字节
  // 被折成逐字节字符，contains 原文必失配）；断字节口径：完成附注
  // 「程序运行完成，返回值：7\n」UTF-8 = 11×3 + 2 = 35 字节
  assert_true(
    r3.contains("\"total\":35"),
    msg="note 通道字节总数（完成附注 UTF-8 35 字节）",
  )
  assert_false(r3.contains("\"delta\":\"\""), msg="note 增量非空")
  let (r4, _) = serve_handle(s, "{\"id\":5,\"method\":\"output.delta\"}")
  assert_true(r4.contains("\"stream\":\"display\""))
  assert_true(r4.contains("\"delta\":\"out"), msg="display 含 stdout")
  assert_true(r4.contains("err"), msg="display 含 stderr")
}

///|
test "serve_output_delta_unknown_stream_defaults_display" {
  // 未知通道取值退化 display（Rust 同形——旧值客户端行为不变）
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { printf(\\\"x\\\"); return 0; }\\n\"}}",
  )
  let _ = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  let (resp, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"output.delta\",\"params\":{\"stream\":\"bogus\"}}",
  )
  assert_true(resp.contains("\"stream\":\"display\""))
}

// ── memory.regions 族（C2 三段式）──

///|
test "serve_memory_regions_global_entries" {
  // 全局区合成：两全局（int g + char arr[10]）——addr 自 GLOBAL_START、
  // type_display_name 渲染
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"int g;\\nchar arr[10];\\nint main() { return 0; }\\n\"}}",
  )
  let _ = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  let (resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"memory.regions\"}")
  assert_true(resp.contains("\"global\":2"), msg="region_counts.global")
  assert_true(
    resp.contains("\"heap\":2"),
    msg="vfs 预设两块占堆（Rust inject_preset_files 同形）",
  )
  assert_true(resp.contains("\"ty\":\"int\""))
  assert_true(
    resp.contains("\"ty\":\"char[10]\""),
    msg="数组维度渲染（Rust format 无空格同形）",
  )
  assert_true(resp.contains("\"kind\":\"global\""))
  assert_true(resp.contains("\"alloc_by\":\"static\""))
  assert_true(
    resp.contains("\"addr\":5120"),
    msg="首全局 = GLOBAL_START(0x1000) + libc 预留段 1024（codegen 既有锚同源；Rust 同式布局——对拍裁定在批四号)",
  )
}

///|
test "serve_memory_regions_heap_after_malloc" {
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdlib.h>\\nint main() { char* p = (char*)malloc(8); p[0] = 1; return p[0]; }\\n\"}}",
  )
  let _ = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  let (resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"memory.regions\"}")
  assert_true(resp.contains("\"heap\":3"), msg="vfs 预设 2 + malloc 1")
  assert_true(resp.contains("\"kind\":\"heap\""))
  assert_true(resp.contains("\"alloc_by\":\"malloc\""))
  assert_true(resp.contains("\"alloc_counter\""))
  assert_true(resp.contains("\"quarantine\""))
}

///|
test "serve_memory_regions_stack_frames_while_waiting" {
  // 栈区合成锚：waiting 态停在 helper 函数内 → call_stack 非空 →
  // stack 条目（name=函数名、size=帧跨度）
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint helper() { int n; scanf(\\\"%d\\\", &n); return n; }\\nint main() { return helper(); }\\n\"}}",
  )
  let (r1, _) = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  assert_true(r1.contains("\"waiting_input\":true"))
  let (resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"memory.regions\"}")
  assert_true(resp.contains("\"stack\":2"), msg="main+helper 两帧")
  assert_true(resp.contains("\"name\":\"helper\""))
  assert_true(resp.contains("\"kind\":\"stack\""))
  assert_true(resp.contains("\"ty\":\"frame\""))
}

///|
test "type_display_name_rendering_shapes" {
  // type_display_name 单元锚（Rust type_utils.rs 同形）
  assert_eq(@ast.type_display_name(@ast.Type::int()), "int")
  assert_eq(@ast.type_display_name(@ast.Type::unsigned_int()), "unsigned int")
  assert_eq(@ast.type_display_name(@ast.Type::char()), "char")
  assert_eq(@ast.type_display_name(@ast.Type::char().set_const(true)), "const char")
  assert_eq(
    @ast.type_display_name(@ast.Type::int().pointer_to()),
    "int*",
    msg="指针星号",
  )
  assert_eq(
    @ast.type_display_name(@ast.Type::int().pointer_to().pointer_to()),
    "int**",
    msg="二级指针",
  )
  assert_eq(@ast.type_display_name(@ast.Type::long_long()), "long long")
}
