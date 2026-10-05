#include <stdio.h>
#include <stdio.h>

int containsNearbyDuplicate(int* nums, int numsSize, int k) {
    for (int i = 0; i < numsSize; i++) {
        int limit = i + k;
        if (limit >= numsSize) limit = numsSize - 1;
        for (int j = i + 1; j <= limit; j++) {
            if (nums[i] == nums[j]) return 1;
        }
    }
    return 0;
}

int main(void) {
    int a[] = {1, 2, 3, 1};
    printf("%d\n", containsNearbyDuplicate(a, 4, 3));

    int b[] = {1, 0, 1, 1};
    printf("%d\n", containsNearbyDuplicate(b, 4, 1));

    int c[] = {1, 2, 3, 1, 2, 3};
    printf("%d\n", containsNearbyDuplicate(c, 6, 2));

    return 0;
}
