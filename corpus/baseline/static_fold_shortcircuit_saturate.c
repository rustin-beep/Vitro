// @category: baseline
// 绿锚（#437 修复后入库批）：速查表 Z7/Z11 行——静态初始化器折叠两形态：短路（int d1 = 1 || 1/0;
// 右侧 1/0 不求值，值 1——修前折 0）与浮点饱和（int f1 = (int)1e300; 折 2147483647 四端一致
// ——修前折 -1）。#426 B3' 批 1（折叠器短路两阶段帧 CE_LogiRhs/LogiFin + f2i_saturate_i32）
// 修复后翻面入桶。来源：tmp/review_v2_M08/probes p03/p05 / V1#8/#10。
#include <stdio.h>
int d1 = 1 || 1/0;
int f1 = (int)1e300;
int main(void) {
    printf("d1=%d f1=%d\n", d1, f1);   // clang: d1=1 f1=2147483647（四端一致口径）
    return 0;
}
