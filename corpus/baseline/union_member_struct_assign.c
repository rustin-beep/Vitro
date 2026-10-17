// @category: baseline
// #136 缺陷 2 修复锚（2026-10-17）：struct 内 union 成员的按值整体
// 赋值——assign 分发改判扩 TK_Union（旧只判 TK_Struct，union 成员
// 落标量路径半拷丢数据，读回 0.000000 实锤）。
#include <stdio.h>
typedef union { long long ll; double d; char bytes[8]; } U;
struct Box { U data; int id; };
int main(void) {
    U arr[2]; struct Box c;
    arr[0].d = 1.5; arr[1].d = 3.0;
    printf("direct: %f %f\n", arr[0].d, arr[1].d);
    c.data = arr[0]; c.id = 0;
    printf("via_struct_assign: %f\n", c.data.d);
    struct Box b2; b2.data.d = 4.5;
    printf("direct_field_write: %f\n", b2.data.d);
    return 0;
}
