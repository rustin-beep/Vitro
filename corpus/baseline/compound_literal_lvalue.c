/*
 * @category: compound_literal
 * 复合字面量的左值语义（#267 修复锚，2026-10-22）：C99 6.5.2.5p3
 * 复合字面量是可修改左值（unnamed object）——直接赋值 / 解引用数组
 * 字面量赋值（p5 明文示例）/ 取地址后成员赋值三形态。旧 typeck 四
 * 形态左值判定缺 CompoundLiteral 臂报 E3043、codegen gen_assign 缺
 * 臂报「赋值目标不支持」。数组字面量作初始化值（值语义消费）是另
 * 一缺陷面（#272 登记）。clang 真值对拍。
 */
#include <stdio.h>

int main(void) {
    (int){3} = 5;                          /* 标量字面量直接赋值 */
    *(int[]){1, 2} = 7;                    /* p5 明文示例形态 */
    struct P { int x, y; };
    struct P *pp = &(struct P){ .x = 1, .y = 2 };
    pp->x = 30;                            /* 取地址后成员赋值 */
    printf("%d %d\n", pp->x, pp->y);
    struct P *qq = &(struct P){ 5, 6 };
    qq->y += 40;                           /* 复合赋值 */
    printf("%d %d\n", qq->x, qq->y);
    return pp->x;                          /* 30 */
}
