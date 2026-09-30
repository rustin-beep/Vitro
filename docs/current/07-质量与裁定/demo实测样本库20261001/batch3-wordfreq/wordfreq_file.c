#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#define HASH_SIZE 101  /* 质数，减少冲突 */
#define WORD_MAX  64
typedef struct WordEntry {
    char word[WORD_MAX];
    int  count;
    struct WordEntry *next;
} WordEntry;
static unsigned int hash_str(const char *s) {
    unsigned int h = 5381;
    while (*s)
        h = h * 33 + (unsigned char)*s++;
    return h % HASH_SIZE;
}
static WordEntry *table[HASH_SIZE];
static WordEntry *find_or_create(const char *word) {
    unsigned int idx = hash_str(word);
    WordEntry *p;
    for (p = table[idx]; p != NULL; p = p->next)
        if (strcmp(p->word, word) == 0)
            return p;
    /* 没找到，创建 */
    p = (WordEntry *)malloc(sizeof(WordEntry));
    if (!p) { fprintf(stderr, "out of memory\n"); exit(1); }
    strncpy(p->word, word, WORD_MAX - 1);
    p->word[WORD_MAX - 1] = '\0';
    p->count = 0;
    p->next = table[idx];
    table[idx] = p;
    return p;
}
static void count_words(FILE *fp) {
    char buf[WORD_MAX];
    int  c, n = 0;
    while ((c = fgetc(fp)) != EOF) {
        if (isalpha((unsigned char)c) || c == '\'') {
            if (n < WORD_MAX - 1)
                buf[n++] = (char)tolower((unsigned char)c);
        } else {
            if (n > 0) {
                buf[n] = '\0';
                find_or_create(buf)->count++;
                n = 0;
            }
        }
    }
    if (n > 0) {
        buf[n] = '\0';
        find_or_create(buf)->count++;
    }
}
