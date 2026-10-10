/* 病 15 批 B/C（#61，2026-10-10）：标准流宏句柄全链接线——fputc('x', stdout)
 * 修复前 read_fd 把宏值 1 折叠成 fd=0 静默丢输出；fprintf(stderr) 修复前
 * CLI 层无 stderr 通道整段丢失（vm_diff/clang_direct 口径 = stderr 不进
 * stdout 对拍 digest，两侧对称）。 */
#include <stdio.h>

int main() {
    int a = fputc('x', stdout);
    int b = fputs("s-out\n", stdout);
    printf(" a=%d b=%d\n", a, b);
    fprintf(stderr, "to-stderr\n");
    int c = fputc('y', stderr);
    fprintf(stderr, " c=%d\n", c);
    return 0;
}
