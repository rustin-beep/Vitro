// 试点默认被测程序——与 spike 对拍基准（fw_pilot/program.c、fw_bench3/frames.json）
// 同一份源码，帧率/FLIP 指标可与历史实测直接对表。
export const DEFAULT_PROGRAM = `#include <stdio.h>

int main(void) {
  int a[8] = {8, 3, 5, 1, 9, 2, 7, 4};
  int n = 8;
  for (int i = 0; i < n - 1; i = i + 1) {
    for (int j = 0; j < n - 1 - i; j = j + 1) {
      if (a[j] > a[j + 1]) {
        int t = a[j];
        a[j] = a[j + 1];
        a[j + 1] = t;
      }
    }
  }
  for (int k = 0; k < n; k = k + 1) {
    printf("%d ", a[k]);
  }
  printf("\\n");
  return 0;
}
`;
