#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#define TABLE_SIZE 53   /* 质数，减少冲突 */
#define WORD_MAX   64
typedef struct Entry {
    char          word[WORD_MAX];
    int           count;
    struct Entry *next;
} Entry;
static Entry *table[TABLE_SIZE];
/* ---------- djb2 哈希 ---------- */
static unsigned int hash(const char *s) {
    unsigned int h = 5381;
    while (*s)
        h = h * 33 + (unsigned char)*s++;
    return h % TABLE_SIZE;
}
/* ---------- 查找或插入 ---------- */
static Entry *lookup(const char *word, int create) {
    unsigned int idx = hash(word);
    Entry *p;
    for (p = table[idx]; p; p = p->next)
        if (strcmp(p->word, word) == 0)
            return p;
    if (!create) return NULL;
    p = malloc(sizeof(Entry));
    if (!p) { perror("malloc"); exit(EXIT_FAILURE); }
    strncpy(p->word, word, WORD_MAX - 1);
    p->word[WORD_MAX - 1] = '\0';
    p->count = 0;
    p->next  = table[idx];
    table[idx] = p;
    return p;
}
/* ---------- 统计一段文本里的单词 ---------- */
static void count_words(const char *text) {
    char buf[WORD_MAX];
    int  n = 0;
    for (const char *p = text; ; p++) {
        unsigned char c = (unsigned char)*p;
        if (isalpha(c) || c == '\'') {
            if (n < WORD_MAX - 1)
                buf[n++] = (char)tolower(c);
        } else {
            if (n > 0) {
                buf[n] = '\0';
                lookup(buf, 1)->count++;
                n = 0;
            }
            if (c == '\0') break;
        }
    }
}
/* ---------- 遍历所有桶，打印非空 ---------- */
static void print_all(void) {
    for (int i = 0; i < TABLE_SIZE; i++)
        for (Entry *p = table[i]; p; p = p->next)
            printf("%-16s %d\n", p->word, p->count);
}
/* ---------- 释放 ---------- */
static void free_all(void) {
    for (int i = 0; i < TABLE_SIZE; i++) {
        Entry *p = table[i];
        while (p) {
            Entry *next = p->next;
            free(p);
            p = next;
        }
        table[i] = NULL;
    }
}
/* ---------- 演示 ---------- */
int main(void) {
    const char *text =
        "the quick brown fox jumps over the lazy dog. "
        "The dog barks, and the fox runs away. "
        "It's a quick fox, isn't it?";
    printf("原文:\n%s\n\n", text);
    count_words(text);
    printf("词频:\n");
    print_all();
    free_all();
    return 0;
}
