// @category: baseline
// #471 (review v2 M12 A-3 / PR #467 P2): fp -> unsigned integer in-domain
// conversion is DEFINED behavior (C11 6.3.1.4) across all four paths:
// explicit cast / plain assignment / binary narrowing / compound assign.
// Old shape saturated via CastD2I/CastD2Q: every path returned INT_MAX /
// INT64_MAX for in-domain values (3e9 -> 2147483647, 1.8e19 -> 2^63-1).
// Truth (win-clang 22.1.4 / MinGW-gcc / WSL-gcc, vitro js+native+wasm):
// "3000000000 18000000000000000000 3000000000 18000000000 3000000000 3000000000"
#include <stdio.h>
int main() {
  unsigned y = (unsigned)3000000000.0; /* explicit cast, uint */
  unsigned long long r = (unsigned long long)18000000000000000000.0; /* cast, ull: [2^63,2^64) segment */
  unsigned a = 3000000000.0;           /* plain assignment, uint */
  double d = 6000000000.0;
  unsigned long long f = d * 3.0;      /* binary narrowing, ull */
  unsigned x = 0; x += 3000000000.0;   /* compound assign, uint */
  unsigned g = 0; g += 3000000000.0f;  /* compound, uint, float src (exact in f32) */
  printf("%u %llu %u %llu %u %u\n", y, r, a, f, x, g);
  return 0;
}
