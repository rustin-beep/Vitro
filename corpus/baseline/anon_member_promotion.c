/*
 * @category: anon_member
 * 匿名 union/struct 成员提升（#266/#249 修复锚，2026-10-22）：C11
 * §6.7.2.1p13 无声明器成员的内部成员提升为外层成员（s.a 直访 +
 * 初始化器定位）。旧三面：单匿名初始化 E3006「期望 union 实际 int」/
 * designated 查名 E3042/静默丢值、双匿名成员表空名互撞 E3080。
 * 全局 struct designated（.x=1）是 #270 域不在此列。clang 真值对拍。
 */
#include <stdio.h>

struct AnonUnion {
  union { int a; float b; };
};

/* 双匿名（#249 形态：旧空名互撞 E3080）+ 命名成员混排 */
struct Mixed {
  int tag;
  union { int u1; long long u2; };
  union { char c1; float c2; };
};

int main(void) {
    /* 局部 designated 指名提升成员（旧 E3042 + codegen 静默丢值） */
    struct AnonUnion x = { .a = 3 };
    /* 位置初始化透传匿名 union（旧 E3006 误拒） */
    struct AnonUnion y = { 7 };
    /* 双匿名：两个提升成员 + 命名成员各就各位 */
    struct Mixed m = { 1 };
    m.u1 = 40;
    m.c1 = 'k';
    printf("x=%d y=%d tag=%d u1=%d c1=%c\n", x.a, y.a, m.tag, m.u1, m.c1);
    printf("float-view=%d\n", x.b != 0.0f ? 1 : 0);
    return x.a + y.a; /* 10 */
}
