#include <stdio.h>

void printSubset(int* nums, int n, int mask) {
    printf("[");
    int first = 1;
    for (int i = 0; i < n; i++) {
        if (mask & (1 << i)) {
            if (!first) {
                printf(",");
            }
            printf("%d", nums[i]);
            first = 0;
        }
    }
    printf("]");
}

int main() {
    int nums[] = {1, 2, 3};
    int n = 3;
    int total = 1 << n;

    for (int mask = 0; mask < total; mask++) {
        printSubset(nums, n, mask);
        printf("\n");
    }

    return 0;
}
