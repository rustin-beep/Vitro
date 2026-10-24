#include <stdio.h>

char nb = 'Z';
int main(void) {
  char c1 = 128; char c2 = -1;
  char a1 = 'A', a2 = 'B', a3 = 'C';
  c1 = 128; c2 = -1;
  c1 -= 1; c2 -= 1;
  printf("%d %d\n", c1, c2);
  printf("%c%c%c\n", a1, a2, a3);
  return 0;
}
