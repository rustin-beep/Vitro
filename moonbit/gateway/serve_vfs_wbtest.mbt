// #95 VFS 预置文件列举口·vfs.list 方法帧白盒锚：
//   - 预置可见性（test.txt / numbers.txt——issue 核心诉求「只能靠一个个名字试」收口）
//   - 时机语义（预置随 run 注入：run 前 files 空、run 后两件在列）
//   - 动态文件进列 + 每 run 重建语义（reset_vfs 后自建文件消失、预置复位）
// 字符串转义口径同 serve_run_wbtest 头注：JSON 结构引号 = `\"`；
// C 源码内嵌引号 = `\\\"`；`\\n` = C 源码换行。

///|
test "serve_vfs_list_preseed_visible_after_run" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { printf(\\\"hi\\\"); return 0; }\\n\"}}",
  )
  let (run_resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  assert_true(run_resp.contains("\"status\":\"finished\""))
  let (resp, _) = serve_handle(s, "{\"id\":3,\"method\":\"vfs.list\"}")
  assert_true(resp.contains("\"ok\":true"), msg="vfs.list 帧成功")
  assert_true(
    resp.contains("\"name\":\"test.txt\""),
    msg="预置 test.txt 在列",
  )
  assert_true(
    resp.contains("\"name\":\"numbers.txt\""),
    msg="预置 numbers.txt 在列",
  )
  assert_true(resp.contains("\"size\":12"), msg="hello\\nworld\\n = 12")
  assert_true(resp.contains("\"size\":10"), msg="1 2 3 4 5\\n = 10")
}

///|
test "serve_vfs_list_empty_before_run_and_rebuild_semantics" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { FILE* f = fopen(\\\"my.txt\\\", \\\"w\\\"); fputs(\\\"abc\\\", f); fclose(f); return 0; }\\n\"}}",
  )
  // run 前：预置随 run 注入（serve_execute_run 语义），此刻 files 空
  let (pre, _) = serve_handle(s, "{\"id\":2,\"method\":\"vfs.list\"}")
  assert_true(pre.contains("\"ok\":true"))
  assert_true(
    pre.contains("\"files\":[]"),
    msg="run 前无预置（注入随 run）",
  )
  let (_, _) = serve_handle(s, "{\"id\":3,\"method\":\"run\"}")
  let (post, _) = serve_handle(s, "{\"id\":4,\"method\":\"vfs.list\"}")
  assert_true(
    post.contains("\"name\":\"my.txt\""),
    msg="程序自建文件进列",
  )
  assert_true(post.contains("\"size\":3"), msg="fputs abc = 3 字节")
  // 换不建文件的程序再 run：VFS 重建（reset_vfs + 预置重注入）——
  // 自建文件消失、预置复位。同程序重跑无法区分「重建+重执行」与
  // 「累加」，故必须换程序观测重建语义
  let (_, _) = serve_handle(
    s, "{\"id\":5,\"method\":\"compile\",\"params\":{\"source\":\"int main() { return 0; }\\n\"}}",
  )
  let (_, _) = serve_handle(s, "{\"id\":6,\"method\":\"run\"}")
  let (rebuilt, _) = serve_handle(s, "{\"id\":7,\"method\":\"vfs.list\"}")
  assert_false(
    rebuilt.contains("my.txt"),
    msg="每 run 重建：自建文件不跨 run 存活",
  )
  assert_true(
    rebuilt.contains("\"name\":\"test.txt\""),
    msg="预置复位（每 run 重注入）",
  )
  assert_true(
    rebuilt.contains("\"name\":\"numbers.txt\""),
    msg="预置复位（两件全在）",
  )
}
