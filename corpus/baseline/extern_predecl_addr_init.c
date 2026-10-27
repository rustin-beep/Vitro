// @category: static_addr_const
// #331（2026-10-27）负锚：地址常量初始化器的**合法**形态全家族——前向
// 引用守卫（fwd_ref_static_init.c 锚）不得误拒本面：
//   ① extern 先行声明 + 定义在后（codegen pending 回填活通道，突变实证
//      见 #331 销案评论——短路 pending 即 NULL 解引用 TRAP）；
//   ② 后向引用（声明在前的 &g / 数组名互引用，#264 主形态回归保护）；
//   ③ 函数内 static 聚合的链形态 &s.f（base 是 static local，Pass 4 语境
//      不进守卫；emit_static_var 先登记后初始化当场 Resolved）。
#include <stdio.h>
extern int e;
int *p = &e;              /* ① */
int e = 7;
int g = 5;
static const int TABLE[2] = {10, 20};
const int *tp = TABLE;    /* ② 后向数组名 */
int *gp = &g;             /* ② 后向 &g */
struct S { int f; };
int take(void) {
    static struct S s = {42};
    static int *sp = &s.f; /* ③ 函数内 static 链 */
    return *sp;
}
int main(void) {
    printf("%d %d %d %d %d\n", *p, *tp, *gp, TABLE[0], take());
    return 0;
}
