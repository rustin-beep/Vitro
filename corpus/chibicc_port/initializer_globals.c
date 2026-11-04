// @category: chibicc_port
// source: chibicc test/initializer.c（MIT, © 2019 Rui Ueyama）
// topic: 全局标量/数组/struct/union/字符串初始化与静态取址初始化
#include <stdio.h>
#include <string.h>
char g3 = 3;
short g4 = 4;
int g5 = 5;
long g6 = 6;
int g9[3] = {0, 1, 2};
struct { char a; int b; } g11[2] = {{1, 2}, {3, 4}};
struct { int a[2]; } g12[2] = {{{1, 2}}};
// 注：chibicc 原 union 数组平铺初始化 g13[2]={0x01020304,0x05060708}——Vitro E3006 拒收（gap 候选），移 deferred
char g17[] = "foobar";
char g18[10] = "foobar";
char g19[3] = "foobar";      // 截尾无 NUL（chibicc 语义：恰好装下）
int g24 = 3;
int *g25 = &g24;
int g26[3] = {1, 2, 3};
// 注：chibicc 原静态指针算术/成员链初始化族（int *g=g26+1 / char *p=&g11[1].a /
// int *q=g30.a.a）——master B3'/B9 批后升级为 E3075 编译期显式拒绝（原为运行期
// NULL-deref trap，fail loud 改进），形态移差异台账（issue 见 #437 批报告）
int main(void) {
  printf("%d %d %d %lld\n", g3, g4, g5, (long long)g6);
  printf("%d %d %d\n", g9[0], g9[1], g9[2]);
  printf("%d %d %d %d\n", g11[0].a, g11[0].b, g11[1].a, g11[1].b);
  printf("%d %d %d %d\n", g12[0].a[0], g12[0].a[1], g12[1].a[0], g12[1].a[1]);
  printf("%d %d %d\n", (int)sizeof(g17), (int)sizeof(g18), (int)sizeof(g19));
  printf("%d\n", memcmp(g17, "foobar", 7) == 0);
  printf("%d\n", memcmp(g18, "foobar\0\0\0", 10) == 0);
  printf("%d\n", memcmp(g19, "foo", 3) == 0);
  printf("%d %d\n", g24, *g25);
  // 注：chibicc 原静态指针算术/成员链初始化族（int *g27=g26+1 / char *g28=&g11[1].a /
  // int *g31=g30.a.a）——master B3'/B9 批起 Vitro 以 E3075 编译期显式拒绝（fail loud），
  // 形态移差异台账（issue #465），与文件头注口径一致
  return 0;
}
