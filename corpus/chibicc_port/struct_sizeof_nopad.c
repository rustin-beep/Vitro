// @category: chibicc_port
// source: chibicc test/struct.c / sizeof.c（MIT, © 2019 Rui Ueyama）
// topic: struct/数组 sizeof——仅同宽成员（无 padding 面；混合宽成员的 sizeof 属紧排差异面，见 deferred/gap）
#include <stdio.h>
int main(void) {
  struct { int a; } s1; printf("%d\n", (int)sizeof(s1));            // 4
  struct { int a; int b; } s2; printf("%d\n", (int)sizeof(s2));     // 8
  struct { int a, b; } s2b; printf("%d\n", (int)sizeof(s2b));       // 8
  struct { int a[3]; } s3; printf("%d\n", (int)sizeof(s3));         // 12
  struct { int a; } a4[4]; printf("%d\n", (int)sizeof(a4));         // 16
  struct { int a[3]; } a2[2]; printf("%d\n", (int)sizeof(a2));      // 24
  struct { char a; char b; } c2; printf("%d\n", (int)sizeof(c2));   // 2
  struct { char a[3]; char b[5]; } nb; printf("%d\n", (int)sizeof(nb)); // 8
  struct foo *bar; (void)bar;                                       // 不完整类型指针声明
  struct TT { int x; }; struct TT use; use.x = 4;
  printf("%d %d\n", (int)sizeof(struct TT), use.x);
  return 0;
}
