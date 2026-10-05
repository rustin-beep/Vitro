#include <stdio.h>

int trap(int* height, int heightSize) {
    if (heightSize == 0) {
        return 0;
    }
    int left = 0;
    int right = heightSize - 1;
    int left_max = 0;
    int right_max = 0;
    int water = 0;
    while (left < right) {
        if (height[left] < height[right]) {
            if (height[left] >= left_max) {
                left_max = height[left];
            } else {
                water += left_max - height[left];
            }
            left++;
        } else {
            if (height[right] >= right_max) {
                right_max = height[right];
            } else {
                water += right_max - height[right];
            }
            right--;
        }
    }
    return water;
}

int main() {
    int h1[] = {0, 1, 0, 2, 1, 0, 1, 3, 2, 1, 2, 1};
    printf("%d\n", trap(h1, 12));

    int h2[] = {4, 2, 0, 3, 2, 5};
    printf("%d\n", trap(h2, 6));

    return 0;
}
