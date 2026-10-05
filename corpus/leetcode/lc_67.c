#include <stdio.h>
#include <string.h>

char* addBinary(char* a, char* b) {
    int i = strlen(a) - 1;
    int j = strlen(b) - 1;
    int carry = 0;
    static char res[1000];
    int k = 0;
    while (i >= 0 || j >= 0 || carry) {
        int sum = carry;
        if (i >= 0) sum += a[i--] - '0';
        if (j >= 0) sum += b[j--] - '0';
        res[k++] = (sum % 2) + '0';
        carry = sum / 2;
    }
    res[k] = '\0';
    for (int left = 0, right = k - 1; left < right; left++, right--) {
        char tmp = res[left];
        res[left] = res[right];
        res[right] = tmp;
    }
    return res;
}

int main(void) {
    printf("%s\n", addBinary("11", "1"));
    printf("%s\n", addBinary("1010", "1011"));
    return 0;
}
