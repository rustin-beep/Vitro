#include <stdio.h>
unsigned int g[] = {0xFFFFFFFF, 0xAAAAAAAA};
unsigned int neg = -1;
int main(void) {
    printf("%u %u %u\n", g[0], g[1], neg);
    unsigned int t[] = {0, 1, 255, 1023, 0xFFFFFFFF, 0xAAAAAAAA};
    for (int i = 0; i < 6; i++) printf("%u ", t[i]);
    printf("\n");
    return 0;
}
