// @category: baseline
// 绿锚（#437 修复后入库批）：速查表 Z12/Z13/Z14 行——静态初始化器折叠的提升/符号面：
// ((uchar)255<<24)<0 应 1（uchar 提升为 signed int，移位结果为负）、(~0u)<0 应 0（~0u 保持
// unsigned）、(-(uchar)1)<0 应 1（Neg 结果为 signed int）。#426 B3' 批 2（Shl/BitNot/Neg 定型
// integer_promote）修复后翻面入桶。来源：tmp/review_v2_M08/probes p07 / V1#11。
#include <stdio.h>
int t1 = ((unsigned char)255 << 24) < 0;
int t2 = (~0u) < 0;
int t3 = (-(unsigned char)1) < 0;
int main(void) {
    printf("t1=%d t2=%d t3=%d\n", t1, t2, t3);   // clang: t1=1 t2=0 t3=1
    return 0;
}
