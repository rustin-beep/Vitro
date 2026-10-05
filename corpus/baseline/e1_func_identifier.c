// @category: baseline
// C99（E1 B 档）：__func__ 预定义标识符
#include <stdio.h>
int helper(void) {
    printf("in %s\n", __func__);
    return 1;
}
int main() {
    printf("in %s\n", __func__);
    return helper();
}
