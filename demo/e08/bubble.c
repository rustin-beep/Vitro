// E-08 渲染金标准的引擎输入真源（#324 治本批，2026-10-31）——本文件是
// payloads/core.json 的 frames 段唯一来源（tests/e08-export.mts 人工令导出），
// 也是同形性闸（tests/e08-shape.test.mts）现场跑引擎的输入。改本文件后：
//   1. node demo/tests/e08-export.mts   重导 core.json（人工审定 diff）
//   2. cd demo && npx vite build --ssr src/e08/entry.ts --outDir dist-e08
//      && node demo/tests/e08-update.mts  重冻 golden（人工审定 diff）
// 禁止手改 payloads/*.json 的 frames/outputs/labels/capabilities 段——那些
// 段的真相源是引擎（#324：手写夹具与实产形态相反，闸测不到真机协议流）。
#include <stdio.h>

int main(void) {
    int a[5] = {5, 3, 1, 4, 2};
    int n = 5;
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - 1 - i; j++) {
            if (a[j] > a[j + 1]) {
                int t = a[j];
                a[j] = a[j + 1];
                a[j + 1] = t;
            }
        }
    }
    for (int k = 0; k < n; k++) printf("%d ", a[k]);
    return 0;
}
