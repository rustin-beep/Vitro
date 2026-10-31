#include <stdio.h>
#include <string.h>

/* ds 批 2026-10-31：\xHH >= 0x80 转义的 NUL 终止与 strlen/%s 路径锚。
 * 已知差异（known_direct 登记）：\xff 码点经 UTF-8 通道落 C3 BF 双字节
 * （clang 单字节 FF）⇒ sizeof=11 vs 10、strlen=10 vs 9——值差面；
 * 尺寸/字节两层同口径保证 NUL 终止符在场，strlen/%s 不越界（回归即
 * digest 变红：任何人改回 Latin-1 计长，NUL 被挤、len 读到相邻内存）。 */
char g[] = "\x4Z\x41Y\012B\7C\xff";

/* 审阅批 2026-10-31：显式尺寸恰满形态（PR #401 P1-2 反例锚）——
 * vitro 口径 "\xff" 字节层 2（C3 BF）恰等于数组尺寸 2，NUL 无空间
 * 被挤（C11 §6.7.9p14 合法形态）⇒ strlen 越界（b_nul=0）+ W3008
 * 误警（判定把 NUL 计入——与 clang 判据同款，误警同为值差连带）；
 * clang 口径单字节 FF + NUL 恰好放下：NUL 在场（b_nul=1）零警。
 * 判定输出形态：不打印越界内容——全局相邻布局改动不至 digest 漂移。
 * 治本（单字节值语义）挂 #66 尾巴（词法层转义通道，载体改 Bytes）。 */
char b[2] = "\xff";

int main(void) {
    printf("sizeof=%d\n", (int)sizeof(g));
    for (int i = 0; i < (int)sizeof(g); i++)
        printf("%d ", (int)(unsigned char)g[i]);
    printf("\nlen=%d\n", (int)strlen(g));
    printf("[%s]|end\n", g);
    printf("b_sizeof=%d\n", (int)sizeof(b));
    printf("b_nul=%d\n", (int)(strlen(b) <= (size_t)sizeof(b)));
    printf("b_bytes=%d %d\n", (int)(unsigned char)b[0],
           (int)(unsigned char)b[1]);
    return 0;
}
