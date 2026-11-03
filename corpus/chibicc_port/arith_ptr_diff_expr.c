// @category: chibicc_port
// source: chibicc test/arith.c（MIT, © 2019 Rui Ueyama）— ASSERT 形态 port；statement expression 拆变量
// topic: 指针差值/指针比较/指针±整数表达值（值面，非 sizeof 面）
// UB 域披露（审阅 P3-3）：p+20/p-20 为越界指针算术（C11 §6.5.6p8 只定义同数组内与
// 末尾一位）——clang -O2 直接折叠为常量（movl $20），golden 锁的是 UB 折叠值而非
// 定义语义；三方（Win clang/WSL gcc+clang/Vitro）当前同值，UB 域不追值、不作为行为依据
#include <stdio.h>
int main(void) {
  int x; int *p = &x;
  printf("%d\n", (int)(p+20-p));
  printf("%d\n", p+20-p > 0);
  printf("%d\n", (int)(p-20-p));
  printf("%d\n", p-20-p < 0);
  return 0;
}
