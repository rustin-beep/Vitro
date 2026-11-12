// @category: baseline
// #477 探针（2026-11-05）：qsort/bsearch 宿主回调段帧连续（INV3a）——
// comparator 多轮逐指令执行（双比较器：升/降序 × qsort 排序 + bsearch
// 命中/未命中），step 帧流 step_index 须全流连续无 gap、seek 可寻址
// 回调内部步（嵌套帧语义）。
#include <stdio.h>
#include <stdlib.h>

int cmp_asc(const void* a, const void* b) {
    return *(const int*)a - *(const int*)b;
}

int cmp_desc(const void* a, const void* b) {
    return *(const int*)b - *(const int*)a;
}

int main() {
    int a[6] = {5, 2, 9, 1, 7, 3};
    qsort(a, 6, sizeof(int), cmp_asc);
    printf("asc:");
    for (int i = 0; i < 6; i++) printf(" %d", a[i]);
    printf("\n");
    int key = 7;
    int* hit = (int*)bsearch(&key, a, 6, sizeof(int), cmp_asc);
    printf("hit: %d\n", hit ? *hit : -1);
    qsort(a, 6, sizeof(int), cmp_desc);
    printf("desc:");
    for (int i = 0; i < 6; i++) printf(" %d", a[i]);
    printf("\n");
    int miss = 4;
    int* miss_r = (int*)bsearch(&miss, a, 6, sizeof(int), cmp_desc);
    printf("miss: %d\n", miss_r ? *miss_r : -1);
    return 0;
}
