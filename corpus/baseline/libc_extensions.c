// @category: baseline
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main() {
    // === String / memory extensions ===
    char s1[20] = "hello";
    strncat(s1, " world!!!", 6);
    printf("%s ", s1);

    printf("%d %d ", strncmp("abc", "abd", 2), strncmp("abc", "abd", 3));

    printf("%d %d ", memcmp("abc", "abc", 3), memcmp("abc", "abd", 3));

    char *p = strchr("hello", 'l');
    if (p) printf("%c ", *p); else printf("X ");

    p = strrchr("hello", 'l');
    if (p) printf("%c ", *p); else printf("X ");

    p = strstr("hello world", "world");
    if (p) printf("%c ", *p); else printf("X ");

    p = memchr("hello", 'l', 5);
    if (p) printf("%c ", *p); else printf("X ");

    // === Conversion extensions ===
    double d = atof("3.14");
    long l = atol("12345");
    printf("%.2f %ld ", d, l);

    // === Math extensions ===
    printf("%.3f ", tan(0.0));
    printf("%.3f ", log10(100.0));
    printf("%.3f ", fabs(-3.14));
    printf("%.1f ", ceil(2.3));
    printf("%.1f ", floor(2.7));
    printf("%.1f ", round(2.5));
    printf("%.1f ", fmod(5.5, 2.0));

    return 0;
}
