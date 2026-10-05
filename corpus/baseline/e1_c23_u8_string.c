// @category: baseline
// C23（E1）：u8 前缀字符串（教学子集差异：无独立 char8_t，按 char[] 处理）
#include <stdio.h>
#include <string.h>
int main() {
    printf("%s %d\n", u8"hi", (int)strlen(u8"abc"));
    return 0;
}
