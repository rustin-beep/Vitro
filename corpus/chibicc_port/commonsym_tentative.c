// @category: chibicc_port
// source: chibicc test/commonsym.c（MIT, © 2019 Rui Ueyama）— 支持度预检分拣（tentative definition 面）
// topic: 暂定定义：先声明后定义/先定义后声明/多文件公共符号语义（单文件面）
#include <stdio.h>
int x;
int x = 5;
int common_ext1;       // 无初始化=零
int main(void) {
  // 注：chibicc 原 int y=7; int y;（先定义后暂定）——clang y=7 / Vitro y=0（暂定定义覆盖取先声明，DIFF 候选），移 deferred
  printf("%d %d\n", x, common_ext1);
  return 0;
}
