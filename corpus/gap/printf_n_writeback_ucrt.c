// @category: arch_diff_bug
// 平台方言锚（#437 修复后入库批，gap 桶）：速查表 P1 行——%n 写回已输出字节数（C11
// 7.21.6.1p8）。Win UCRT 出厂配置禁 %n：整程运行崩 rc=127（__stdio_common_vfprintf
// 参数校验直接 fail-fast）——Win clang 直拍取不到正常真值；真值采 WSL gcc（glibc 全派
// 一致：abcd / n=2）。Vitro（B4 批 #427 修复写回 + 实参消耗）对齐 gcc 真值。known_direct
// 登记（digest 锁 Win clang 侧崩溃形态输出）。来源：tmp/review_v2_M20 A-1 / V1#32。
#include <stdio.h>
int main(void) {
    int n = -1;
    printf("ab%ncd\n", &n);
    printf("n=%d\n", n);   // gcc: abcd / n=2；Win UCRT: 运行崩 rc=127
    return 0;
}
