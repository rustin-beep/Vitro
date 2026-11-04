// @category: baseline
// #424 B1 (review v2 M11-A3 probe pd): static local function-pointer array.
// emit_static_scalar_array_init's 4-byte arm had no Identifier case, so every
// element hit `_ => push((addr, 0))` and fns[0]() trapped "CallPtr index 0
// out of range". The global twin (#201-B) was fixed; static was not.
#include <stdio.h>
int f1(void) { return 11; }
int f2(void) { return 22; }
int main(void) {
  static int (*fns[2])(void) = {f1, f2};
  printf("%d %d\n", fns[0](), fns[1]());
  return 0;
}
