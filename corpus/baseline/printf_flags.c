// @category: baseline
// DIFF-LIB-PRINTF-01 锚（2026-10-05 批二-b）：+ / 空格 / # 旗标 + %.Ns 精度
//（旧只实现 -/0、%.1s 忽略精度系 oracle 照搬）+ %c 高位字节单字节直出
//（旧 char 通道两字节化）；%*d 动态宽度（typeck 编译拒）归批三
#include <stdio.h>
char hs[] = "hello";
int main() {
    printf("[%+d][% d][%5d][%-5d][%05d]\n", 42, 42, 42, 42, 42);
    printf("[%#x][%#X][%#o]\n", 255, 255, 8);
    printf("[%.1s][%.3s][%6.2s][%-6.2s]\n", hs, hs, hs, hs);
    printf("[%d][%+d][% d]\n", -7, -7, -7);
    return 0;
}
