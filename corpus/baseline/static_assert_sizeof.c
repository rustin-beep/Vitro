// @category: baseline
// #13 销案形态语料（2026-10-06）：static_assert 条件的 sizeof 聚合/数组
// 折叠（含顶层断言组合形态——trailing_globals 吞函数声明器坑）+ 失败
// 断言反锚（两侧同报）
#include <stdio.h>
struct P { int a; int b; };
union U { int a; double d; };
int g[6];
_Static_assert(sizeof(struct P) == 8, "s");
_Static_assert(sizeof(union U) == 8, "u");
_Static_assert(sizeof(g) == 24, "g");
_Static_assert(sizeof(int) == 4, "i");
int main() {
    int arr[4];
    _Static_assert(sizeof(arr) == 16, "a");
    printf("all asserts pass\n");
    return 0;
}
