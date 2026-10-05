#include <stdio.h>

void sort(int* intervals, int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            int a0 = intervals[j * 2];
            int a1 = intervals[j * 2 + 1];
            int b0 = intervals[(j + 1) * 2];
            int b1 = intervals[(j + 1) * 2 + 1];
            if (a0 > b0) {
                intervals[j * 2] = b0;
                intervals[j * 2 + 1] = b1;
                intervals[(j + 1) * 2] = a0;
                intervals[(j + 1) * 2 + 1] = a1;
            }
        }
    }
}

int main() {
    int intervals[] = {1, 3, 2, 6, 8, 10, 15, 18};
    int n = 4;
    sort(intervals, n);

    int merged[20];
    int m = 0;
    merged[0] = intervals[0];
    merged[1] = intervals[1];

    for (int i = 1; i < n; i++) {
        int start = intervals[i * 2];
        int end = intervals[i * 2 + 1];
        if (start <= merged[m * 2 + 1]) {
            if (end > merged[m * 2 + 1]) {
                merged[m * 2 + 1] = end;
            }
        } else {
            m++;
            merged[m * 2] = start;
            merged[m * 2 + 1] = end;
        }
    }
    m++;

    for (int i = 0; i < m; i++) {
        printf("[%d,%d]\n", merged[i * 2], merged[i * 2 + 1]);
    }

    return 0;
}
