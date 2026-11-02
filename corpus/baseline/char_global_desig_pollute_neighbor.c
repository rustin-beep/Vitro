// @category: baseline
// #424 B1 (review v2 M11-A1 probe pa3): designated char write at the last
// element spilled three 0xFF bytes into the *uninitialised* neighbour b,
// which has no init record to overwrite them back -> permanent pollution.
// Truth: `-1 0 0 2`.
#include <stdio.h>
char a[4] = {[3] = -1};
char b[2];
int main(void) {
  printf("%d %d %d %d\n", a[3], b[0], b[1], (int)sizeof(b));
  return 0;
}
