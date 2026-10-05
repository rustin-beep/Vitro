#include <stdio.h>
int plusOne(int* digits, int digitsSize, int* out) {
    int c = 1;
    for (int i = digitsSize - 1; i >= 0; i--) {
        int s = digits[i] + c;
        out[i + 1] = s % 10;
        c = s / 10;
    }
    if (c) {
        out[0] = 1;
        return digitsSize + 1;
    }
    for (int i = 0; i < digitsSize; i++) out[i] = out[i + 1];
    return digitsSize;
}
int main() {
    int digits[] = {1, 2, 3};
    int out[4];
    int k = plusOne(digits, 3, out);
    for (int i = 0; i < k; i++) printf("%d", out[i]);
    printf("\n");
    return 0;
}
