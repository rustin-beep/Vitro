/* abort_probe——SIGABRT 崩溃路径防线的 C 桩（#391 审阅 P1-2/P2-1，2026-10-31）。
 *
 * 背景：issue #357 现象 A 的「重定向下崩溃诊断可见」此前零锚——smoke 附 8
 * 只断言死形态（rc=134），与「缓冲有没有刷出去」正交；且 Linux 面附 8 无
 * handler 与有 handler 同为 134，零区分度。本桩不需任何 panic 语料：
 * #include 真源 stdout_stub.c（cmd/run 真源——三副本逐字节同，single_source
 * 锁）→ main 首行 ensure_binary_mode()（挂 handler + Windows 切二进制）→
 * printf 两行进 CRT 缓冲（模拟 panic 诊断已在缓冲）→ raise(SIGABRT)。
 *
 * 断言（vitro_cli_smoke B 组附 9，node 侧）：
 *   ① 刷出实效：重定向文件含全部 printf 字节（handler 没挂上/没 flush
 *      即丢字节红——附 8 的零区分度由此补齐）；
 *   ② rc 不落 CLI_PROTOCOL_V1 §2 协议五值 {0,1,2,3,4}——UCRT 下 raise 形态
 *      曾走 _exit(3) 撞 step-limit 码（#391 审阅 P1-1 实锤）；abort() 形态
 *      Windows 保 0xC0000409 crash（node status 负值）/ POSIX 134。
 *
 * 编译：clang -o <tmp>/abort_probe abort_probe.c（单翻译单元含真源，
 * 无链接依赖）；clang 缺失的跑环境明示 skip（gofmt 先例——工具缺失不静默）。
 */
#include <stdio.h>
#include <signal.h>
#include "../../../moonbit/cmd/run/stdout_stub.c"

int main(void) {
  moonbit_vitro_ensure_binary_mode();
  printf("probe-line-1-in-buffer\n");
  printf("probe-line-2-in-buffer\n");
  raise(SIGABRT);
  return 0;
}
