// @category: baseline
// #134 缺陷 2 合法形态锚（2026-10-17）：. 与 -> 双运算符正确使用——
// AST Member 节点带 is_arrow 位后 typeck 双向一致性检查（-> 要求指针、
// . 要求 struct/union）不得误伤合法形态。
#include <stdio.h>
struct R { int id; };
int main(void) {
    struct R r; r.id = 7;
    struct R *p = &r;
    printf("%d %d\n", p->id, r.id);
    return 0;
}
