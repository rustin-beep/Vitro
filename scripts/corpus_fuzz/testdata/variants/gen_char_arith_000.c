#include <stdio.h>

char nb = 'Z';
int main(void) {
  char c1 = 127; char c2 = 127;
  c1 = 127; c2 = 127;
  c1 += 1; c2 += 1;
  printf("%d %d\n", c1, c2);
  return 0;
}
