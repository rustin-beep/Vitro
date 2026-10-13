#include <stdio.h>
#include <stdlib.h>

// @category: #75 三缺口 + #76 两缺口回归锚（LLM 语料线产出·跨模型复现·
// clang/gcc 双 ACCEPT）——宽 LL 下标 / malloc(sizeof *p) 自身引用 /
// struct char[] 成员字符串初始化（2026-10-12 批）；文件作用域指定
// 初始化器 / stdio.h 传递 ptrdiff_t（2026-10-13 批·gpt-oss-120b 产出）。

struct S { char s[64]; };
struct T { int n; char s[64]; };

// #76 缺口 4：文件作用域指定初始化器（C11 6.7.9——Index designator 定位
// + 续位 + 未提及位静态零；修复前 codegen fail loud 拒绝）
int grid[8] = { [2] = 7, 9, [5] = -3 };
long long big[4] = { [1] = 1234567890123LL, 5 };
double ratios[3] = { [2] = 2.5 };

int main(void) {
  // 缺口 1：long long 下标（E3039 假阳性 ×6 + E3040 级联）
  int arr[8] = {64, 34, 25, 12, 22, 11, 90, 1};
  long long i, j, n = 8;
  for (i = 0; i < n - 1; i++)
    for (j = 0; j < n - i - 1; j++)
      if (arr[j] > arr[j + 1]) { int t = arr[j]; arr[j] = arr[j+1]; arr[j+1] = t; }
  printf("%d %d\n", arr[0], arr[7]);
  // 缺口 2：malloc(n * sizeof *p)——声明符作用域始于初始化器（C11 6.2.1p2）
  int m = 5;
  int *p = malloc(m * sizeof *p);
  p[0] = 42;
  printf("%d\n", p[0]);
  // #76 缺口 5：ptrdiff_t 随 stdio.h 传递（修复前 E2003；stddef.h 绕法除外）
  ptrdiff_t d = (char*)p + 1 - (char*)p;
  free(p);
  // 缺口 3：struct char[] 成员字符串初始化（C11 6.7.9p14）
  struct S a = {"Hi"};
  struct T c = {1, "Yo"};
  printf("%s %d%s\n", a.s, c.n, c.s);
  // #76 缺口 4 值断言（续位 [3]=9 / 静态零 a[0] / 8 字节与 double 位模式）
  printf("%d %d %d %d\n", grid[2], grid[3], grid[5], grid[0]);
  printf("%lld %lld %lld\n", big[1], big[2], big[0]);
  printf("%.1f %.1f\n", ratios[2], ratios[0]);
  printf("%d\n", (int)(d == 1));
  return 0;
}
