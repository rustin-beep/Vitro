#include <stdio.h>

static int counter = 0;

int next() {
    counter++;
    return counter;
}

int main() {
    printf("%d\n", next());
    printf("%d\n", next());
    printf("%d\n", next());
    return 0;
}
