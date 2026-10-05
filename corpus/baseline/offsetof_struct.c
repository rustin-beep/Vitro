// @category: baseline
#include <stdio.h>
#include <stddef.h>
struct S { int a; int b; int c; };
int main() { printf("%d %d", (int)offsetof(struct S, a), (int)offsetof(struct S, c)); return 0; }
