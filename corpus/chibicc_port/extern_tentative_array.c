#include <stdio.h>

// @category: chibicc port——extern 前置声明族（extern.c 主题）：extern 标量前置
// + extern 不完整数组前置（tentative）→ 同翻译单元内定义补全；写读双向验证
// 前置声明与定义是同一对象（非双份拷贝）。clang 真值：43 1 30 4。

extern int shared_counter;
extern int table[];

int shared_counter = 42;
int table[4] = {1, 2, 3, 4};

int main() {
    shared_counter += 1;
    table[2] = 30;
    printf("%d %d %d %d\n", shared_counter, table[0], table[2], table[3]);
    return 0;
}
