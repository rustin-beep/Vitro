// @category: chibicc_port
// source: chibicc test/initializer.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: 局部数组/二维/空初始化/部分初始化/字符串初始化/定长推断
#include <stdio.h>
int main(void) {
  int x[3]={1,2,3}; printf("%d %d %d\n", x[0], x[1], x[2]);
  int m23[2][3]={{1,2,3},{4,5,6}};
  printf("%d %d %d\n", m23[0][1], m23[1][0], m23[1][2]);
  int ez[3]={}; printf("%d %d %d\n", ez[0], ez[1], ez[2]);    // 空初始化=全零
  int pf[2][3]={{1,2}}; printf("%d %d %d\n", pf[0][1], pf[1][0], pf[1][2]); // 部分初始化
  char c4[4]="abc"; printf("%d %d %d\n", c4[0], c4[2], c4[3]);
  char c24[2][4]={"abc","def"};
  printf("%d %d %d %d\n", c24[0][0], c24[0][3], c24[1][0], c24[1][2]);
  int ia[]={1,2,3,4}; printf("%d %d\n", ia[3], (int)sizeof(ia));
  char ca[]="foo"; printf("%d\n", (int)sizeof(ca));           // 4
  struct { int a; int b; int c; } s={1,2,3}; printf("%d %d %d\n", s.a, s.b, s.c);
  struct { int a; int b; int c; } ps={1}; printf("%d %d %d\n", ps.a, ps.b, ps.c);
  struct { int a; int b; } sa[2]={{1,2},{3,4}};
  printf("%d %d %d %d\n", sa[0].a, sa[0].b, sa[1].a, sa[1].b);
  struct { int a; int b; } psa[2]={{1,2}}; printf("%d\n", psa[1].b);
  struct { int a; int b; } es={}; printf("%d %d\n", es.a, es.b);
  typedef struct { int a,b,c,d,e,f; } T6; T6 f1={1,2,3,4,5,6}; T6 f2; f2=f1; printf("%d\n", f2.e);
  // 注：chibicc 原 struct 连续赋值链 g3=g2=g1（赋值表达式返回 struct 右值再赋）——Vitro codegen E0「不支持的地址生成」拒收（M12 族 gap 候选），移 deferred
  typedef struct { int a,b; } T2b; T2b h1={1,2}; T2b h2=h1; printf("%d\n", h2.a);
  union { int a; char b[4]; } u={0x01020304}; printf("%d %d\n", u.b[0], u.b[1]);
  union { struct { char a,b,c,d; } e; int f; } us={{4,3,2,1}}; printf("%d\n", us.f);  // 0x01020304
  int fl[2][3]={0,1,2,3,4,5}; printf("%d %d\n", fl[0][0], fl[1][0]);  // 二维平铺初始化
  // 注：chibicc 原 struct{int a,b;} x[2]={0,1,2,3}（struct 数组平铺初始化）——Vitro E3006 拒收（gap 候选），移 deferred
  int tl[]={1,2,3,}; printf("%d\n", tl[2]);                    // 尾逗号
  return 0;
}
