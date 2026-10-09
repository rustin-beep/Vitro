// @category: baseline
// issue #55 靶料：C11 §6.4p3 white-space 全集含 \v(0x0B) / \f(0x0C)——
// 词法器曾随 Rust is_ascii_whitespace 集合漏掉 \v，拒绝合法 C（E1001）。
// 控制字节只落在 token 间空白位（行首/行中/表达式内），stdout 为可见内容。
#include <stdio.h>
int main() {
int x= 1;
printf("%d\n", x);
int y= x+ 2;
printf("%d\n", y);
return 0;
}
