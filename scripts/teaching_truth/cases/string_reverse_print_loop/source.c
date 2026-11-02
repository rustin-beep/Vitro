#include <stdio.h>

/* 字符串反转 + 逐字符打印循环（M34b A6 红例载体）：打印循环
   `for (i = 0; i < len; i++) printf("%c", str[i]);` 命中 string_reverse
   推断器判据 starts_with("for ") && contains("len") 被标 swap。
   真值：打印循环无交换语义，不得产 swap 帧。 */
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
    for (int i = 0; i < len; i++) {
        printf("%c", str[i]);
    }
    printf("\n");
}

int main() {
    char str[] = "hello";
    reverseString(str);
    return 0;
}
