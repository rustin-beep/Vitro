// @category: baseline
// #136 缺陷 3 修复锚（2026-10-17）：libc 函数名作函数指针值（非调用
// 位置）——host_rerouted 六函数（strcmp 等）经 HOST_FUNC_PTR_BASE
// 编码段 + VM CallPtr 转发 execute_host_func；bytecode 段纯函数
//（strlen）走 func_index 预注册索引。qsort 回调形态同批验证。
#include <stdio.h>
#include <string.h>
int main(void) {
    int (*f)(const char *, const char *) = strcmp;
    printf("%d\n", f("abc", "abd"));
    return 0;
}
