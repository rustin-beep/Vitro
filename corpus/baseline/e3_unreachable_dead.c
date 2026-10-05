// @category: baseline
// E3：C23 unreachable()——严格死代码（return 之后）中的调用不执行、不影响
// 输出（Clang 丢弃不可达代码，链接无符号问题）；执行到则教学 trap（单测覆盖）
#include <stdio.h>
#include <stddef.h>
int main() {
    int x = 0;
    printf("before %d\n", x);
    if (x != 0) {
        printf("impossible\n");
    }
    return 0;
    unreachable();
}
