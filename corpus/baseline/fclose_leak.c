#include <stdio.h>

int main() {
    FILE *fp = fopen("test.txt", "w");
    if (!fp) {
        printf("open failed\n");
        return 1;
    }
    fputs("hello\n", fp);
    fclose(fp);
    printf("done\n");
    return 0;
}
