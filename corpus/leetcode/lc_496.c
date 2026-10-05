#include <stdio.h>
#include <stdlib.h>

int* nextGreaterElement(int* nums1, int nums1Size, int* nums2, int nums2Size, int* returnSize) {
    int* res = (int*)malloc(nums1Size * sizeof(int));
    *returnSize = nums1Size;
    for (int i = 0; i < nums1Size; i++) {
        res[i] = -1;
        int found = 0;
        for (int j = 0; j < nums2Size; j++) {
            if (nums2[j] == nums1[i]) found = 1;
            else if (found && nums2[j] > nums1[i]) {
                res[i] = nums2[j];
                break;
            }
        }
    }
    return res;
}

int main(void) {
    int nums1[] = {4,1,2};
    int nums2[] = {1,3,4,2};
    int size = 0;
    int* r = nextGreaterElement(nums1, 3, nums2, 4, &size);
    for (int i = 0; i < size; i++) printf("%d ", r[i]);
    printf("\n");
    free(r);

    int nums3[] = {2,4};
    int nums4[] = {1,2,3,4};
    r = nextGreaterElement(nums3, 2, nums4, 4, &size);
    for (int i = 0; i < size; i++) printf("%d ", r[i]);
    printf("\n");
    free(r);
    return 0;
}
