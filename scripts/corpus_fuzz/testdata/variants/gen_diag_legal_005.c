#include <stdio.h>
int g[4];
int main(void) {
  char s[] = "ok4"; int a[4] = {0};
  for (int i = 0; i < 4; i++) a[i] = i;
  printf("%d %s %d\n", a[3], s, (int)sizeof(g));
  return 0; }
