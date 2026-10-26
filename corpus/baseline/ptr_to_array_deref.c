// @category: baseline
// #330：指向数组的指针 T(*)[N]——(*q)[i] 解引用寻址（修复前双重解引用
// TRAP 0x4）+ 写入左值 + 行指针算术（*(r+1) 跨行步进）+ q[i][j] 守成面
int g2d[2][3] = {{1, 2, 3}, {4, 5, 6}};

int main() {
    int (*q)[3] = &g2d[1];
    printf("%d %d %d\n", q[0][0], q[0][1], q[0][2]);
    printf("%d %d %d\n", (*q)[0], (*q)[1], (*q)[2]);
    printf("%d %d\n", **q, (*&*q)[2]);
    (*q)[1] = 40;
    printf("%d %d %d\n", g2d[0][1], g2d[1][1], (*q)[1]);
    int (*r)[3] = &g2d[0];
    printf("%d\n", (*(r + 1))[0]);
    return 0;
}
