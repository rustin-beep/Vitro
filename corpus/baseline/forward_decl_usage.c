// 前向声明与完整定义的合法链（#145 红锚，2026-10-18）：`struct S;` 后向
// 声明 + 后续完整定义是 C 惯用法（互引链表/不透明指针）；修复前前向被
// 当零字段完整定义，后续定义误报 E3002 重复。不完整类型的合法用法 =
// 指针（`struct Opq *`）。
#include <stdio.h>
#include <stdlib.h>
struct Node;
struct Node { int v; struct Node *next; };
struct Opq;
typedef struct Opq *OpqH;
struct Opq { int x; };
int main(void) {
    struct Node a = {1, 0};
    struct Node b = {2, 0};
    a.next = &b;
    struct Opq o = {7};
    OpqH h = &o;
    int sum = 0;
    for (struct Node *p = &a; p != 0; p = p->next) {
        sum += p->v;
    }
    printf("sum=%d opq=%d same=%d\n", sum, h->x, h == &o);
    return 0;
}
