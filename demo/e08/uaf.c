// E-08 diagband-trap 用例的引擎输入真源（#324 治本批，2026-10-31）——
// use-after-free 教学标准案：malloc → 赋值 → free → 读已释放块（E3060）。
// payloads/diagband-trap.json 的 frames/stopped/runStats 段唯一来源
// （tests/e08-export.mts 人工令导出，取 step 流末帧 = trap 帧，带引擎实产
// root_cause_hint 与 pointer_snapshots 的 Freed 状态）。
// 改本文件后与 bubble.c 同款连坐：e08-export.mts 重导 → golden 重冻 →
// 同形性闸必须绿。
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    int *p = malloc(sizeof(int));
    *p = 42;
    free(p);
    printf("%d\n", p[0]);
    return 0;
}
