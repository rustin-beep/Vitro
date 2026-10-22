#include "sort.h"
#include <string.h>

int sort_compare_ints(const void *a, const void *b)
{
    int left = *(const int *)a;
    int right = *(const int *)b;

    if (left < right) {
        return -1;
    }
    if (left > right) {
        return 1;
    }
    return 0;
}

int sort_compare_strings(const void *a, const void *b)
{
    const char *const *left = (const char *const *)a;
    const char *const *right = (const char *const *)b;

    return strcmp(*left, *right);
}

static int sort_cmp_values(const int *a, const int *b, SortCmp cmp)
{
    if (cmp != NULL) {
        return cmp(a, b);
    }
    return sort_compare_ints(a, b);
}

static void sort_swap(int *a, int *b, SortStats *stats)
{
    int tmp = *a;

    *a = *b;
    *b = tmp;
    if (stats != NULL) {
        stats->swaps++;
    }
}

void sort_insertion(int *values, int count, SortCmp cmp, SortStats *stats)
{
    int i;

    for (i = 1; i < count; i++) {
        int j = i;
        int current = values[i];
        while (j > 0) {
            if (stats != NULL) {
                stats->comparisons++;
            }
            if (sort_cmp_values(&current, &values[j - 1], cmp) >= 0) {
                break;
            }
            values[j] = values[j - 1];
            j--;
        }
        if (j != i) {
            values[j] = current;
            if (stats != NULL) {
                stats->swaps++;
            }
        }
    }
}

static void sort_quick_part(int *values, int low, int high, SortCmp cmp, SortStats *stats)
{
    int i = low;
    int j = high;
    int pivot = values[low + (high - low) / 2];

    while (i <= j) {
        while (1) {
            if (stats != NULL) {
                stats->comparisons++;
            }
            if (sort_cmp_values(&values[i], &pivot, cmp) >= 0) {
                break;
            }
            i++;
        }
        while (1) {
            if (stats != NULL) {
                stats->comparisons++;
            }
            if (sort_cmp_values(&values[j], &pivot, cmp) <= 0) {
                break;
            }
            j--;
        }
        if (i <= j) {
            if (i != j) {
                sort_swap(&values[i], &values[j], stats);
            }
            i++;
            j--;
        }
    }
    if (low < j) {
        sort_quick_part(values, low, j, cmp, stats);
    }
    if (i < high) {
        sort_quick_part(values, i, high, cmp, stats);
    }
}

void sort_quick(int *values, int count, SortCmp cmp, SortStats *stats)
{
    if (count > 1) {
        sort_quick_part(values, 0, count - 1, cmp, stats);
    }
}

static void sort_merge_run(int *values, int *scratch, int low, int mid, int high,
                            SortCmp cmp, SortStats *stats)
{
    int i = low;
    int j = mid;
    int k = low;

    while (i < mid && j < high) {
        if (stats != NULL) {
            stats->comparisons++;
        }
        if (sort_cmp_values(&values[i], &values[j], cmp) <= 0) {
            scratch[k++] = values[i++];
        } else {
            scratch[k++] = values[j++];
            if (stats != NULL) {
                stats->swaps++;
            }
        }
    }
    while (i < mid) {
        scratch[k++] = values[i++];
    }
    while (j < high) {
        scratch[k++] = values[j++];
    }
    for (i = low; i < high; i++) {
        values[i] = scratch[i];
    }
}

void sort_merge(int *values, int count, SortCmp cmp, SortStats *stats)
{
    int scratch[SORT_MAX];
    int size = 1;

    if (count <= 1) {
        return;
    }
    while (size < count) {
        int low;
        for (low = 0; low + size < count; low += 2 * size) {
            int mid = low + size;
            int high = low + 2 * size;
            if (high > count) {
                high = count;
            }
            if (mid > count) {
                mid = count;
            }
            sort_merge_run(values, scratch, low, mid, high, cmp, stats);
        }
        size *= 2;
    }
}

static void sort_heap_sift(int *values, int count, int root, SortCmp cmp, SortStats *stats)
{
    while (1) {
        int largest = root;
        int left = 2 * root + 1;
        int right = 2 * root + 2;
        if (left < count) {
            if (stats != NULL) {
                stats->comparisons++;
            }
            if (sort_cmp_values(&values[left], &values[largest], cmp) > 0) {
                largest = left;
            }
        }
        if (right < count) {
            if (stats != NULL) {
                stats->comparisons++;
            }
            if (sort_cmp_values(&values[right], &values[largest], cmp) > 0) {
                largest = right;
            }
        }
        if (largest == root) {
            return;
        }
        sort_swap(&values[root], &values[largest], stats);
        root = largest;
    }
}

void sort_heap(int *values, int count, SortCmp cmp, SortStats *stats)
{
    int i;

    for (i = count / 2 - 1; i >= 0; i--) {
        sort_heap_sift(values, count, i, cmp, stats);
    }
    for (i = count - 1; i > 0; i--) {
        sort_swap(&values[0], &values[i], stats);
        sort_heap_sift(values, i, 0, cmp, stats);
    }
}

void sort_counting(int *values, int count, SortStats *stats)
{
    int counts[SORT_MAX + 1];
    int maximum = 0;
    int i;
    int position = 0;

    if (count <= 0) {
        return;
    }
    for (i = 0; i < count; i++) {
        if (values[i] > maximum) {
            maximum = values[i];
        }
    }
    if (maximum > SORT_MAX) {
        maximum = SORT_MAX;
    }
    for (i = 0; i <= maximum; i++) {
        counts[i] = 0;
    }
    for (i = 0; i < count; i++) {
        if (values[i] >= 0 && values[i] <= maximum) {
            counts[values[i]]++;
        }
    }
    for (i = 0; i <= maximum; i++) {
        int k;
        for (k = 0; k < counts[i]; k++) {
            values[position++] = i;
            if (stats != NULL) {
                stats->swaps++;
            }
        }
    }
    if (stats != NULL) {
        stats->comparisons += count;
    }
}

void sort_callback(void *base, int count, int size, SortCmp cmp)
{
    char *bytes = (char *)base;
    int i;
    int j;

    for (i = 1; i < count; i++) {
        for (j = i; j > 0; j--) {
            char *left = bytes + (j - 1) * size;
            char *right = bytes + j * size;
            if (cmp(left, right) <= 0) {
                break;
            }
            memcpy(left, right, (size_t)size);
        }
    }
}

int sort_same(const int *a, const int *b, int count)
{
    int i;

    for (i = 0; i < count; i++) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}
