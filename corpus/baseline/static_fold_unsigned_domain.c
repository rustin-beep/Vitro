// @category: baseline
// 绿锚（#437 修复后入库批）：速查表 Z8/Z9/Z10 行——静态初始化器常量折叠无符号域：-1LL/2u 折
// 0（u32 全值域可被 i64 容纳 → 公共类型 signed long long）、(uchar)200/-1 折 -200（uchar 提升
// signed int）、(-1==4294967295u) 折 1（-1 转 unsigned 比较）。运行期三式皆对——静态/运行期
// 分叉曾是 #426 B3' 共享算术核的靶心，修复后静态=运行期。来源：tmp/review_v2_M08/probes
// p01-02 / V1#6/#7；与 const_fold_unsigned.c（P1-2 批比较/cast 符号域）互补：本文件锁除法域。
#include <stdio.h>
long long g1 = -1LL / 2u;
int g2 = (unsigned char)200 / -1;
int g3 = (-1 == 4294967295u);
int main(void) {
    printf("g1=%lld g2=%d g3=%d\n", g1, g2, g3);   // clang: g1=0 g2=-200 g3=1
    printf("r1=%lld r2=%d r3=%d\n", -1LL / 2u, (unsigned char)200 / -1, -1 == 4294967295u);  // 运行期对照
    return 0;
}
