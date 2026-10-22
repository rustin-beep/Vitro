#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "list.h"

static int cmp_int(const void *a, const void *b)
{
    int x = *(const int *)a;
    int y = *(const int *)b;
    if (x < y) {
        return -1;
    }
    if (x > y) {
        return 1;
    }
    return 0;
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static void print_int(const void *a)
{
    printf("%d\n", *(const int *)a);
}

static void print_str(const void *a)
{
    printf("%s\n", *(const char *const *)a);
}

int main(void)
{
    List *ints;
    List *words;
    int values[6];
    int key;
    int i;
    const char *names[5];

    values[0] = 42;
    values[1] = 7;
    values[2] = 19;
    values[3] = 3;
    values[4] = 25;
    values[5] = 11;

    names[0] = "delta";
    names[1] = "alpha";
    names[2] = "echo";
    names[3] = "bravo";
    names[4] = "charlie";

    ints = list_create();
    words = list_create();
    if (ints == NULL || words == NULL) {
        printf("alloc failed\n");
        return 1;
    }

    printf("=== int list ===\n");
    for (i = 0; i < 6; i++) {
        list_push_back(ints, &values[i]);
    }
    printf("push_back x6   size=%d\n", list_size(ints));
    list_push_front(ints, &values[0]);
    printf("push_front      size=%d\n", list_size(ints));
    list_insert_at(ints, 2, &values[2]);
    printf("insert_at(2)   size=%d\n", list_size(ints));
    list_remove_at(ints, 0);
    printf("remove_at(0)   size=%d\n", list_size(ints));

    printf("forward:\n");
    list_print(ints, print_int);
    printf("reverse:\n");
    list_print_reverse(ints, print_int);

    list_sort(ints, cmp_int);
    printf("sorted:\n");
    list_print(ints, print_int);

    key = 19;
    if (list_find(ints, &key, cmp_int) != NULL) {
        printf("find(19)       = found\n");
    } else {
        printf("find(19)       = missing\n");
    }
    key = 999;
    if (list_find(ints, &key, cmp_int) != NULL) {
        printf("find(999)      = found\n");
    } else {
        printf("find(999)      = missing\n");
    }

    list_reverse(ints);
    printf("reversed:\n");
    list_print(ints, print_int);

    printf("=== string list ===\n");
    for (i = 0; i < 5; i++) {
        list_push_back(words, (void *)&names[i]);
    }
    printf("forward:\n");
    list_print(words, print_str);
    list_sort(words, cmp_str);
    printf("sorted:\n");
    list_print(words, print_str);
    printf("reverse:\n");
    list_print_reverse(words, print_str);

    printf("=== counters ===\n");
    printf("int_nodes=%d word_nodes=%d\n", list_size(ints), list_size(words));
    list_destroy(ints);
    list_destroy(words);
    printf("freed_count=%d\n", list_freed_count);
    return 0;
}
