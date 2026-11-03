// @category: chibicc_port
// source: chibicc test/struct.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: struct 成员读写/嵌套 struct/指针成员访问/struct 赋值/同名 tag 作用域/自引用链
#include <stdio.h>
int main(void) {
  struct { int a; int b; } x; x.a=1; x.b=2;
  printf("%d %d\n", x.a, x.b);
  struct { char a; int b; char c; } m; m.a=1; m.b=2; m.c=3;
  printf("%d %d %d\n", m.a, m.b, m.c);
  struct { char a; char b; } arr[3]; char *p = (char*)arr;
  p[0]=0; p[1]=1; p[2]=2; p[3]=3;                      // 跨元素字节写（无 padding 面）
  printf("%d %d %d %d\n", arr[0].a, arr[0].b, arr[1].a, arr[1].b);
  struct { char a[3]; char b[5]; } nb; char *np = (char*)&nb;
  nb.a[0]=6; nb.b[0]=7;
  printf("%d %d\n", np[0], np[3]);
  struct { struct { char b; } a; } nest; nest.a.b=6; printf("%d\n", nest.a.b);
  struct t { char a; } sx; struct t *sy = &sx; sx.a=3;
  printf("%d\n", sy->a);
  sy->a=4; printf("%d\n", sx.a);
  struct { int a,b; } c1, c2; c1.a=3; c2=c1; printf("%d\n", c2.a);
  struct t2 { int a,b; } d1; d1.a=7; struct t2 d2; struct t2 *dz=&d2; *dz=d1; printf("%d\n", d2.a);
  struct t2 *dp=&d1, *dq=&d2; *dq=*dp; printf("%d\n", d2.a);
  struct t3 { char a, b; } e1, e2; e1.a=5; e2=e1; printf("%d\n", e2.a);
  struct t4 { int a; int b; } tagtest; struct t4 tag2;  // tag 作用域
  tag2.a = 8; printf("%d\n", tag2.a);
  struct T { struct T *next; int x; } n1, n2; n2.x=1; n1.next=&n2;
  printf("%d\n", n1.next->x);
  return 0;
}
