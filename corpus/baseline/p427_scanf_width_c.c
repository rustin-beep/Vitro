// #427 批 B4 语料锚：scanf/sscanf %Nc 字段宽度（M20 A-3，范围外顺手）
// ——sscanf 形态（自包含无 stdin 依赖，vm_diff 域）；scanf 流式同修锚在
// wbtest（host_b4_printf_wbtest.mbt scanf_b4_width_c）。
#include <stdio.h>

int main(void) {
  char b[8] = {0, 0, 0, 0, 0, 0, 0, 0};
  int r = sscanf("abcdef", "%3c", b);
  printf("r=%d [%s]\n", r, b);
  // 宽度 1（缺省语义显式形态）+ 抑制臂
  char c2[4] = {0, 0, 0, 0};
  int r2 = sscanf("xy", "%1c", c2);
  printf("r2=%d [%s]\n", r2, c2);
  int r3 = sscanf("abcdef", "%*3c%c", c2);
  printf("r3=%d [%s]\n", r3, c2);
  return 0;
}
