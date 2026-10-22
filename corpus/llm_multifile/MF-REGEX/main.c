#include <stdio.h>
#include <string.h>
#include "re.h"

typedef struct {
    const char *pattern;
    const char *text;
} Case;

int main(void)
{
    static const Case CASES[10] = {
        { "abc", "xxabcxx" },
        { "^abc", "abcdef" },
        { "abc$", "xxabc" },
        { "^abc$", "abc" },
        { "a.c", "abc" },
        { "[a-z]+", "hello" },
        { "colou?r", "color" },
        { "ab*c", "abbbc" },
        { "[0-9][0-9]", "x42" },
        { "a[bc]d", "abd" }
    };
    static const Case FAILURES[2] = {
        { "^xyz$", "abc" },
        { "[0-9]+z", "abc123" }
    };
    RePattern pattern;
    long total_steps = 0;
    long worst_steps = 0;
    int worst_index = -1;
    int i;
    int matched;
    int start;
    int end;
    long steps;

    printf("=== ten cases ===\n");
    for (i = 0; i < 10; i++) {
        int elements = re_compile(&pattern, CASES[i].pattern);
        int k;
        printf("  case %2d pattern=[%s] text=[%s]\n", i + 1, CASES[i].pattern, CASES[i].text);
        printf("    compiled elements=%d :", elements);
        for (k = 0; k < elements; k++) {
            printf(" %s", re_elem_name(pattern.elems[k].type));
        }
        printf("\n");
        matched = re_match(&pattern, CASES[i].text, &start, &end, &steps);
        total_steps += steps;
        if (steps > worst_steps) {
            worst_steps = steps;
            worst_index = i;
        }
        if (matched) {
            char slice[RE_MAX_TEXT + 1];
            int len = end - start;
            if (len > RE_MAX_TEXT) {
                len = RE_MAX_TEXT;
            }
            memcpy(slice, CASES[i].text + start, (size_t)len);
            slice[len] = '\0';
            printf("    matched=yes start=%d end=%d text=[%s] steps=%ld\n",
                   start, end, slice, steps);
        } else {
            printf("    matched=no  start=%d end=%d steps=%ld\n", start, end, steps);
        }
    }

    printf("=== failing cases ===\n");
    for (i = 0; i < 2; i++) {
        re_compile(&pattern, FAILURES[i].pattern);
        matched = re_match(&pattern, FAILURES[i].text, &start, &end, &steps);
        printf("  pattern=[%s] text=[%s] matched=%s failure_position=%d steps=%ld\n",
               FAILURES[i].pattern, FAILURES[i].text, matched ? "yes" : "no", start, steps);
    }

    printf("=== backtracking statistics ===\n");
    printf("  total_steps=%ld\n", total_steps);
    printf("  worst_case_index=%d worst_case_steps=%ld\n", worst_index, worst_steps);
    if (worst_index >= 0) {
        printf("  worst_case_pattern=[%s]\n", CASES[worst_index].pattern);
    }

    printf("=== compile errors ===\n");
    printf("  compile([) elements=%d\n", re_compile(&pattern, "["));
    printf("  compile([abc) elements=%d\n", re_compile(&pattern, "[abc"));
    printf("  re_ops=%d\n", re_ops);
    return 0;
}
