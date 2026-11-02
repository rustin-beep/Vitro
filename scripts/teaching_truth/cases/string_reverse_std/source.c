#include <stdio.h>

/* 正例主干：函数形态的教科书字符串反转（templates/stringReverse 全在 main
   内——detect 按函数名命中 string_reverse，无函数名零标注，故自带函数版）。 */
void reverseString(char str[]) {
    int len = 0;
    while (str[len] != '\0') {
        len++;
    }
    for (int i = 0; i < len / 2; i++) {
        char temp = str[i];
        str[i] = str[len - i - 1];
        str[len - i - 1] = temp;
    }
}

int main() {
    char str[] = "hello";
    reverseString(str);
    printf("%s\n", str);
    return 0;
}
