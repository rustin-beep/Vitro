#include <stdio.h>
enum A { X1 = 3 };
enum B { Y1, Y2 };
int main(void) { enum A a = X1; enum B b = Y2;
  printf("%d %d\n", a, b);
  return 0; }
