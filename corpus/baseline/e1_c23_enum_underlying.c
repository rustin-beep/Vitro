// @category: baseline
// C23（E1）：enum 底层类型声明
#include <stdio.h>
enum Small : unsigned char { S1 = 200, S2 = 255 };
enum Big : long long { B1 = 0, B2 = 5000000000LL };
int main() {
    printf("%d %d %d %lld\n", (int)S2, (int)sizeof(enum Small), (int)B2, B2);
    return 0;
}
