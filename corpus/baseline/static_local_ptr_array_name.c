// @category: baseline
// #424 B1 (review v2 M11-A2 probe pc): static local pointer initialised with
// a bare global array name. emit_static_init's Identifier arm only consulted
// func_index and fell through `None => ()` silently, leaving p = NULL and
// trapping E3083 on p[1]. The global path already had the
// push_global_addr_init fallback (#264); the static path was never wired.
#include <stdio.h>
int arr[3] = {5, 6, 7};
int main(void) {
  static int *p = arr;
  printf("%d\n", p[1]);
  return 0;
}
