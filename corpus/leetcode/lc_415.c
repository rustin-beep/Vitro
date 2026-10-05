#include <stdio.h>
#include <string.h>

char* addStrings(char* num1, char* num2) {
    int i = strlen(num1) - 1;
    int j = strlen(num2) - 1;
    int carry = 0;
    static char res[10000];
    int k = 0;
    while (i >= 0 || j >= 0 || carry) {
        int sum = carry;
        if (i >= 0) sum += num1[i--] - '0';
        if (j >= 0) sum += num2[j--] - '0';
        res[k++] = (sum % 10) + '0';
        carry = sum / 10;
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
    printf("%s\n", addStrings("11", "123"));
    printf("%s\n", addStrings("456", "77"));
    printf("%s\n", addStrings("0", "0"));
    return 0;
}
