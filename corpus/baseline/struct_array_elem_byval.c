/*
 * @category: struct_pass
 * struct 按值传参的 Index/Member 实参形态（#162 修复锚，2026-10-18）：
 * 旧 gen_index/gen_member_expr 对 struct 结果照发 4 字节 LoadMem 留下
 * 首字段值，gen_call_ptr struct 实参兜底臂把它当地址逐字拷贝 →
 * `asum(arr2[0])` TRAP NULL 0x1。修复 = struct/union 结果不 load 留地址
 * （对齐 struct 返回透传契约）。clang 真值对拍。
 */
#include <stdio.h>

struct A {
    int arr[3];
    int n;
};

struct Outer {
    struct A inner;
    int tag;
};

int asum(struct A a) { return a.arr[0] + a.arr[1] + a.arr[2] + a.n; }

int osum(struct Outer o) { return asum(o.inner) + o.tag; }

int main(void) {
    /* struct 数组元素按值实参（issue 原形态：TRAP 面） */
    struct A arr2[2] = { { { 1, 2, 3 }, 4 }, { { 5, 6, 7 }, 8 } };
    int r1 = asum(arr2[0]);
    printf("r1=%d\n", r1);
    int r2 = asum(arr2[1]);
    printf("r2=%d\n", r2);

    /* struct 变量实参（对照，旧已好） */
    struct A one = { { 9, 8, 7 }, 6 };
    int r3 = asum(one);
    printf("r3=%d\n", r3);

    /* 嵌套 struct 成员按值实参（gen_member_expr 同病形态） */
    struct Outer o = { { { 1, 1, 1 }, 2 }, 3 };
    int r4 = asum(o.inner);
    printf("r4=%d\n", r4);

    /* 嵌套 struct 整体按值实参（双层通道） */
    int r5 = osum(o);
    printf("r5=%d\n", r5);

    /* struct 数组元素传嵌套函数（Index→Member 链） */
    struct Outer os[2] = { { { { 2, 2, 2 }, 2 }, 2 }, { { { 3, 3, 3 }, 3 }, 3 } };
    int r6 = osum(os[0]);
    printf("r6=%d\n", r6);
    int r7 = asum(os[1].inner);
    printf("r7=%d\n", r7);
    return 0;
}
