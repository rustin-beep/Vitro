#include <stdio.h>
int g = 42;
int& get_g() { return g; }
int main() {
    get_g() = 100;
    printf("%d\n", g);
    return 0;
}
