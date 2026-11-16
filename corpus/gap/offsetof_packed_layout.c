#include <stdio.h>
#include <stddef.h>

// @category: arch_diff_bug——offsetof 宏本身工作（编译期常量、嵌套 struct 成员
// 均可取），但布局值随 Vitro struct 紧排口径（无对齐 padding）分叉：clang
// offsetof(A,i)=4/sizeof(B)=24 vs Vitro 1/16（char+int 紧排无 3 字节 pad）。
// 已知限制表 6（DIFF-LAYOUT-PACKED-01）既有登记面的 offsetof 载体。
// clang 真值（x64）：0 4 8 / 0 16 / 24。

struct A { char c; int i; double d; };
struct B { struct A a; char tail[3]; };

int main() {
    printf("%d %d %d\n", (int)offsetof(struct A, c), (int)offsetof(struct A, i), (int)offsetof(struct A, d));
    printf("%d %d\n", (int)offsetof(struct B, a), (int)offsetof(struct B, tail));
    printf("%d\n", (int)sizeof(struct B));
    return 0;
}
