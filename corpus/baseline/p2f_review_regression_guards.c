#include <stdio.h>

// @category: 审阅 2026-10-14 回归锚族（P1-b/P2）——
// designated 全局 symbols 表（越界文案含变量名——降级形态=回归）+
// UL·ULL 后缀宽度区分（sizeof 4/4/8）+ 混合 designated 续位（a[3]=9）。
// 运行期 [deny] 教学 trap vs Clang 无 sanitizer——known_direct 登记。

int a[5] = { [2] = 7, 9 };

struct S { int m; };

int main() {
  printf("%d %d %d\n", (int)sizeof(1u), (int)sizeof(1lu), (int)sizeof(1ull));
  printf("%d\n", a[3]);
  return a[10];
}
