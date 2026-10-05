#include <stdio.h>
int main() {
    FILE *fp = fopen("lines.txt", "w");
    if (!fp) return 1;
    fputs("line1\n", fp);
    fputs("line2\n", fp);
    fclose(fp);
    fp = fopen("lines.txt", "r");
    if (!fp) return 1;
    char line[100];
    while (fgets(line, sizeof(line), fp) != NULL)
        printf("%s", line);
    fclose(fp);
    return 0;
}
