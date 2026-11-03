// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M23「EOF 族同形面」（速查表 F4/F7 行）——过读一次后 feof=1 与
// 短读（fread 请求超过剩余）置 feof=1 双侧一致；恰满即置位的分叉面（F1-F3/F5）不入本文件（修复后入库批）。
// 来源：tmp/review_v2_M23/probes/a1_fgetc.c（过读段）+ 速查表 F7 口径
#include <stdio.h>
int main(void) {
    FILE *a = fopen("m23over.txt", "w");
    fwrite("ab", 1, 2, a);
    fclose(a);
    FILE *f = fopen("m23over.txt", "r");
    int c1 = fgetc(f);
    int c2 = fgetc(f);
    int c3 = fgetc(f);                    // 过读一次 → EOF
    printf("c1=%d c2=%d c3=%d eof_after_over=%d\n", c1, c2, c3, feof(f));
    fclose(f);
    FILE *h = fopen("m23short.txt", "w");
    fwrite("abcdef", 1, 6, h);
    fclose(h);
    FILE *s = fopen("m23short.txt", "r");
    char buf[32];
    int n = fread(buf, 1, 100, s);        // 短读（请求 100 > 剩 6）→ feof=1（F7：非病）
    printf("n=%d eof_after_short=%d\n", n, feof(s));
    fclose(s);
    return 0;
}
