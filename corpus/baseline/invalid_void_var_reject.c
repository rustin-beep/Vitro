// @category: baseline
// #182 D-1 红锚：void 类型变量（C11 6.7.6p6——void 是不完整类型不能
// 定义对象）clang/gcc 双 error；vitro 修后 E3076。对照组 void 函数
// 返回/void 参数表合法零误报。
#include <stdio.h>
void vv;
int main(void) {
  void w;
  printf("ok\n");
  return 0;
}
