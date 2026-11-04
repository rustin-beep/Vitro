// @category: baseline
// #425 B2 (review v2 M13-A1 probes p01/p17): &&/|| operand truthiness used
// truncating casts (CastF2I/D2I/Q2I) so any float in (0,1) tested FALSE and
// an LL whose low 32 bits are zero tested FALSE. Must be numeric != 0.
// The direct-cond forms (if(d)/ternary) are the correct control group.
#include <stdio.h>
int main() {
  printf("%d %d %d %d\n", 0.5f && 1, 0.5 && 1, 2.5f && 1, 0x100000000LL && 1);
  printf("%d\n", 0.4999f || 0);
  double d = 0.5; int n = 0;
  while (d && n < 1) { printf("while_d\n"); n++; }
  printf("tern=%d\n", d ? 1 : 2);
  return 0;
}
