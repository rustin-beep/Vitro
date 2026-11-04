// @category: baseline
// #467 P1 (review of B2 batch): compound-assignment domain promotion must
// keep the UNSIGNED axis. Values crossing the sign bit used to go through
// signed casts (CastI2Q/CastI2D/CastQ2D) giving -1 / negative doubles; the
// fix picks the U-dual opcode per (src kind x src signedness x target
// domain). Truth (clang): 4294967295 4294967295.0 4294967296.0 1.8000e+19
// 3000000000.0
#include <stdio.h>
int main() {
  unsigned u = 4294967295u;
  long long x = 0; x += u;
  double d = 0; d += u;
  float f = 0; f += u;
  unsigned long long q = 18000000000000000000ULL;
  double d2 = 0; d2 += q;
  unsigned big = 3000000000u;
  double d3 = 0; d3 += big;
  printf("%lld %.1f %.1f %.4e %.1f\n", x, d, f, d2, d3);
  return 0;
}
