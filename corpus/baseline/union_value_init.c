/*
 * @category: baseline
 * union 值作初始化元素 + rvalue 成员访问（#515 审阅 P1/P2 连坐，2026-11-15）：
 * ① 字段位 union 值 `S s = {1, a}`；② 数组元素 union 值 `U arr[2] = {a, b}`；
 * ③ rvalue 成员 `mk2(7).i`。缺陷版（聚合判定漏 TK_Union）：① ② 落标量兜底
 * 只拷 4 字节静默错值（w=0 / a0=0——emit_field_init 与 emit_local_array_init
 * 分流条件两层）；③ 「复杂结构体表达式暂不支持」编译错（gen_member_addr
 * 只判 TK_Struct）。clang 真值对拍。
 */
#include <stdio.h>

typedef union { int i; double d; } U;
typedef struct { int t; U w; } S;

U mk(double x) { U u; u.d = x; return u; }
U mk2(int x) { U u; u.i = x; return u; }

int main(void) {
    U a; a.d = 1.5;
    U b; b.d = 2.5;
    S s = { 1, a };                        /* ① 字段位 union 值 */
    printf("t=%d w=%g\n", s.t, s.w.d);     /* 1 1.5 */
    U arr[2] = { a, b };                   /* ② 数组元素 union 值 */
    printf("a0=%g a1=%g\n", arr[0].d, arr[1].d);  /* 1.5 2.5 */
    printf("rv=%d\n", mk2(7).i);           /* ③ rvalue 成员 —— 7 */
    printf("ret=%g\n", mk(2.5).d);         /* 返回调用成员取 double —— 2.5 */
    return 0;
}
