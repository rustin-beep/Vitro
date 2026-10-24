#include <stdio.h>
int main(void) { register int r = 33; register int s = r * 2;
  printf("%d\n", r + s);
  return r + s; }
