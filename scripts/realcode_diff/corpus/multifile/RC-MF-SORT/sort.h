#ifndef SORT_H
#define SORT_H

#define SORT_MAX 64

typedef int (*SortCmp)(const void *a, const void *b);

typedef struct {
    long comparisons;
    long swaps;
} SortStats;

void sort_insertion(int *values, int count, SortCmp cmp, SortStats *stats);
void sort_quick(int *values, int count, SortCmp cmp, SortStats *stats);
void sort_merge(int *values, int count, SortCmp cmp, SortStats *stats);
void sort_heap(int *values, int count, SortCmp cmp, SortStats *stats);
void sort_counting(int *values, int count, SortStats *stats);
void sort_callback(void *base, int count, int size, SortCmp cmp);
int sort_compare_ints(const void *a, const void *b);
int sort_compare_strings(const void *a, const void *b);
int sort_same(const int *a, const int *b, int count);

#endif /* SORT_H */
