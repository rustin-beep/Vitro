// @category: baseline
// DIFF-LIB-FPRINTF-01 锚（2026-10-05 批二-a；批二-b 扩 %c 高位字节形态——
// P3-2 验证：fprintf 落盘通道 %c 与 printf 同为单字节直出，Clang 0xC8）
#include <stdio.h>
int main() {
    FILE* f = fopen("out_b2a.txt", "w");
    if (!f) { printf("open-fail\n"); return 1; }
    fprintf(f, "v=%d line\n", 7);
    fprintf(f, "high:[%c]\n", 200);
    fclose(f);
    FILE* r = fopen("out_b2a.txt", "r");
    if (!r) { printf("reopen-fail\n"); return 2; }
    char buf[48] = {0};
    int total = 0, n;
    while ((n = fread(buf + total, 1, 40, r)) > 0) total += n;
    fclose(r);
    printf("[%s]\n", buf);
    return 0;
}
