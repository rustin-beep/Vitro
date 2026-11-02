#include <stdio.h>
int main(void) { register int r = 24; register int s = r * 4;
  printf("%d\n", r + s);
  return r + s; }
