/* printf_star_member.c —— #159 审阅 P2-2：printf 星号参数槽 × struct 成员
 *
 * 真实 C 源形态的「星号宽度/精度位吃 struct 成员」组合（wbtest 锚
 * printf_star_member_typed 是手写 AST，不走 parser 真实路径——本锚
 * 互补）。旧缺陷：check_printf_format 只对值参数槽 resolve 回写，星号
 * 槽实参子树 ty 停在 parse 默认 Void ⇒ get_member_offset(Void) 落
 * _ => 0 ⇒ 字段偏移段静默不发（%.*s 的精度位读成首字段）。
 */
#include <stdio.h>

struct Point { int x; int y; int tag[4]; };
struct Point pt = { 3, 20, { 5, 6, 7, 8 } };
struct W { int w; };
struct W ww = { 6 };

int main(void) {
    /* 星号精度（%.*s）吃 struct 成员——#159 主形态 */
    printf("[%.*s]\n", ww.w, "abcdefgh");
    /* 星号宽度（%*d）吃 struct 成员——同族宽度位 */
    printf("[%*d]\n", pt.y, 42);
    /* 星号宽度 + 嵌套数组元素成员（链形态进星号槽） */
    printf("[%*d]\n", pt.tag[1], 7);
    return 0;
}
