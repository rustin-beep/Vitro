#include <stdio.h>
#include "include_custom_header.h"

int main() {
    printf(GREETING);
    printf("%d\n", add(2, 3));
    return 0;
}
