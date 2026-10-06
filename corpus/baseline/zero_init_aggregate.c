// @category: baseline
// #19 销案形态语料（2026-10-06）：{0} 清零初始化（C11 §6.7.9 花括号
// 省略——常量 0 可初始化任意聚合成员）+ union 变量初始化三面（parse
// classify 前瞻 / typeck 字段表 / codegen 局部与全局 flatten）
#include <stdio.h>
struct Inner { int a; char b; };
struct S2 { struct Inner in2; int arr[3]; };
struct S2 g2 = {0};
struct S2 gflat = {0};
union U2 { int x; char c[4]; };
union U2 gu = {0};
union U2 g5 = {5};
int main() {
    struct S2 loc = {0};
    loc.arr[2] = 5;
    union U2 lu = {0};
    printf("%d %d %d %d %d\n", g2.in2.a, gu.x, g5.x, loc.arr[2], lu.x);
    return gflat.arr[0];
}
