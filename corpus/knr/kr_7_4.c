#include <stdio.h>
int main() {
    FILE *fp = fopen("test.txt", "w");
    if (!fp) return 1;
    fputs("hello world\n", fp);
    fclose(fp);
    fp = fopen("test.txt", "r");
    if (!fp) return 1;
    int c;
    while ((c = fgetc(fp)) != EOF)
        putchar(c);
    fclose(fp);
    return 0;
}
