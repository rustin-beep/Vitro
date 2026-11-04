// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M23 a3「二进制臂 fseek 超尾写」同形面（速查表 F6 行：rb+ 臂
// ftell=10/size=12/洞 00/XY@10 双侧完全同形；文本臂钳回物理末尾的差异另属 F6 分叉格，不入本文件）。
// 来源：tmp/review_v2_M23/probes/a3_fseek_bin.c（文件名用 m23b 专用名避开 VFS 预置撞名口径）
#include <stdio.h>
int main(void) {
    FILE *a = fopen("m23b.bin", "wb");
    fwrite("abcdef", 1, 6, a);
    fclose(a);
    FILE *f = fopen("m23b.bin", "rb+");
    int rc = fseek(f, 10, SEEK_SET);
    long p = ftell(f);
    printf("rc=%d ftell=%ld\n", rc, p);
    fwrite("XY", 1, 2, f);
    fclose(f);
    FILE *g = fopen("m23b.bin", "rb");
    fseek(g, 0, SEEK_END);
    long sz = ftell(g);
    rewind(g);
    char buf[32];
    int n = fread(buf, 1, 20, g);
    printf("size=%ld n=%d\n", sz, n);
    for (int i = 0; i < n; i++) {
        printf("%d:%02x ", i, (unsigned char)buf[i]);
    }
    printf("\n");
    fclose(g);
    return 0;
}
