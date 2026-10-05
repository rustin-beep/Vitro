#include <stdio.h>

void printIntersection(int* nums1, int nums1Size, int* nums2, int nums2Size) {
    int seen[1001] = {0};
    for (int i = 0; i < nums1Size; i++) {
        seen[nums1[i]] = 1;
    }
    for (int i = 0; i < nums2Size; i++) {
        if (seen[nums2[i]] == 1) {
            printf("%d ", nums2[i]);
            seen[nums2[i]] = 2;
        }
    }
    printf("\n");
}

int main(void) {
    int a[] = {1, 2, 2, 1};
    int b[] = {2, 2};
    printIntersection(a, 4, b, 2);

    int c[] = {4, 9, 5};
    int d[] = {9, 4, 9, 8, 4};
    printIntersection(c, 3, d, 5);

    return 0;
}
