// @category: baseline
// DIFF-LIB-PRINTF-01 锚（2026-10-05 批二-b；同日审阅 P2-a 扩回避面）：
// + / 空格 / # 旗标 + %.Ns 精度 + %c 单字节 + 零填充符号前置（%+05d→+0003、
// %05d 负→-0003、%05.1f→-03.5）+ 浮点臂旗标（%+f/% f/%+g——旧浮点臂
// 未传 signed_pos）；%*d 动态宽度（typeck 编译拒）归批三
#include <stdio.h>
char hs[] = "hello";
int main() {
    printf("[%+d][% d][%5d][%-5d][%05d]\n", 42, 42, 42, 42, -42);
    printf("[%#x][%#X][%#o]\n", 255, 255, 8);
    printf("[%.1s][%.3s][%6.2s][%-6.2s]\n", hs, hs, hs, hs);
    printf("[%d][%+d][% d]\n", -7, -7, -7);
    printf("[%+05d][%05d][%05.1f][%+f][% f][%+g]\n", 3, -3, -3.5, 3.5, 3.5, 3.5);
    return 0;
}
