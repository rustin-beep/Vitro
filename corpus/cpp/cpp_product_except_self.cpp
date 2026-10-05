#include <stdio.h>
int main() {
    int nums[] = {1, 2, 3, 4};
    int n = 4;
    int out[4];
    out[0] = 1;
    for (int i = 1; i < n; i++) out[i] = out[i-1] * nums[i-1];
    int r = 1;
    for (int i = n - 1; i >= 0; i--) { out[i] = out[i] * r; r = r * nums[i]; }
    for (int i = 0; i < n; i++) printf("%d\n", out[i]);
    return 0;
}
