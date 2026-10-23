/*
 * @category: static_local
 * 同名 static 局部变量的作用域独立性（#277 修复锚，2026-10-23）：C11 6.2.1
 * 内层块同名 static 是独立对象；不同函数同名 static 亦各自独立。旧
 * emit_static_var 按裸名 contains 早退——内层声明复用外层槽：初始化被
 * 跳过 + 读写错指（探针 p10：内层 `static int a[2]={1,1}` 读到外层 {9,9}）；
 * 跨函数同名残留键同款复用他函数槽。修复 = 删早退（每声明必分配新槽）+
 * static 两表接入 ScopeFrame 遮蔽/恢复链（退出作用域恢复外层映射）。
 * clang 真值对拍。
 */
#include <stdio.h>

int counter(void) { static int c = 0; c++; return c; }
int other(void)  { static int c = 100; c += 2; return c; }

int main(void) {
    static int a = 9;
    {
        static int a = 1;                 /* 内层独立对象 */
        a += 10;
        printf("%d\n", a);                /* 11 */
    }
    printf("%d\n", a);                    /* 9：外层不受内层污染 */
    int c1 = counter();                   /* 求值顺序无关化：拆语句序列 */
    int c2 = counter();
    int c3 = counter();
    printf("%d %d %d\n", c1, c2, c3);     /* 1 2 3 */
    printf("%d\n", other());              /* 102：跨函数同名独立 */
    for (int i = 0; i < 3; i++) {
        static int once = 5;              /* 循环体 static：只初始化一次 */
        once += 1;
        printf("%d", once);               /* 678 */
    }
    printf("\n");
    return 0;
}
