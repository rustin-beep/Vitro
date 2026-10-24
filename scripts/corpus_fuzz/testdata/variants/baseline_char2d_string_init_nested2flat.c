// @category: baseline
// #137 缺陷 1 修复锚（2026-10-17，C11 §6.7.9p14）：二维 char 数组
// 字符串字面量初始化——显式维与推断维（char t[][8]）两形态；每行
// 逐字节拷入 + '\0' + 零填充。四模型 8/8 命中形态。
#include <stdio.h>
int main(void) {
    char t[2][8] = { "xy", "zw" };
    printf("[%s][%s]\n", t[0], t[1]);
    char u[][4] = { "ab", "cd" };
    printf("[%s][%s] %d\n", u[0], u[1], (int)sizeof(u));
    return 0;
}
