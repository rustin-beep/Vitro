// @category: baseline
// #7 销案形态语料（2026-10-06 审阅 P2-2 补——三层穿透的差分覆盖）：
// 匿名 union 内联 body + 成员直接访问（typeck find_anonymous_member +
// codegen anon_field_offset 双层在 typeck_diff/codegen_diff 面锚定）
#include <stdio.h>
struct S {
    int pre;
    union { int a; float b; };
    int post;
};
int main() {
    struct S s;
    s.pre = 10; s.a = 20; s.post = 30;
    union { int x; long long y; } v;
    v.y = 5;
    struct T { struct { int in1; int in2; }; int tail; } t;
    t.in2 = 7; t.tail = 8;
    printf("%d %d %d %d\n", s.pre + s.a + s.post, (int)v.y, t.in2, t.tail);
    return 0;
}
