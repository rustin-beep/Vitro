// @category: baseline
// #198 红锚：局部 char 算术后不回窄字节域——复合赋值与 ++/-- 全族
//（127++ 应 -128 非 128；-128-- 应 127 非 -129；255uc++ 应 0 非 256；
// post/pre 表达式返回值同受窄化语义约束）。arr[1] 行对照：Index 左值
// 走 MemByte 族天然窄化（应 -128）；末行 gc 亦局部（全局形态另由
// char_global_read_extents 锁）。
#include <stdio.h>
int main(void) {
  char a; a = 200;
  char b = 127; b += 1;
  char c = 100; c *= 2;
  char d = 127; d++;
  char e = 127; ++e;
  char f = -128; f--;
  char g = 127; char h = g++;
  char i = 127; char j = ++i;
  unsigned char u = 255; u++;
  char arr[2] = {100, 127}; arr[1] += 1;
  char gc = 127; gc++;
  printf("%d %d %d %d %d %d %d %d %d %d %d\n",
         a, b, c, d, e, f, g, h, i, j, arr[1]);
  printf("%d %d\n", u, gc);
  return 0;
}
