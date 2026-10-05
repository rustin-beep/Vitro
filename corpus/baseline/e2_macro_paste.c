// @category: baseline
// E2：## token 拼接（结果必须为单个合法 token）
#include <stdio.h>
#define GLUE(a, b) a##b
#define PIPE(a, b) a##b
int main() {
    int GLUE(my, var) = 42;
    int PIPE(other, one) = 8;
    printf("%d %d\n", myvar, otherone);
    return 0;
}
