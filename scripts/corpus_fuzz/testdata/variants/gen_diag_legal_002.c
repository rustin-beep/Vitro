#include <stdio.h>
int arr1[2]; int arr2[2];
int main(void) {
  for (int i = 0; i < 2; i++) arr1[i] = i * 1;
  int *p = arr1;
  printf("%d %d\n", arr1[0], p[1]);
  return 0; }
