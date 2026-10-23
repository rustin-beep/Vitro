// file_fopen_modes.c —— fopen 读写族模式面（r+/w+/a/a+ + fseek 往返 + b 位）
// PR #280 审阅 P2-2 处方形态：12 形态家族此前零语料承载（corpus 的 fopen
// 模式串只有 w/r/rb/wb——A2-b 形状单一，差分闸结构性看不见；同根因两
// 实现点的 wbtest 锚见 vfs_fwrite_append_writes_at_end）。全路径检查返回
// 值（去 UB——fclose/fread 不得在 NULL 路径调用）；文件读写全在同进程
// VFS/真 FS 内闭环，两侧行为一致。
// 预期：pass=5 final=XYZW
#include <stdio.h>
#include <string.h>
int main(void) {
    char buf[32];
    int pass = 0;
    /* w 建文件 + 写底稿 */
    FILE *w = fopen("modes_probe.txt", "w");
    if (!w) { printf("w-fail\n"); return 1; }
    fputs("12345", w);
    fclose(w);
    /* r+ 读改写：读全量、seek 回头部覆盖写 */
    FILE *rp = fopen("modes_probe.txt", "r+");
    if (!rp) { printf("rplus-fail\n"); return 1; }
    memset(buf, 0, sizeof buf);
    if (fread(buf, 1, 5, rp) == 5 && strcmp(buf, "12345") == 0) pass++;
    fseek(rp, 0, SEEK_SET);
    fputs("AB", rp);
    fclose(rp);
    /* w+ 清空重建 + 同 fd 读回 */
    FILE *wp = fopen("modes_probe.txt", "w+");
    if (!wp) { printf("wplus-fail\n"); return 1; }
    fputs("XY", wp);
    fseek(wp, 0, SEEK_SET);
    memset(buf, 0, sizeof buf);
    if (fread(buf, 1, 4, wp) == 2 && strcmp(buf, "XY") == 0) pass++;
    fclose(wp);
    /* a 追加：fseek 不改写位（写恒末尾）*/
    FILE *a = fopen("modes_probe.txt", "a");
    if (!a) { printf("a-fail\n"); return 1; }
    fseek(a, 0, SEEK_SET);
    fputs("Z", a);
    fclose(a);
    /* a+ 读起点在文件头 + 写恒末尾 */
    FILE *ap = fopen("modes_probe.txt", "a+");
    if (!ap) { printf("aplus-fail\n"); return 1; }
    memset(buf, 0, sizeof buf);
    if (fread(buf, 1, 8, ap) == 3 && strcmp(buf, "XYZ") == 0) pass++;
    fseek(ap, 0, SEEK_SET);
    fputs("W", ap);
    fclose(ap);
    /* rb+ 二进制位：字节原样（无 CRLF 伸缩路径）*/
    FILE *wb = fopen("modes_probe.bin", "wb");
    if (!wb) { printf("wb-fail\n"); return 1; }
    fputc('P', wb);
    fclose(wb);
    FILE *rbc = fopen("modes_probe.bin", "rb+");
    if (!rbc) { printf("rbplus-fail\n"); return 1; }
    memset(buf, 0, sizeof buf);
    if (fread(buf, 1, 2, rbc) == 1 && buf[0] == 'P') pass++;
    fclose(rbc);
    /* 终态校验（追加链完整：XY→XYZ→XYZW）*/
    FILE *fin = fopen("modes_probe.txt", "r");
    if (!fin) { printf("final-fail\n"); return 1; }
    memset(buf, 0, sizeof buf);
    if (fread(buf, 1, 16, fin) == 4 && strcmp(buf, "XYZW") == 0) pass++;
    fclose(fin);
    printf("pass=%d final=%s\n", pass, buf);
    return 0;
}
