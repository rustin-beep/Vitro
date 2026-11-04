// @category: baseline
// #424 B1 (review v2 M13-A-3 probe p03): global char scalar literal init.
// 300 = 0x012C; the old 4-byte little-endian store leaked 0x01 into b
// (offset+1, no initialiser -> never overwritten). c is declared after and
// overwrote its own byte, which is exactly the "accidentally right" shape
// that let this survive. Truth: `abc=44 0 66`.
#include <stdio.h>
char a = 300;
char b;
char c = 66;
int main() {
  printf("abc=%d %d %d\n", a, b, c);
  return 0;
}
