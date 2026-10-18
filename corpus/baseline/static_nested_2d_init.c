/*
 * @category: static_init
 * 函数内 static 多维数组嵌套大括号初始化（#171 修复锚，2026-10-18）：
 * 旧 emit_static_scalar_array_init 的 4 字节臂 flatten([elem])[0] 只取
 * 子初始化器首元素、8 字节臂 literal_init_bits(InitList) 恒 None——
 * {{1,2,3},{4,5,6}} 只写 1,4,0,0,0,0，double 全 0。修 = 表达式级
 * 扁平化两臂共用定位。文件作用域/一维/char 对照组同收。
 */
#include <stdio.h>

int g[2][3] = {{1, 2, 3}, {4, 5, 6}}; /* 文件作用域对照（既有正确形态） */

int main(void) {
    static int m[2][3] = {{1, 2, 3}, {4, 5, 6}};
    static double d[2][2] = {{1.5, 2.5}, {3.5, 4.5}};
    static char c[2][4] = {{'a', 'b', 'c', 0}, {'x', 'y', 'z', 0}};
    static int flat[5] = {9, 8, 7, 6, 5}; /* 一维对照 */

    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 3; j++) printf("%d,", m[i][j]);
    printf("\n");
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++) printf("%.1f,", d[i][j]);
    printf("\n");
    for (int i = 0; i < 2; i++) printf("%s ", c[i]);
    printf("\n");
    for (int j = 0; j < 3; j++) printf("%d,", g[0][j]);
    printf("\n");
    for (int j = 0; j < 5; j++) printf("%d,", flat[j]);
    printf("\n");
    return 0;
}
