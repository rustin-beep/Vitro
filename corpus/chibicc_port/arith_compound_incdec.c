// @category: chibicc_port
// source: chibicc test/arith.c（MIT, © 2019 Rui Ueyama）— ASSERT 形态 port；statement expression 拆变量
// topic: 复合赋值全族 + 前/后缀自增自减表达式值
#include <stdio.h>
int main(void) {
  int i = 2; i += 5; printf("%d\n", i);
  i = 5; i -= 2; printf("%d\n", i);
  i = 3; i *= 2; printf("%d\n", i);
  i = 6; i /= 2; printf("%d\n", i);
  i = 2; printf("%d\n", ++i);
  int a[3]; a[0]=0; a[1]=1; a[2]=2; int *p=a+1;
  { int t = ++*p; printf("%d %d\n", t, a[1]); }        // 拆 tmp 定序（同 printf 副作用+读 UB——WSL 副判实锤）
  a[0]=0; a[1]=1; a[2]=2; p = a+1;
  { int t = *p++; printf("%d %d\n", t, *p); }
  a[0]=0; a[1]=1; a[2]=2; p = a+1;
  { int t = *p--; printf("%d %d\n", t, *p); }
  i = 2; { int t = i++; printf("%d %d\n", t, i); }
  i = 2; { int t = i--; printf("%d %d\n", t, i); }
  a[0]=0; a[1]=1; a[2]=2; p=a+1;
  (*p++)--; printf("%d %d %d\n", a[0], a[1], a[2]);
  a[0]=0; a[1]=1; a[2]=2; p=a+1;
  (*p)--; p++; printf("%d %d\n", a[1], *p);
  i = 10; i %= 4; printf("%d\n", i);
  long li = 10; li %= 4; printf("%lld\n", li);
  i = 6; i &= 3; printf("%d\n", i);
  i = 6; i |= 3; printf("%d\n", i);
  i = 15; i ^= 5; printf("%d\n", i);
  i = 1; i <<= 3; printf("%d\n", i);
  i = 5; i >>= 1; printf("%d\n", i);
  i = -1; i >>= 1; printf("%d\n", i);
  return 0;
}
