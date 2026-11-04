// @category: baseline
// #424 B1 (review v2 M11-A1 probe pa): global char array designated init.
// The old path pushed every elem_size<8 element through the 4-byte
// globals_init_32 store, so `[1] = -1` wrote 0xFFFFFFFF over a[1..4] and
// a[2]/a[3] read back -1. Must be exactly one byte: `0 -1 0 0 0`.
#include <stdio.h>
char a[4] = {[1] = -1};
char b[2] = {0, 0};
int main(void) {
  printf("%d %d %d %d %d\n", a[0], a[1], a[2], a[3], b[0]);
  return 0;
}
