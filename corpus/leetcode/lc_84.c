#include <stdio.h>

int largestRectangleArea(int* heights, int heightsSize) {
    int stack[100000];
    int top = -1;
    int max_area = 0;
    for (int i = 0; i <= heightsSize; i++) {
        int h = (i == heightsSize) ? 0 : heights[i];
        while (top >= 0 && h < heights[stack[top]]) {
            int height = heights[stack[top--]];
            int width = (top >= 0) ? (i - stack[top] - 1) : i;
            int area = height * width;
            if (area > max_area) {
                max_area = area;
            }
        }
        stack[++top] = i;
    }
    return max_area;
}

int main() {
    int h1[] = {2, 1, 5, 6, 2, 3};
    printf("%d\n", largestRectangleArea(h1, 6));

    int h2[] = {2, 4};
    printf("%d\n", largestRectangleArea(h2, 2));

    int h3[] = {6, 4, 2, 0, 3, 2, 0, 3, 1, 4, 5, 3, 2, 7, 5, 3, 0, 1, 2, 1, 3, 4, 6, 8, 1, 3};
    printf("%d\n", largestRectangleArea(h3, 26));

    return 0;
}
