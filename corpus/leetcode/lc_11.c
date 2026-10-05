#include <stdio.h>

int maxArea(int* height, int heightSize) {
    int left = 0;
    int right = heightSize - 1;
    int max_area = 0;
    while (left < right) {
        int width = right - left;
        int h;
        if (height[left] < height[right]) {
            h = height[left];
            left++;
        } else {
            h = height[right];
            right--;
        }
        int area = width * h;
        if (area > max_area) {
            max_area = area;
        }
    }
    return max_area;
}

int main() {
    int h1[] = {1, 8, 6, 2, 5, 4, 8, 3, 7};
    printf("%d\n", maxArea(h1, 9));

    int h2[] = {1, 1};
    printf("%d\n", maxArea(h2, 2));

    int h3[] = {4, 3, 2, 1, 4};
    printf("%d\n", maxArea(h3, 5));

    int h4[] = {1, 2, 1};
    printf("%d\n", maxArea(h4, 3));

    return 0;
}
