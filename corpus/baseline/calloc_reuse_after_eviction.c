#include <stdio.h>
#include <stdlib.h>

/* calloc 复用隔离驱逐块不得误报 UAF（存量缺陷①红→绿锚，2026-09-23）：
 * 600 x 512B 的 malloc/free 使隔离区超过 256KB 预算，随后的 calloc 驱逐
 * 最老块进 free_list 并 first-fit 复用同址——清理 freed_logs 必须发生在
 * 置零（受检写）之前，否则撞自己的检验窗口。 */
int main(void) {
  char *keep[600];
  for (int i = 0; i < 600; i++) keep[i] = malloc(512);
  for (int i = 0; i < 600; i++) free(keep[i]);
  char *p = calloc(1, 512);
  if (p == NULL) { printf("null\n"); return 1; }
  printf("%d\n", (int)p[0]);
  p[0] = 7;
  printf("%d\n", (int)p[0]);
  free(p);
  return 0;
}
