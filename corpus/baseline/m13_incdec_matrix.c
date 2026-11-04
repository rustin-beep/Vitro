// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M13 p09「++/-- 步长矩阵 13 项」无发现面——char/uchar/float/double/LL/
// 指针/(*p)++/成员/前后缀全链三方一致。来源：tmp/review_v2_M13/probes/p09_incdec.c
#include <stdio.h>
struct P { int x; int y; };
int main(void) {
  char c = 127; c++; printf("c=%d\n", c);          // -128
  unsigned char uc = 255; uc++; printf("uc=%d\n", uc); // 0
  float f = 1.5f; f++; printf("f=%.1f\n", f);       // 2.5
  double d = 2.5; d--; printf("d=%.1f\n", d);       // 1.5
  long long q = 5LL; q++; printf("q=%lld\n", q);    // 6
  int arr[3] = {1, 2, 3};
  int *p = arr; p++; printf("p=%d\n", *p);          // 2
  (*p)++; printf("deref=%d\n", *p);                 // 3
  arr[0]++; printf("idx=%d\n", arr[0]);             // 2
  struct P s = {1, 2}; s.x++; printf("mem=%d\n", s.x); // 2
  int i = 5; int post = i++; printf("post=%d i=%d\n", post, i); // 5 6
  int pre = ++i; printf("pre=%d i=%d\n", pre, i);   // 7 7
  char gc = 'A'; gc++; printf("gc=%c\n", gc);       // B
  double dp[2] = {1.5, 2.5}; double *q2 = dp; q2++; printf("dp=%.1f\n", *q2); // 2.5
  return 0;
}
