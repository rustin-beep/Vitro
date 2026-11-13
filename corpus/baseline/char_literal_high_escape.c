// @category: baseline
// #510 红锚：字符常量高位转义符号化——C11 §6.4.4.4 字符常量值 = 执行字符
// 集成员经 char 转换后的 int；vitro char = signed char（x86 clang 基准）。
// 修前 vitro 零扩展（'\377'→255、'\200'→128、'\xff'→255），与自家 char
// 变量路径（char_signedness.c 锚）内部不一致；clang 22 实测 -1/-128/-1。
// 边界对照：'\x7f'=127 与 'A'=65 不符号化；'\0'=0 不动。
#include <stdio.h>
int main() {
    printf("lit377=%d\n", '\377');
    printf("lit200=%d\n", '\200');
    printf("litxff=%d\n", '\xff');
    printf("edge=%d %d %d\n", '\x7f', 'A', '\0');
    return 0;
}
