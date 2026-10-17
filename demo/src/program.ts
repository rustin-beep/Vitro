// 首屏默认编辑器内容（行为拍板 2026-10-17：恢复旧栈指引文案形态——空态
// 指引承担断点/跳转的功能发现性，此前预载冒泡让这些提示没了载体）。
// ⚠️ 基准对拍程序拆到 BENCH_PROGRAM（?autorun/?bench 钩子专用——与
// fw_pilot/program.c 同源的冒泡，帧数/FLIP 指标可与历史实测对表；指引
// 文案不能当基准负载）。
export const DEFAULT_PROGRAM = `// 请输入代码，或者在「内容」选择要预先载入的示例
// 注意：从内容页选择时会覆盖编辑器里原有的代码
// 提示：编辑器左侧行号单击可设置/取消断点（采集回放将在断点处暂停）；
//       回放条「步号跳转」可直达目标帧；「⚙ 设置」可切换主题与字号
//
`;

export const BENCH_PROGRAM = `#include <stdio.h>

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
