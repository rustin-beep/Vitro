// @category: baseline
// #424 B1 followup: char initializer narrowing-warning domain. In-domain
// forms (char c = -1 / unsigned char u = 200 / designated [1] = -1 /
// static char sc = -2) are idiomatic C and must stay silent (clang -Wall
// agrees); out-of-domain forms keep the teaching W3053 (clang agrees via
// -Wconstant-conversion / -Wextra sign-conversion). stdout locks the
// truncated values themselves (C conversion semantics on both sides).
#include <stdio.h>
char a1 = -1;           /* in-domain neg literal */
char a2 = -300;         /* out of signed char domain -> warn */
unsigned char u1 = 200; /* in unsigned domain (128..255) */
unsigned char u2 = -1;  /* negative to unsigned -> warn */
unsigned char u3 = 300; /* out of unsigned domain -> warn */
char arr[2] = {[1] = -1};
int main(void) {
  static char sc = -2;
  printf("%d %d %d %d %d %d %d\n", a1, a2, u1, u2, u3, arr[1], sc);
  return 0;
}
