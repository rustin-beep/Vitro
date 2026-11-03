// @category: chibicc_port
// source: chibicc test/control.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: switch 基本形态/命中与穿透/default/条件转换 case 标签/do-while
#include <stdio.h>
int main(void) {
  int i = 0;
  switch(0) { case 0:i=5;break; case 1:i=6;break; case 2:i=7;break; }
  printf("%d\n", i);
  switch(1) { case 0:i=5;break; case 1:i=6;break; case 2:i=7;break; }
  printf("%d\n", i);
  switch(3) { case 0:i=5;break; case 1:i=6;break; case 2:i=7;break; }
  printf("%d\n", i);
  switch(0) { case 0:i=5;break; default:i=7; } printf("%d\n", i);
  switch(1) { case 0:i=5;break; default:i=7; } printf("%d\n", i);
  switch(1) { case 0: 0; case 1: 0; case 2: 0; i=2; } printf("%d\n", i);  // 穿透
  switch(3) { case 0: 0; case 1: 0; case 2: 0; i=2; } printf("%d\n", i); // 无命中无 default
  // 注：chibicc 原 ASSERT(3, switch(-1){case 0xffffffff:...})——unsigned 域 case 标签，Vitro E3047 拒收（DIFF 候选），移 deferred
  int j = 0, k = 0;
  do { j++; } while (i++ < 6); printf("%d\n", j);                        // 7
  j=0; do { if (++j > 3) break; continue; k++; } while (1); printf("%d %d\n", j, k);  // 4 0
  return 0;
}
