/* 病 15 批 B（#61）：fgets(b, n, stdin) 接 InputState（与 scanf/getchar 同
 * 游标）——修复前 stdin 宏折叠 fd=0 恒空读。 */
#include <stdio.h>

int main() {
    char b[8];
    char* r = fgets(b, 8, stdin);
    printf("r=%d b=%s", r != 0, b);
    return 0;
}
