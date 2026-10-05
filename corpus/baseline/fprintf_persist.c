// @category: baseline
// DIFF-LIB-FPRINTF-01 锚（2026-10-05 批二-a）：fprintf 到 fopen 自建文件落盘并 fread 读回（旧形态静默转 stdout 系 oracle 照搬；自建文件两侧同为新建——非预设文件域，不撞 vfs 预设 known）
#include <stdio.h>
int main() {
    FILE* f = fopen("out_b2a.txt", "w");
    if (!f) { printf("open-fail\n"); return 1; }
    fprintf(f, "v=%d line\n", 7);
    fclose(f);
    FILE* r = fopen("out_b2a.txt", "r");
    if (!r) { printf("reopen-fail\n"); return 2; }
    char buf[32] = {0};
    fread(buf, 1, 12, r);
    fclose(r);
    printf("[%s]\n", buf);
    return 0;
}
