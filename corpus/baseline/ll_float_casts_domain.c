// @category: baseline
// #471 B 轮连坐 (speed-table C1/C2/C10/C11, in-domain A face): LL<->float
// conversions in both directions. Old shape: LL->F fed the low 32 bits of
// the i64 stack slot to CastI2F (bit-pattern value 705032704 for 5e9);
// F->LL emitted no conversion at all (f32 bit pattern stored as i64,
// -2.5f -> -1071644672). Truth (win-clang / MinGW-gcc / WSL, and vitro
// js+native+wasm after fix): "5000000000 -2 -2 1 2 7"
#include <stdio.h>
int main() {
  float f = (float)5000000000LL;    /* LL -> F */
  long long a = -2.5f;              /* F -> LL, assignment */
  long long b = (long long)(-2.5f); /* F -> LL, explicit cast */
  float g = 1.5f; long long c = g;  /* F -> LL, variable source */
  long long d = 2.5;                /* double -> LL (regression) */
  float h = 7;                      /* int -> F (regression) */
  printf("%.0f %lld %lld %lld %lld %.0f\n", (double)f, a, b, c, d, (double)h);
  return 0;
}
