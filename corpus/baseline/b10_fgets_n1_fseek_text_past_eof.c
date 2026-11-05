/* B10 #434 / M23-A2+A3：fgets(buf,1) 返 buf 写 NUL 不置 eof 不吞行
 * （C11 §7.21.7.2）+ r+ 文本臂 fseek(SEEK_SET, 过尾) 不钳位（ftell=10、
 * 过尾写留 0 洞、size=12——修前钳到物理末尾 ftell=6/size=8）。真值 =
 * Win clang 22.1.4 UCRT 实测。 */
#include <stdio.h>
/* EOF 粘滞三形态 + n=1 + 过尾 fseek（B10 真值采证探针） */
int main(void) {
    /* F1: fread 恰满 */
    FILE *a = fopen("e6.bin", "wb");
    fwrite("ABCDEF", 1, 6, a);
    fclose(a);
    FILE *g1 = fopen("e6.bin", "rb");
    char buf[16];
    int n1 = fread(buf, 1, 6, g1);
    printf("F1 n=%d feof=%d\n", n1, feof(g1)); /* clang: n=6 feof=0 */
    int k = fread(buf, 1, 6, g1);
    printf("F4 n=%d feof=%d\n", k, feof(g1));  /* 过读: n=0 feof=1 */
    fclose(g1);
    /* F2: fgetc 末字节 */
    FILE *a2 = fopen("e2.bin", "wb");
    fwrite("xy", 1, 2, a2);
    fclose(a2);
    FILE *g2 = fopen("e2.bin", "rb");
    printf("F2 c=%d", fgetc(g2));
    printf(" %d", fgetc(g2));
    printf(" feof=%d\n", feof(g2));            /* clang: c=120 121 feof=0 */
    int c2 = fgetc(g2);
    printf("F2b c=%d feof=%d\n", c2, feof(g2)); /* c=-1 feof=1（拆语句防求值顺序污染） */
    fclose(g2);
    /* F3: fgets 停 \n 恰满 */
    FILE *a3 = fopen("e3.txt", "wb");
    fwrite("ab\n", 1, 3, a3);
    fclose(a3);
    FILE *g3 = fopen("e3.txt", "r");
    char *r = fgets(buf, 100, g3);
    printf("F3 r=%s feof=%d\n", r ? buf : "(null)", feof(g3)); /* clang: ab feof=0 */
    fclose(g3);
    /* S6: fgets(buf,1) */
    FILE *a4 = fopen("hi.txt", "wb");
    fwrite("hi", 1, 2, a4);
    fclose(a4);
    FILE *g4 = fopen("hi.txt", "r");
    buf[0] = 90;
    char *r4 = fgets(buf, 1, g4);
    printf("S6 ret=%s b0=%d feof=%d\n", r4 ? "buf" : "NULL", buf[0], feof(g4));
    r4 = fgets(buf, 8, g4);
    printf("S6b next=%s\n", r4 ? buf : "(null)"); /* hi 未消耗 */
    fclose(g4);
    /* F6: r+ 文本 fseek 过尾 */
    FILE *a5 = fopen("s6.bin", "wb");
    fwrite("ABCDEF", 1, 6, a5);
    fclose(a5);
    FILE *g5 = fopen("s6.bin", "r+");
    int sk = fseek(g5, 10, SEEK_SET);
    long tl = ftell(g5);
    fwrite("XY", 1, 2, g5);
    fclose(g5);
    FILE *g6 = fopen("s6.bin", "rb");
    int total = 0;
    while ((k = fread(buf, 1, 1, g6)) > 0) { total = total + k; }
    printf("F6 sk=%d tl=%ld size=%d\n", sk, tl, total); /* clang: 0 10 12 */
    fclose(g6);
    FILE *g7 = fopen("s6.bin", "rb");
    (void)fread(buf, 1, 12, g7);
    printf("F6b hole=");
    for (int i = 6; i < 10; i++) printf("%02X", (unsigned char)buf[i]);
    printf(" tail=%c%c\n", buf[10], buf[11]);    /* 00000000 tail=XY */
    fclose(g7);
    /* PR #486 审阅 P2-1：fgets 停因三形态（尾停置 / 恰满 n-1 不置 / \n 停不置） */
  FILE *nf = fopen("nf.txt", "wb"); fwrite("abc", 1, 3, nf); fclose(nf);
  FILE *ng = fopen("nf.txt", "r");
  char *ra = fgets(buf, 64, ng);
  printf("A1 r=%d feof=%d\n", ra != 0, feof(ng));
  fclose(ng);
  FILE *nh = fopen("nf.txt", "r");
  char *rb = fgets(buf, 3, nh);
  printf("A2 r=%d s=%s feof=%d\n", rb != 0, buf, feof(nh));
  fclose(nh);
  FILE *ni = fopen("nl.txt", "wb"); fwrite("ab\n", 1, 3, ni); fclose(ni);
  FILE *nj = fopen("nl.txt", "r");
  char *rc = fgets(buf, 64, nj);
  printf("A3 r=%d s=%s feof=%d\n", rc != 0, buf, feof(nj));
  fclose(nj);
  /* PR #486 审阅 P3：文本模式 fseek<->ftell round-trip（a\r\nb x6 物理 24 逻辑 18） */
  FILE *ck = fopen("crlf.txt", "wb");
  for (int q = 0; q < 6; q++) fwrite("ab\r\n", 1, 4, ck);
  fclose(ck);
  FILE *cl = fopen("crlf.txt", "r");
  fseek(cl, 15, SEEK_SET); printf("T1 tl=%ld\n", ftell(cl));
  fseek(cl, 30, SEEK_SET); printf("T2 tl=%ld\n", ftell(cl));
  fclose(cl);
  return 0;
}
