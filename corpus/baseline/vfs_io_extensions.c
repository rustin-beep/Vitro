// @category: baseline
#include <stdio.h>
#include <string.h>

int main() {
    FILE *f = fopen("test.txt", "w");
    if (!f) { printf("FAIL fopen w\n"); return 1; }

    fputc('H', f);
    fputc('i', f);
    fputs("!\n", f);
    fclose(f);

    f = fopen("test.txt", "r");
    if (!f) { printf("FAIL fopen r\n"); return 1; }

    int c1 = fgetc(f);
    int c2 = fgetc(f);
    int c3 = fgetc(f);
    int c4 = fgetc(f);
    printf("%c%c%c ", c1, c2, c3);
    printf("%d ", c4);

    printf("%ld ", ftell(f));
    rewind(f);
    printf("%ld ", ftell(f));
    printf("%c ", fgetc(f));

    fseek(f, 1, 0);
    printf("%c ", fgetc(f));

    fseek(f, -1, 1);
    printf("%c ", fgetc(f));

    fseek(f, 0, 2);
    printf("%ld ", ftell(f));

    fclose(f);
    return 0;
}
