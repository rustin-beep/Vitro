#include <stdio.h>
#include <string.h>
int main() {
    char s1[100] = "hello";
    char s2[100] = "world";
    printf("%d\n", strlen(s1));
    strcpy(s1, s2);
    printf("%s\n", s1);
    printf("%d\n", strcmp(s1, s2));
    strcat(s1, "!");
    printf("%s\n", s1);
    return 0;
}
