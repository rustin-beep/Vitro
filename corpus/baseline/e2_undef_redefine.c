// @category: baseline
// E2：#undef 与重定义
#include <stdio.h>
#define LEVEL 1
#undef LEVEL
#define LEVEL 7
int main() {
    printf("%d\n", LEVEL);
    return 0;
}
