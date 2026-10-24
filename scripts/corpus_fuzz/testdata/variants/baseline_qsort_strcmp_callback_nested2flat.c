// @category: baseline
// #136 缺陷 3 qsort 形态锚（2026-10-17）：strcmp 强转后作 qsort 比较
// 回调——issue 触发文件的核心形态；Host 编码段指针经 CallPtr 间接
// 调用（含参数转发）。
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    char *words[] = { "pear", "apple", "orange" };
    qsort(words, 3, sizeof(char *),
          (int (*)(const void *, const void *))strcmp);
    for (int i = 0; i < 3; i++) printf("%s ", words[i]);
    printf("\n");
    return 0;
}
