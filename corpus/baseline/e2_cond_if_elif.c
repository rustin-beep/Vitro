// @category: baseline
// E2：#if 算术/比较/defined 与 #elif 链
#include <stdio.h>
#define MODE 2
#define LIMIT 10
int main() {
#if MODE == 1
    printf("one");
#elif MODE == 2
    printf("two");
#else
    printf("other");
#endif
#if defined(MODE) && LIMIT >= 5 && LIMIT / 5 == 2
    printf(" cond");
#endif
#if !defined(NOTHING)
    printf(" ok");
#endif
    printf("\n");
    return 0;
}
