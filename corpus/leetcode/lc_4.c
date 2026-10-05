#include <stdio.h>

double findMedianSortedArrays(int* nums1, int nums1Size, int* nums2, int nums2Size) {
    int total = nums1Size + nums2Size;
    int mid = total / 2;
    int i = 0;
    int j = 0;
    int prev = 0;
    int curr = 0;
    for (int k = 0; k <= mid; k++) {
        prev = curr;
        if (i < nums1Size && (j >= nums2Size || nums1[i] < nums2[j])) {
            curr = nums1[i++];
        } else {
            curr = nums2[j++];
        }
    }
    if (total % 2 == 0) {
        return (prev + curr) / 2.0;
    } else {
        return curr;
    }
}

int main() {
    int a1[] = {1, 3};
    int b1[] = {2};
    printf("%.5f\n", findMedianSortedArrays(a1, 2, b1, 1));

    int a2[] = {1, 2};
    int b2[] = {3, 4};
    printf("%.5f\n", findMedianSortedArrays(a2, 2, b2, 2));

    int a3[] = {};
    int b3[] = {1};
    printf("%.5f\n", findMedianSortedArrays(a3, 0, b3, 1));

    return 0;
}
