// @category: chibicc_port
// source: chibicc test/alignof.c / offsetof.c（MIT, © 2019 Rui Ueyama）
// topic: _Alignof 基本类型与数组；offsetof 无 padding struct（_Alignas/混合宽成员偏移属差异面，见 deferred）
#include <stdio.h>
#include <stddef.h>
int main(void) {
  printf("%d\n", (int)_Alignof(char));       // 1
  printf("%d\n", (int)_Alignof(int));        // 4
  printf("%d\n", (int)_Alignof(char[3]));    // 1
  printf("%d\n", (int)_Alignof(int[3]));     // 4
  char cx; printf("%d\n", (int)_Alignof(cx));
  int ix; printf("%d\n", (int)_Alignof(ix));
  // 注：chibicc 原 _Alignof(char)<<31>>31——clang 1（size_t 无符号逻辑移位）/ Vitro -1（按 int 算术移位），
  // sizeof/_Alignof 类型符号性差异（速查表 Z12 同族 DIFF 候选），移 deferred
  typedef struct { char a[3]; char b[5]; } NoPad;      // 同宽成员无 padding
  printf("%d %d\n", (int)offsetof(NoPad, a), (int)offsetof(NoPad, b));  // 0 3
  printf("%d\n", (int)sizeof(NoPad));                   // 8
  return 0;
}
