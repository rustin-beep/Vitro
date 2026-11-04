// @category: chibicc_port
// source: chibicc test/vla.c / alloca.c 头部主题（MIT, © 2019 Rui Ueyama）— Vitro 已有 VLA 支持面，边界 port
// topic: 变长数组基本形态：运行期定维/循环内重建/VLA 传参（alloca 面不 port）
#include <stdio.h>
int sum_vla(int n, int a[n]) {
  int s = 0; for (int i = 0; i < n; i++) s += a[i]; return s;
}
int main(void) {
  int n = 4;
  int a[n];
  for (int i = 0; i < n; i++) a[i] = i * 10;
  printf("%d %d\n", (int)sizeof(a), a[3]);       // sizeof VLA 运行期
  printf("%d\n", sum_vla(n, a));                 // VLA 参数
  for (int k = 1; k <= 3; k++) {
    int b[k];
    for (int i = 0; i < k; i++) b[i] = i;
    printf("%d %d\n", (int)sizeof(b), b[k-1]);   // 循环内重建
  }
  return 0;
}
