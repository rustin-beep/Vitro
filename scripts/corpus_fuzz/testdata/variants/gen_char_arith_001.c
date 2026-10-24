#include <stdio.h>

char c1 = 254; char c2 = -127; char nb = 'Z';
int main(void) {
  c1 = 254; c2 = -127;
  c1 *= 2; c2 *= 2;
  printf("%d %d\n", c1, c2);
  return 0;
}
