#include <stdio.h>
int mySqrt(int x) {
    if (x < 2) return x;
    int lo = 1, hi = x / 2;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        if (mid <= x / mid && (mid + 1) > x / (mid + 1)) return mid;
        if (mid < x / mid) lo = mid + 1;
        else hi = mid - 1;
    }
    return lo;
}
int main() {
    printf("%d\n", mySqrt(8));
    return 0;
}
