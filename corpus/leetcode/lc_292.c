#include <stdio.h>
#include <stdio.h>

int canWinNim(int n) {
    return n % 4 != 0;
}

int main(void) {
    printf("%d\n", canWinNim(4));
    printf("%d\n", canWinNim(1));
    printf("%d\n", canWinNim(7));
    return 0;
}
