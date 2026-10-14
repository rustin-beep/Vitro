/* #79（2026-10-13 报 / 2026-10-14 修）：print_int 保留名劫持——typeck
 * visit_call 对 print_int 无条件走内置签名（print_int(int)）检查，用户
 * 重定义被静默无视：正确调用自有 print_int(int\*)（取址实参）被 E3029
 * 误拒、传参类型不匹配（int 给 int\* 形参）被零诊断误收（clang/gcc 均
 * error: incompatible integer to pointer conversion）。修复对齐 qsort
 * 先例：funcs 命中用户定义优先 check_user_func——本文件锁正确形态
 * （run 输出 user fn: 7，用户函数被真正调用——codegen 侧无劫持，
 * print_int 不在 libc 预注册表，用户定义走 CallFunc 路由）。误收形态
 * 另见 print_int_user_redefine_bad.c（双侧编译失败等价）。 */
#include <stdio.h>
void print_int(int *p) { printf("user fn: %d\n", *p); }
int main(void) {
    int v = 7;
    print_int(&v);
    return 0;
}
