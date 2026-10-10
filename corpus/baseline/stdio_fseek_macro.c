/* 病 15 批 A/B（#61）：FILE* 位三态的宏名形态——Clang 侧 stdout 是真 FILE*
 * 宏（编译过），Vitro 侧预处理展开为字面量 1 放行（宁纵勿枉——裸 1 形态
 * Clang error/Vitro 放行的分裂面不进语料，由 typeck wbtest 锚锁定）。
 * 运行层锚 fflush(stdout) 返 0 + fclose(stdout) 返 0（rc 携带——关流后
 * printf 不再可用，输出序不可倒置）；fseek/ftell 对标准流返 -1 面：本机
 * MSVC CRT 对管道流 seek 崩溃（Linux 正常——本机/CI 分裂面），由
 * vfs_wbtest stdio_handle_dispatch_batch_b 锁定，不入语料。 */
#include <stdio.h>

int main() {
    printf("f=%d\n", fflush(stdout));
    int c = fclose(stdout);
    return c;
}
