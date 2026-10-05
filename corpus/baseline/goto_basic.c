#include <stdio.h>

int main() {
    int x = 0;
    goto forward;
    x = 100;  // skipped
forward:
    printf("%d\n", x);

    int i = 0;
loop:
    if (i >= 3) goto end;
    printf("%d\n", i);
    i++;
    goto loop;
end:
    return 0;
}
