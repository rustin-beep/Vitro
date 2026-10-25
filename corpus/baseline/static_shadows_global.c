/*
 * @category: static_local
 * static 局部遮蔽同名文件作用域 global（#283 修复锚，2026-10-24）：
 * 函数级 `static int c` 与文件作用域 `int c` 同名——C11 6.2.1 内层声明
 * 遮蔽外层，函数体内全部 c 引用（读/写/取址/复合赋值/自增/指针初始化器
 * 回填）都应指向 static 槽。旧解析链 local → global → static 垫底：
 * global 抢先命中，c=c+1 读到 global 500 写回 global（clang 8 / vitro 501
 * 静默错值，零诊断）；修复 = static 前置（local → static → global）。
 *
 * 消费点覆盖矩阵（PR #299 审阅 P1/P2，2026-10-25 补锚后——六消费点中
 * 本语料可反证五处，addr 臂可达面极窄由 codegen wbtest 白盒锚锁）：
 *   assign 复合赋值/整体拷贝/整体赋值 ← main 体 c+=5 与 matrix_main 形态 2/3
 *   unary IncDec 前后自增          ← main 体 c++ / ++c
 *   stmt 读值                      ← main 体 printf(c)
 *   index_member 成员读改写        ← matrix_main 形态 1（同名 struct 碰撞）
 *   init 回填聚合地址常量          ← matrix_main 形态 4（struct 聚合 {&c}）
 *   addr 取址                      ← 本语料无判别形态（&x 走 unary Addr 臂
 *                                    /init 回填，指令流差分实证）——由
 *                                    codegen_wbtest 双锚白盒锁序
 *   call 数组/struct 传参          ← 原序已正确（复核），非本批修复面
 * 边界防回退：块内 local 遮蔽 static（#71 病 37）/ 块内 static 遮蔽函数级
 * static（#277）/ 参数与块内 static 同名（#282 零回退）。
 * 两条 master 既有缺陷已避开（审阅顺带实测，另案处置）：文件作用域取
 * 成员地址 &s.x、数组聚合初始化器 {&c} 均 NULL 解引用——本语料形态都在
 * 函数内、聚合用 struct 非数组。
 * clang 真值对拍。
 */
#include <stdio.h>

int c = 500;
int arr_g[2] = {7, 8};
struct P { int x; int y; };
struct P gp = {1, 2};

void take(int *p, char *q) { printf("%d %s\n", p[0], q); }
int matrix_main(void);                   /* 消费点矩阵段（文件尾）前置原型 */

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
    return matrix_main();
}

/* ==== 消费点矩阵补锚段（PR #299 审阅 P1，2026-10-25）====================
 * 原 main 体只反证 assign / unary IncDec / stmt 读值三消费点（审阅指令流
 * 差分实测）；以下 4 形态定向补 addr / index_member / init 回填三消费点
 * 的判别力（突变还原实测：三处还原修复前序时下四形态全部静默错值）。
 * 两条既有洞已避开（形态在函数内非文件作用域；聚合用 struct 非数组）：
 * 文件作用域 &s.x 取成员地址 / 数组聚合 {&c} 属 master 既有 NULL 解引用
 * 缺陷（审阅顺带实测，另案处置），本语料不写会红的形态。 */
struct P sp = {1, 2};                    /* 文件作用域同名 global（碰撞对）*/
struct Q { int *p; };

int matrix_main(void) {
    /* 形态 1（index_member）：同名 static struct 遮蔽 global struct，
     * 成员读改写走 static 槽——突变态 1 3 / clang+PR 10 21 */
    static struct P sp = {10, 20};
    sp.y = sp.y + 1;
    printf("%d %d\n", sp.x, sp.y);       /* 10 21 */

    /* 形态 2（assign 整体拷贝初始化）：clang+PR 10 20 / 突变态 1 2 */
    struct P d = sp;
    /* 形态 3（assign 整体赋值）：clang+PR 10 20 / 突变态 1 2 */
    struct P e;
    e = sp;
    printf("%d %d %d %d\n", d.x, d.y, e.x, e.y);   /* 10 21 10 21 */

    /* 形态 4（init 回填·聚合初始化器地址常量）：&c 取 static 槽——
     * clang+PR 7 / 突变态 500（读到 global） */
    static int c = 7;
    static struct Q q = { &c };
    printf("%d\n", *q.p);                /* 7 */

    /* 形态 4b（addr 消费点）：取址后经指针读——&c 须是 static 槽地址 */
    int *p2 = &c;
    printf("%d\n", *p2);                 /* 7 */
    return 0;
}
