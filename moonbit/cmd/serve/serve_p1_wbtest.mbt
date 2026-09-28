// P1 审阅批锚（2026-09-28 用户审阅报告）：serve 输入通道的 getchar 行间
// 换行——oracle split_stdin 是 split_inclusive('\n')（行含尾换行），
// 切行剥掉换行导致 getchar 每行少产一个 \n（C 组 oracle n=6 / 本侧 n=4
// 实锤）。修复 = split_stdin_lines 改保留尾换行；host 侧补位守卫
// （行尾≠\n 才补）天然兼容含换行形态，零改动。

///|
test "serve_run_getchar_counts_newlines_inclusive" {
  // C 组：input "ab\ncd\n" → oracle n=6（a b \n c d \n）
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main(){ int c; int n=0; while((c=getchar())!=EOF)n++; printf(\\\"n=%d\\\",n); return 0; }\\n\"}}",
  )
  let (r1, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"run\",\"params\":{\"input\":\"ab\\ncd\\n\",\"batch_input\":true}}",
  )
  assert_true(r1.contains("\"status\":\"finished\""))
  assert_eq(
    stdout_text(s),
    "n=6",
    msg="行间换行必须计入（oracle split_inclusive 同形——审阅 P1 C 组）",
  )
}

///|
test "serve_run_getchar_counts_last_line_without_newline" {
  // D' 组：input "ab\ncd"（无尾换行）→ oracle n=5（a b \n c d——末行
  // 无 \n 就没有，尾换行信息不得丢失）
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main(){ int c; int n=0; while((c=getchar())!=EOF)n++; printf(\\\"n=%d\\\",n); return 0; }\\n\"}}",
  )
  let (r1, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"run\",\"params\":{\"input\":\"ab\\ncd\",\"batch_input\":true}}",
  )
  assert_true(r1.contains("\"status\":\"finished\""))
  assert_eq(
    stdout_text(s),
    "n=5",
    msg="末行无换行不得虚增（尾换行信息保留——审阅 P1 D 组引申）",
  )
}

///|
test "serve_run_scanf_then_getchar_reads_newline" {
  // B 组：scanf %s 消费 "hi" 后 getchar 读到行间 \n（oracle 10——
  // 原形态下读到下一行首字符 121/c 的分叉形态）
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main(){ char buf[8]; scanf(\\\"%s\\\", buf); int c = getchar(); printf(\\\"%d\\\", c); return 0; }\\n\"}}",
  )
  let (r1, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"run\",\"params\":{\"input\":\"hi\\nxy\",\"batch_input\":true}}",
  )
  assert_true(r1.contains("\"status\":\"finished\""))
  assert_eq(
    stdout_text(s),
    "10",
    msg="%s 停在行间换行，getchar 须读到 10（oracle 同——审阅 P1 B 组）",
  )
}
