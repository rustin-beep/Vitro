#include <stdio.h>
#include <string.h>

/* ds 批 2026-10-31：\xHH >= 0x80 转义的 NUL 终止与 strlen/%s 路径锚。
 * 已知差异（known_direct 登记）：\xff 码点经 UTF-8 通道落 C3 BF 双字节
 * （clang 单字节 FF）⇒ sizeof=11 vs 10、strlen=10 vs 9——值差面；
 * 尺寸/字节两层同口径保证 NUL 终止符在场，strlen/%s 不越界（回归即
 * digest 变红：任何人改回 Latin-1 计长，NUL 被挤、len 读到相邻内存）。 */
char g[] = "\x4Z\x41Y\012B\7C\xff";

int main(void) {
    printf("sizeof=%d\n", (int)sizeof(g));
    for (int i = 0; i < (int)sizeof(g); i++)
        printf("%d ", (int)(unsigned char)g[i]);
    printf("\nlen=%d\n", (int)strlen(g));
    printf("[%s]|end\n", g);
    return 0;
}
