// @category: baseline
// C23（E1）：typeof_unqual —— 推导并剥离顶层限定符
#include <stdio.h>
int main() {
    const int ci = 9;
    __typeof_unqual__(ci) x = ci + 1;
    x = 42;
    __typeof__(ci) y = ci;
    printf("%d %d\n", x, y);
    return 0;
}
