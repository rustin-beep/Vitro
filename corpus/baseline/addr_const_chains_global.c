/* addr_const_chains_global.c —— #304：文件作用域地址常量链形态
 *
 * Member/Index 链 + 末端静态符号的地址常量（&s.x / &sa[1].x / &go.in.b
 * / &garr[1]）在三条回填路径（顶层标量臂 / 数组逐元素臂 / 聚合递归
 * flatten 臂）上的运行期取值。旧缺陷：三臂只认裸名/纯取址两形态，链
 * 形态静默置 0 ⇒ 运行期 E3083 NULL 解引用（clang 全部正常给值）。
 */
#include <stdio.h>

struct Inner { int a; int b; };
struct Outer { struct Inner in; int tail; };
struct Inner gi = {10, 20};
struct Outer go = { {30, 40}, 50 };
struct Inner gia[3] = { {1,2}, {3,4}, {5,6} };
int garr[3] = {100, 200, 300};

/* 顶层标量臂：单成员 / 括号 / 嵌套成员 / 数组元素成员 / 纯数组元素 */
int *p1 = &gi.a;
int *p2 = &(gi.b);
int *p3 = &go.in.b;
int *p4 = &gia[1].b;
int *p5 = &garr[1];
int *p6 = &go.tail;

/* 数组逐元素臂：聚合元素为链形态 */
int *agg[3] = { &gi.a, &gia[2].a, &garr[2] };

/* 聚合递归 flatten 臂：struct 初始化器内链形态 */
struct PtrBox { int *p; };
struct PtrBox box = { &go.in.a };

int main(void) {
    printf("%d %d %d %d %d %d\n", *p1, *p2, *p3, *p4, *p5, *p6);
    printf("%d %d %d\n", *agg[0], *agg[1], *agg[2]);
    printf("%d\n", *box.p);
    return 0;
}
