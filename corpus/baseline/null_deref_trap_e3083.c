// @category: baseline
// #178 锁面锚：NULL 指针解引用 trap 带 E3083 码位（对齐 E3060 uaf 的
//「文案带码」形态；error_catalog 106 卡有条目——demo 码表卡可渲染）。
// 写/读两形态；对照组判空分支正常返回。trap 文案进 note 通道非 stdout，
// 双侧对拍面 = 对照组输出 + 两侧异常终止。
#include <stdlib.h>
#include <stdio.h>
int main(void) {
  int *p = NULL;
  if (p != NULL) {          /* 对照：判空分支不触发 */
    *p = 1;
  }
  printf("guard-ok\n");
  int *q = NULL;
  *q = 1;                   /* trap：NULL 写（E3083） */
  return 0;
}
