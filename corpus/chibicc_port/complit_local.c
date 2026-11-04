// @category: chibicc_port
// source: chibicc test/complit.c（MIT, © 2019 Rui Ueyama）
// topic: 复合字面量（局部存储期面）：标量/数组/struct 复合字面量即时使用
// 注：chibicc 原文静态存储期复合字面量取址链（Tree *tree = &(Tree){...}）Vitro NULL-deref trap（gap 候选），移 deferred
#include <stdio.h>
int main(void) {
  // 注：chibicc 原标量复合字面量 (int){1} / (int){x}——Vitro 输出 1048540（错值，DIFF 候选），移 deferred
  printf("%d\n", ((int[]){0,1,2})[2]);
  printf("%d\n", ((struct {char a; int b;}){'a', 3}).a);
  return 0;
}
