// @category: baseline
// #182 D-3 红锚：负长度数组（C11 6.7.6.2p1 约束）clang/gcc 双 error
// "array size is negative"；vitro 旧 W2002 警告误收，修后升 E3081
//（`a[-1]` 与 `a[-2]` 两形态——前者 dims 哨兵与 [] 同值，无初始化器
// 双形态 clang 均 error）。对照组正尺寸/推断尺寸/零尺寸（W 维持）合法。
#include <stdio.h>
int main(void) {
  int a[-1];
  int b[-2];
  int ok[2] = {1, 2};
  printf("%d\n", ok[0]);
  return 0;
}
