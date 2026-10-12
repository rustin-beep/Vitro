#include <stdio.h>
#include <stdlib.h>

// @category: #75 三缺口回归锚（LLM 语料线产出·跨模型复现·clang/gcc 双
// ACCEPT）——宽 LL 下标 / malloc(sizeof *p) 自身引用 / struct char[] 成员
// 字符串初始化，2026-10-12 修复批。

struct S { char s[64]; };
struct T { int n; char s[64]; };

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
  free(p);
  // 缺口 3：struct char[] 成员字符串初始化（C11 6.7.9p14）
  struct S a = {"Hi"};
  struct T c = {1, "Yo"};
  printf("%s %d%s\n", a.s, c.n, c.s);
  return 0;
}
