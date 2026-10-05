#include <stdio.h>

#define FEATURE_A

#ifdef FEATURE_A
int a = 1;
#else
int a = 2;
#endif

#ifndef FEATURE_B
int b = 3;
#else
int b = 4;
#endif

#define OUTER
#ifdef OUTER
  #ifdef INNER
    int c = 5;
  #else
    int c = 6;
  #endif
#else
  int c = 7;
#endif

#ifndef GUARD_H
#define GUARD_H
int d = 8;
#endif

int main() {
    printf("%d %d %d %d\n", a, b, c, d);
    return 0;
}
