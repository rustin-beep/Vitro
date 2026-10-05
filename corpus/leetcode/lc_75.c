#include <stdio.h>

void sortColors(int* nums, int numsSize) {
    int low = 0;
    int mid = 0;
    int high = numsSize - 1;
    while (mid <= high) {
        if (nums[mid] == 0) {
            int tmp = nums[low];
            nums[low] = nums[mid];
            nums[mid] = tmp;
            low++;
            mid++;
        } else if (nums[mid] == 1) {
            mid++;
        } else {
            int tmp = nums[mid];
            nums[mid] = nums[high];
            nums[high] = tmp;
            high--;
        }
    }
}

void print_arr(int* nums, int n) {
    for (int i = 0; i < n; i++) {
        printf("%d", nums[i]);
        if (i + 1 < n) {
            printf(" ");
        }
    }
    printf("\n");
}

int main() {
    int a1[] = {2, 0, 2, 1, 1, 0};
    sortColors(a1, 6);
    print_arr(a1, 6);

    int a2[] = {2, 0, 1};
    sortColors(a2, 3);
    print_arr(a2, 3);

    int a3[] = {0};
    sortColors(a3, 1);
    print_arr(a3, 1);

    int a4[] = {1, 2, 0};
    sortColors(a4, 3);
    print_arr(a4, 3);

    return 0;
}
