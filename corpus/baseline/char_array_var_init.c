/*
 * @category: array_init
 * char 局部数组用变量做聚合初始化器（#173 修复锚，2026-10-18）：
 * 旧一维 char 快径 flatten_init_list 对变量元素落 _=>0 兜底——
 * char b[2]={c,'\0'} 整串写 0 变空串（词法分析器 op_buf 形态）。
 * 修 = 全字面量才走快径，含变量分流 flat 路径（char 按 1 字节 store）。
 */
#include <stdio.h>

int main(void) {
    char c = '(';
    char b[2] = {c, '\0'};
    printf("[%s]\n", b);

    char d = 'X';
    char e[3] = {c, d, '\0'};
    printf("[%s]\n", e);

    int x = 5;
    int a[3] = {x, x + 1, 0};
    printf("%d %d %d\n", a[0], a[1], a[2]);

    char lit[2] = {'(', '\0'};
    printf("[%s]\n", lit);

    char mix[3] = {'a', c, 0};
    printf("[%s]\n", mix);
    return 0;
}
