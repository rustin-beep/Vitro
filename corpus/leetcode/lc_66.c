#include <stdio.h>
#include <stdlib.h>

int* plusOne(int* digits, int digitsSize, int* returnSize) {
    int* result = (int*)malloc(sizeof(int) * (digitsSize + 1));
    int carry = 1;
    int len = 0;
    for (int i = digitsSize - 1; i >= 0; i--) {
        int sum = digits[i] + carry;
        result[digitsSize - 1 - i] = sum % 10;
        carry = sum / 10;
        len++;
    }
    if (carry) {
        result[len++] = carry;
    }
    for (int i = 0; i < len / 2; i++) {
        int tmp = result[i];
        result[i] = result[len - 1 - i];
        result[len - 1 - i] = tmp;
    }
    *returnSize = len;
    return result;
}

int main() {
    int digits1[] = {1, 2, 3};
    int returnSize1 = 0;
    int* r1 = plusOne(digits1, 3, &returnSize1);
    for (int i = 0; i < returnSize1; i++) {
        if (i > 0) printf(" ");
        printf("%d", r1[i]);
    }
    printf("\n");
    free(r1);

    int digits2[] = {4, 3, 2, 1};
    int returnSize2 = 0;
    int* r2 = plusOne(digits2, 4, &returnSize2);
    for (int i = 0; i < returnSize2; i++) {
        if (i > 0) printf(" ");
        printf("%d", r2[i]);
    }
    printf("\n");
    free(r2);

    int digits3[] = {9};
    int returnSize3 = 0;
    int* r3 = plusOne(digits3, 1, &returnSize3);
    for (int i = 0; i < returnSize3; i++) {
        if (i > 0) printf(" ");
        printf("%d", r3[i]);
    }
    printf("\n");
    free(r3);

    return 0;
}
