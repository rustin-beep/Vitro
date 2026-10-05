#include <stdio.h>

void reverseString(char* s, int sSize) {
    int left = 0, right = sSize - 1;
    while (left < right) {
        char tmp = s[left];
        s[left] = s[right];
        s[right] = tmp;
        left++;
        right--;
    }
}

int main(void) {
    char s1[] = "hello";
    reverseString(s1, 5);
    printf("%s\n", s1);

    char s2[] = "Hannah";
    reverseString(s2, 6);
    printf("%s\n", s2);

    char s3[] = "a";
    reverseString(s3, 1);
    printf("%s\n", s3);

    return 0;
}
