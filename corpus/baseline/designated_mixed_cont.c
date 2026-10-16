// @category: baseline
#include <stdio.h>
struct S { int a, b, c; };
int main(){
  struct S s = {.a=1, .c=3};
  struct S t = {.c=30, .b=20};
  struct S u = {.a=1, 2, 3};
  int arr[5] = {[2]=22, [0]=11};
  printf("%d %d %d | %d %d | %d %d %d | %d %d\n", s.a, s.b, s.c, t.b, t.c, u.a, u.b, u.c, arr[0], arr[2]);
  return 0; }
