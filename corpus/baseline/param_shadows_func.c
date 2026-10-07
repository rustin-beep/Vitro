// @category: baseline
// #21 销案形态语料（2026-10-07 审阅 P2-3 补——形参名==函数名的变量遮蔽，
// codegen Identifier 臂序修复的差分锚定）：roman_numerals 教科书形态
#include <stdio.h>
int symbol(char symbol) {
    int v = 0;
    switch (symbol) {
    case 'I': v = 1; break;
    case 'V': v = 5; break;
    case 'X': v = 10; break;
    }
    return v;
}
int f(int f) { return f * 2; }
int main() {
    printf("%d %d\n", symbol('V'), f(21));
    return 0;
}
