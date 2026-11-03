// @category: chibicc_port
// source: chibicc test/control.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: goto 前向跳转 + break/continue 嵌套循环
#include <stdio.h>
int main(void) {
  int i = 0;
  goto a;
  a: i++; b: i++; c: i++;
  printf("%d\n", i);                 // 1（顺序落达）
  i = 0; goto e;
  d: i++; e: i++; f: i++;
  printf("%d\n", i);                 // 1（跳过 d）
  i=0; for(;i<10;i++) { if (i == 3) break; } printf("%d\n", i);
  i=0; while (1) { if (i++ == 3) break; } printf("%d\n", i);
  i=0; for(;i<10;i++) { for (;;) break; if (i == 3) break; } printf("%d\n", i);
  i=0; while (1) { while(1) break; if (i++ == 3) break; } printf("%d\n", i);
  int j=0;
  for (i=0;i<10;i++) { if (i>5) continue; j++; }
  printf("%d %d\n", i, j);           // 10 6
  j=0; for(;!i;) { for (;j!=10;j++) continue; break; } printf("%d\n", j);
  j=0; while (i++<10) { if (i>5) continue; j++; } printf("%d %d\n", i, j);
  j=0; i=0; while(!i) { while (j++!=10) continue; break; } printf("%d\n", j);
  return 0;
}
