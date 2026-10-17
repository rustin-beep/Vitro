// @category: baseline
// #134 缺陷 1 灰区锚（2026-10-17）：enum 参数函数赋给 int 参数函数指针
// ——clang 视 enum 与 int 兼容（零警告 ACCEPT），升 error 后的 exact
// 判等（type_eq enum↔int 宽化）不得误拒。三模型独立命中的 fn_t 形态
// 的对照面。
#include <stdio.h>
enum E { EA = 10 };
int f(enum E e) { return (int)e + 1; }
typedef int (*fn_t)(int);
int main(void) {
    fn_t p = f;
    printf("%d\n", p(1));
    return 0;
}
