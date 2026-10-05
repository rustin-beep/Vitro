// @category: baseline
// C89（E1 B 档）：相邻字符串字面量拼接
#include <stdio.h>
#include <string.h>
int main() {
    printf("%s\n", "Hello, " "World" "!");
    char s[] = "ab" "\t" "cd";
    printf("%d %s\n", (int)strlen(s), s);
    return 0;
}
