/*
 * @category: static_local
 * static 局部遮蔽同名文件作用域 global（#283 修复锚，2026-10-24）：函数级
 * `static int c` 与文件作用域 `int c` 同名——C11 6.2.1 内层声明遮蔽外层，
 * 函数体内全部 c 引用（读/写/取址/复合赋值/自增/指针初始化器回填）都应
 * 指向 static 槽。旧解析链 local → global → static 垫底：global 抢先
 * 命中，c=c+1 读到 global 500 写回 global（clang 8 / vitro 501 静默
 * 错值，零诊断）；修复 = static 前置（local → static → global，codegen
 * 六消费点同改：addr/assign/call/index_member/unary IncDec/init 回填）。
 * 边界防回退：块内 local 遮蔽 static（#71 病 37 面）/ 块内 static 遮蔽
 * 函数级 static（#277 面）/ 参数与块内 static 同名（#282 面零回退）。
 * clang 真值对拍。
 */
#include <stdio.h>

int c = 500;
int arr_g[2] = {7, 8};
struct P { int x; int y; };
struct P gp = {1, 2};

void take(int *p, char *q) { printf("%d %s\n", p[0], q); }

void param_form(int n) {
    {
        static int n = 5;                /* 参数形：块内 static 遮蔽参数 */
        n++;
        printf("%d\n", n);               /* 6 */
    }
    printf("%d\n", n);                   /* 100：参数不受块内污染 */
}

int main(void) {
    static int c = 7;
    static int a[2] = {40, 41};
    static char msg[6] = "hi";
    static struct P p = {10, 20};
    static int *pc = &c;                 /* &c 取 static 槽（非 global 500）*/
    c += 5;                              /* 复合赋值走 static */
    c++;                                 /* 后自增 */
    ++c;                                 /* 前自增 */
    printf("%d %d %d %d\n", c, *pc, &c != 0, a[1]);  /* 14 14 1 41 */
    p.y = p.y + 1;                       /* struct 成员读改写走 static */
    printf("%d %d %d\n", p.x, p.y, gp.y);            /* 10 21 2 */
    take(arr_g, msg);                    /* 数组传参：global/static 各一 */
    {
        int c = 3;                       /* 块内 local 遮蔽 static（病 37 面）*/
        printf("%d\n", c);               /* 3 */
    }
    printf("%d\n", c);                   /* 14：块外 static 不受块内污染 */
    {
        static int c = 100;              /* 块内 static 遮蔽函数级（#277 面）*/
        c += 1;
        printf("%d\n", c);               /* 101 */
    }
    printf("%d\n", c);                   /* 14 */
    param_form(100);                     /* 6 100 */
    return 0;
}
