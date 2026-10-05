#include <stdio.h>

void swap(int* a, int* b) {
    int tmp = *a;
    *a = *b;
    *b = tmp;
}

void reverse(int* nums, int left, int right) {
    while (left < right) {
        swap(&nums[left], &nums[right]);
        left++;
        right--;
    }
}

void nextPermutation(int* nums, int numsSize) {
    int i = numsSize - 2;
    while (i >= 0 && nums[i] >= nums[i + 1]) {
        i--;
    }
    if (i >= 0) {
        int j = numsSize - 1;
        while (j >= 0 && nums[j] <= nums[i]) {
            j--;
        }
        swap(&nums[i], &nums[j]);
    }
    reverse(nums, i + 1, numsSize - 1);
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
    int a1[] = {1, 2, 3};
    nextPermutation(a1, 3);
    print_arr(a1, 3);

    int a2[] = {3, 2, 1};
    nextPermutation(a2, 3);
    print_arr(a2, 3);

    int a3[] = {1, 1, 5};
    nextPermutation(a3, 3);
    print_arr(a3, 3);

    int a4[] = {1, 5, 8, 4, 7, 6, 5, 3, 1};
    nextPermutation(a4, 9);
    print_arr(a4, 9);

    return 0;
}
