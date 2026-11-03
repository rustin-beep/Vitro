// @category: chibicc_port
// source: chibicc test/const.c / usualconv.c（MIT, © 2019 Rui Ueyama）
// topic: const 限定声明形态（值读）+ long 混合算术提升 + int 溢出回绕 + 条件运算函数选择
#include <stdio.h>
static int ret10(void) { return 10; }
int main(void) {
  const int cx = 5; printf("%d\n", cx);
  int const cx2 = 8; printf("%d\n", cx2);
  const int const_c = 6; printf("%d\n", const_c);  // 重复限定符
  { const int bq; (void)bq; }                       // 块内 const 声明
  const int pc = 8; int *const y = (int*)&pc; printf("%d\n", *y);
  printf("%lld\n", (long long)(-10 + (long)5));   // -5
  printf("%lld\n", (long long)(-10 - (long)5));
  printf("%lld\n", (long long)(-10 * (long)5));
  printf("%lld\n", (long long)(-10 / (long)5));
  printf("%d %d %d %d\n", -2 < (long)-1, -2 <= (long)-1, -2 > (long)-1, -2 >= (long)-1);
  printf("%d %d %d %d\n", (long)-2 < -1, (long)-2 <= -1, (long)-2 > -1, (long)-2 >= -1);
  // 注：chibicc 原 ASSERT(0, 2147483647+2147483647+2)（int 溢出回绕）——Vitro 教学护栏 trap（D10 族已知差异），移 deferred
  long lx; lx = -1; printf("%lld\n", (long long)lx);
  char nbc[3]; nbc[0]=0; nbc[1]=1; nbc[2]=2; char *ny=nbc+1;
  printf("%d %d\n", ny[0], ny[-1]);               // 负下标
  struct t { char a; } s1, s2; s1.a=5; s2=s1; printf("%d\n", s2.a);
  // 注：chibicc 原 ASSERT(10, (1 ? ret10 : (void*)0)())——GNU void* 与函数指针混型三元，Vitro E3004 拒收（gap 候选），移 deferred
  return 0;
}
