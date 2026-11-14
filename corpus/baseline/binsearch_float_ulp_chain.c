// @category: baseline
// #152: 二分求根迭代浮点链(mid/f(x)/b-a 三列 %.15e)——双臂与 clang -O0
// 逐位一致(立案时 b-a 列 1 ULP 差,2026-11-13 复测已绿,疑 B4 #427 printf
// 高精度段 bigint 化;入库锁迭代+打印全链防回归。原探针样本 BIN_s2.c 为
// 三 Part 大杂烩,按 #437 R5f「一文件一语义点」裁定剥出本段)
#include <stdio.h>
#include <math.h>

int main(void) {
  double a = 1.0, b = 2.0, tolerance = 1e-12;
  int iter = 0;
  printf("%-5s %-20s %-20s %-20s\n", "Iter", "Midpoint", "f(Midpoint)", "Interval Width");
  while (iter < 50) {
    double mid = (a + b) / 2.0;
    double f_mid = mid * mid - 2.0;
    double f_a = a * a - 2.0;
    if (fabs(f_mid) < tolerance || (b - a) / 2.0 < tolerance) {
      printf("%-5d %-20.15f %-20.15e %-20.15e\n", iter, mid, f_mid, b - a);
      break;
    }
    printf("%-5d %-20.15f %-20.15e %-20.15e\n", iter, mid, f_mid, b - a);
    if (f_a * f_mid < 0) {
      b = mid;
    } else {
      a = mid;
    }
    iter++;
  }
  return 0;
}
