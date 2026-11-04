/* B10 #434 / M23-A1：EOF 粘滞位仅过读置位（C11 §7.21.10.2）——恰满
 * fread 不置、while(!feof) 不提前一圈退出（真机 clang: n=3 feof=0、
 * 独立 1B 循环 loops=4 got=3；串行形态恰满后 loops=1 got=0）*/
#include <stdio.h>
int main(void) {
    FILE *f = fopen("t.txt", "w");
    fwrite("abc", 1, 3, f);
    fclose(f);
    FILE *g = fopen("t.txt", "r");
    char buf[8];
    int n = fread(buf, 1, 3, g);
    printf("n=%d feof=%d\n", n, feof(g));
    int count = 0, got = 0;
    while (!feof(g)) { int k = fread(buf, 1, 1, g); count = count + 1; got = got + k; }
    printf("loops=%d got=%d\n", count, got);
    fclose(g);
    /* 独立 a1_loop 形态：从头 1B 读到尾——恰满三圈不置、第 4 圈过读才置 */
    FILE *h = fopen("t.txt", "r");
    int c2 = 0, g2 = 0;
    while (!feof(h)) { int k = fread(buf, 1, 1, h); c2 = c2 + 1; g2 = g2 + k; }
    printf("loops2=%d got2=%d\n", c2, g2);
    fclose(h);
    return 0;
}
