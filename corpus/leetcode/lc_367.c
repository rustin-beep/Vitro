#include <stdio.h>

int isPerfectSquare(int num) {
    int left = 1, right = num;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        int div = num / mid;
        if (div == mid && num % mid == 0) return 1;
        if (div < mid) right = mid - 1;
        else left = mid + 1;
    }
    return 0;
}

int main(void) {
    printf("%d\n", isPerfectSquare(16));
    printf("%d\n", isPerfectSquare(14));
    printf("%d\n", isPerfectSquare(1));
    printf("%d\n", isPerfectSquare(2147395600));
    return 0;
}
