// @category: baseline
#include <stdio.h>
int main() { int x = 0, y = 0; int r = (x = 1, y = 2, x + y); printf("%d %d %d", x, y, r); return 0; }
