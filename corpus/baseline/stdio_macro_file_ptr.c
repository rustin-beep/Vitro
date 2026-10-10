/* 病 15 残余收尾（#61，2026-10-10）：stdin/stdout/stderr 宏从 Number 单
 * token 改为显式 cast 体 ((FILE *)n)——FILE* 赋值/传参/比较/用户函数形参
 * 全语境一次干净（旧形态 `FILE *f = stdout` 走 int→指针赋值吃 E3054）。
 * `#if stdout` 语境改后非法（真 C 对 FILE* 宏同判不支持，登记接受）。 */
#include <stdio.h>

void emit(FILE* f) { fprintf(f, "via-fn"); }

int main() {
    FILE* f = stdout;
    fputc('x', stdout);
    fputs("-s", stdout);
    emit(stdout);
    if (f == stdout) printf("|eq");
    // fseek(stdout) 返回值是环境依赖形态（UCRT 管道 -1 / 文件重定向 0
    /// Go exec 的临时文件中转 = seekable → clang_direct 恒 0），judge 环境
    // 决定真值不可对拍——值不输出（仅由 vfs_wbtest 锁 -1 语义）；fclose 同
    // 理（真 C 关流后 printf 丢失且 UCRT fail-fast vs 伪句柄常驻）放尾。
    fseek(stdout, 0, 0);
    printf("|fin");
    int c = fclose(stdout);
    return c;
}
