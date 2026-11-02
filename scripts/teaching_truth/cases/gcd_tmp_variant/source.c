#include <stdio.h>

/* 教科书 t 暂存形态（M34b A1 红例载体）：余数先落 t 再轮转——
   与 templates/gcd 的 `b = a % b` 单行形态同算法不同写法。 */
int gcd(int a, int b) {
    while (b != 0) {
        int t = a % b;
        a = b;
        b = t;
    }
    return a;
}

int main() {
    int a = 48, b = 18;
    printf("%d\n", gcd(a, b));
    return 0;
}
