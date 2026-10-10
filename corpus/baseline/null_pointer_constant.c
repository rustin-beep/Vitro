// @category: diagnostics
#include <stddef.h>
// #56：空指针常量（C11 6.3.2.3）转指针的惯用法全族——W3054 不得误报。
// 覆盖面：初始化（NULL / 字面量 0）、赋值、函数实参、聚合初始化。
// Clang -Wall -Wextra 对本用例零警告（issue 实测口径）。
static int sink(void *p) {
  return p == 0 ? 1 : 0;
}

int main() {
  char *p = NULL;
  void *v = 0;
  p = 0;
  sink(NULL);
  sink(0);
  char *arr[2] = { NULL, 0 };
  return p == 0 && v == 0 && arr[0] == 0 && arr[1] == 0 ? 42 : 1;
}
