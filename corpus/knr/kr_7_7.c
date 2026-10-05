#include <stdio.h>
#include <stdlib.h>
int main() {
    int *p = (int *)malloc(5 * sizeof(int));
    if (p == NULL) return 1;
    for (int i = 0; i < 5; i++)
        p[i] = i * i;
    for (int i = 0; i < 5; i++)
        printf("%d ", p[i]);
    printf("\n");
    free(p);
    return 0;
}
