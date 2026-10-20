// @category: baseline
// #156 红锚：register 变量取地址（C11 6.7.1p4 约束）必须诊断——clang/gcc
// 双 error "address of register variable requested"；vitro 修后 E3078。
// 三变体：&x 直接取址 / register 数组下标（隐含退化取址）/ scanf 写入；
// 对照组 register 普通使用（算术/传值/返回）合法零误报。
#include <stdio.h>
int main(void) {
  register int x = 5;
  register int arr[3];
  register int ok = 10;
  int *p = &x;                  /* 非法：直接取址 */
  arr[0] = 1;                   /* 非法：下标隐含数组退化取址 */
  int use = ok + x;             /* 合法：普通算术 */
  printf("%d\n", use);
  return ok;
}
