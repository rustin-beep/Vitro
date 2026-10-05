// @category: baseline
// E3：static_assert / _Static_assert 双拼写、双参/单参、编译期真求值
#include <stdio.h>
static_assert(1 + 1 == 2, "math holds");
_Static_assert(sizeof(int) == 4);
static_assert(2 > 1);
int main() {
    printf("asserts pass\n");
    return 0;
}
