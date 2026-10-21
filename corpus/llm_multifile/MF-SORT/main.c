// @category: llm_multifile
// 工程：MF-SORT — 五种排序对比 + qsort 风格函数指针比较器
// 来源：LLM 多文件语料（2026-10-21 入库；clang golden 由 clang_direct 工程模式现场生成）
#include <stdio.h>
#include <string.h>
#include "sort.h"

static void print_values(const char *label, const int *values, int count)
{
    int i;

    printf("  %-22s", label);
    for (i = 0; i < count; i++) {
        printf(" %d", values[i]);
    }
    printf("\n");
}

static void run_all(const char *title, const int *input, int count)
{
    int work[SORT_MAX];
    int results[5][SORT_MAX];
    SortStats stats[5];
    int same = 1;
    int i;
    int k;

    printf("=== %s ===\n", title);
    print_values("input", input, count);

    memcpy(work, input, (size_t)count * sizeof(int));
    memset(&stats[0], 0, sizeof stats[0]);
    sort_insertion(work, count, sort_compare_ints, &stats[0]);
    memcpy(results[0], work, (size_t)count * sizeof(int));

    memcpy(work, input, (size_t)count * sizeof(int));
    memset(&stats[1], 0, sizeof stats[1]);
    sort_quick(work, count, sort_compare_ints, &stats[1]);
    memcpy(results[1], work, (size_t)count * sizeof(int));

    memcpy(work, input, (size_t)count * sizeof(int));
    memset(&stats[2], 0, sizeof stats[2]);
    sort_merge(work, count, sort_compare_ints, &stats[2]);
    memcpy(results[2], work, (size_t)count * sizeof(int));

    memcpy(work, input, (size_t)count * sizeof(int));
    memset(&stats[3], 0, sizeof stats[3]);
    sort_heap(work, count, sort_compare_ints, &stats[3]);
    memcpy(results[3], work, (size_t)count * sizeof(int));

    memcpy(work, input, (size_t)count * sizeof(int));
    memset(&stats[4], 0, sizeof stats[4]);
    sort_counting(work, count, &stats[4]);
    memcpy(results[4], work, (size_t)count * sizeof(int));

    print_values("insertion", results[0], count);
    print_values("quick", results[1], count);
    print_values("merge", results[2], count);
    print_values("heap", results[3], count);
    print_values("counting", results[4], count);

    for (k = 1; k < 5; k++) {
        if (!sort_same(results[0], results[k], count)) {
            same = 0;
        }
    }
    printf("  all_results_identical=%s\n", same ? "yes" : "no");
    for (k = 0; k < 5; k++) {
        const char *names[5] = { "insertion", "quick", "merge", "heap", "counting" };
        printf("    %-10s comparisons=%-5ld swaps=%-5ld\n", names[k],
               stats[k].comparisons, stats[k].swaps);
    }
    for (i = 0; i < count; i++) {
        if (results[0][i] != input[i]) {
            break;
        }
    }
}

int main(void)
{
    static const int DATA[20] = {
        42, 7, 19, 3, 25, 11, 33, 5, 17, 29,
        1, 46, 9, 38, 14, 21, 31, 6, 12, 27
    };
    static const int DUPLICATES[20] = {
        5, 3, 5, 3, 9, 3, 5, 9, 1, 3,
        5, 5, 9, 3, 1, 5, 3, 9, 9, 5
    };
    static const int SORTED[20] = {
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
        11, 12, 13, 14, 15, 16, 17, 18, 19, 20
    };
    const char *names[6] = { "delta", "alpha", "echo", "bravo", "charlie", "foxtrot" };
    const char *sorted_names[6];
    int i;

    run_all("twenty random values", DATA, 20);
    run_all("twenty values with many duplicates", DUPLICATES, 20);
    run_all("already sorted input", SORTED, 20);

    printf("=== callback style sort of strings ===\n");
    for (i = 0; i < 6; i++) {
        printf("  before[%d]=%s\n", i, names[i]);
        sorted_names[i] = names[i];
    }
    sort_callback(sorted_names, 6, (int)sizeof(const char *), sort_compare_strings);
    for (i = 0; i < 6; i++) {
        printf("  after[%d]=%s\n", i, sorted_names[i]);
    }
    printf("=== done ===\n");
    return 0;
}
