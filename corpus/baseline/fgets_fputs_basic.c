// @category: baseline
#include <stdio.h>
int main() { FILE* fp = fopen("test.txt", "w"); fputs("hello\n", fp); fputs("world\n", fp); fclose(fp); fp = fopen("test.txt", "r"); char buf[20]; fgets(buf, 20, fp); printf("%s", buf); fgets(buf, 20, fp); printf("%s", buf); fclose(fp); return 0; }
