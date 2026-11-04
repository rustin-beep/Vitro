// @category: baseline
// #425 B2 (review v2 M13-A4 probe p14): logical not (!) judged the raw i32
// bit pattern -- the f32 bit pattern of -0.0f (0x80000000) is nonzero so
// !(-0.0f) gave 0, and an LL was judged on its low 32 bits only so
// !0x100000000LL gave 1. Must be numeric == 0 per type.
#include <stdio.h>
int main() {
  printf("n2=%d %d\n", !(-0.0), !(-0.0f));      /* C: 1 1 */
  printf("n3=%d %d\n", !0x100000000LL, !1LL);   /* C: 0 0 */
  return 0;
}
