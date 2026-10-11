#include <stdio.h>

// @category: #71 第三梯队病 23/24——scanf 字段宽度（修复前 %3d 读穿）+
// %f token 指数形态（修复前 "1e5" 读 1 游标停 'e'）。stdin 配对 .in。

int main() {
    int a, b;
    int n1 = scanf("%3d%2d", &a, &b);
    printf("n1=%d a=%d b=%d\n", n1, a, b);
    float f = -1.0;
    int n3 = scanf("%f", &f);
    printf("n3=%d f=%f\n", n3, f);
    char buf[16];
    int n2 = scanf("%10s", buf);
    buf[10] = 0;
    printf("n2=%d s=%s\n", n2, buf);
    return 0;
}
