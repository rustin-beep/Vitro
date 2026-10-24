/* issue #285（2026-10-24 报/修）：声明符螺旋 const 层级——`T *const *`
 * 的 const 归属第一层指针自身位（C 右左法则：pointer to const-pointer
 * to T）。旧前缀链组装（源码序 wrap，链头=末位 `*`）与 interpret
 * 「自顶向下」（链头先变形 base、深层后 wrap 成外层）方向相反 ⇒ 纯多
 * 前缀形态层级贡献者互换：const 落最外层（`T** const`），精确匹配的
 * 传参/赋值被误报 W3053（clang -Wall -Wextra 全零诊断）。本例修复后
 * 全部精确匹配格零警告；对照格 `char *const[]` decay 给 `char**`
 * （真剥元素层 const）维持 W3053（警告不进 stdout/exit 对拍面）。 */
#include <stdio.h>
static char *const A2[] = { "x", "y" };
static const char *const TAB[] = { "a", "b" };
void take_pp(char **p) { printf("pp %s\n", p[0]); }
void take_cpcp(char *const *p) { printf("cpcp %s\n", p[0]); }
void take_ccpcp(const char *const *p) { printf("ccpcp %s\n", p[0]); }
int main(void) {
    take_cpcp(A2);   /* char* const[] → char* const*：精确匹配 */
    take_ccpcp(TAB); /* const char* const[] → const char* const*：精确匹配 */
    const char *const *q = TAB; /* 同形态显式赋值（base 带 const） */
    printf("q %s\n", q[1]);
    char *const *r = A2; /* 同形态显式赋值（base 裸） */
    printf("r %s\n", r[1]);
    take_pp(A2);     /* 真剥元素层 const：W3053 对照格（clang -Wall 同报） */
    return 0;
}
