#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define TABLE_SIZE 53   /* 质数，减少哈希冲突 */
#define WORD_MAX   64

/* ---------- 哈希表节点（链表法） ---------- */
typedef struct Entry {
    char          word[WORD_MAX];
    int           count;
    struct Entry *next;
} Entry;

static Entry *table[TABLE_SIZE];

/* ---------- djb2 哈希函数 ---------- */
static unsigned int hash(const char *s)
{
    unsigned int h = 5381;
    while (*s)
        h = h * 33 + (unsigned char)*s++;
    return h % TABLE_SIZE;
}

/* ---------- 查找单词，找不到就创建 ---------- */
static Entry *lookup(const char *word)
{
    unsigned int idx = hash(word);
    Entry *p;

    /* 在对应桶的链表里找 */
    for (p = table[idx]; p != NULL; p = p->next)
        if (strcmp(p->word, word) == 0)
            return p;

    /* 没找到，插入链表头 */
    p = (Entry *)malloc(sizeof(Entry));
    if (!p) {
        perror("malloc");
        exit(EXIT_FAILURE);
    }
    strncpy(p->word, word, WORD_MAX - 1);
    p->word[WORD_MAX - 1] = '\0';
    p->count = 0;
    p->next  = table[idx];
    table[idx] = p;
    return p;
}

/* ---------- 按字符流切词并统计 ---------- */
static void count_words(const char *text)
{
    char buf[WORD_MAX];
    int  n = 0;

    for (const char *p = text; ; p++) {
        unsigned char c = (unsigned char)*p;

        if (isalpha(c) || c == '\'') {
            if (n < WORD_MAX - 1)
                buf[n++] = (char)tolower(c);
        } else {
            if (n > 0) {                /* 一个单词结束 */
                buf[n] = '\0';
                lookup(buf)->count++;
                n = 0;
            }
            if (c == '\0') break;
        }
    }
}

/* ---------- 排序输出 ---------- */
typedef struct { const char *word; int count; } Pair;

static int cmp_desc(const void *a, const void *b)
{
    const Pair *pa = (const Pair *)a;
    const Pair *pb = (const Pair *)b;
    return pb->count - pa->count;       /* 次数降序 */
}

static void print_sorted(void)
{
    Pair *arr = NULL;
    int   cap = 0, n = 0;

    /* 收集所有节点到数组 */
    for (int i = 0; i < TABLE_SIZE; i++) {
        for (Entry *p = table[i]; p != NULL; p = p->next) {
            if (n == cap) {
                cap = cap ? cap * 2 : 16;
                Pair *tmp = realloc(arr, (size_t)cap * sizeof(Pair));
                if (!tmp) { perror("realloc"); free(arr); exit(EXIT_FAILURE); }
                arr = tmp;
            }
            arr[n].word  = p->word;
            arr[n].count = p->count;
            n++;
        }
    }

    qsort(arr, (size_t)n, sizeof(Pair), cmp_desc);

    printf("%-12s %s\n", "单词", "次数");
    printf("----------------------\n");
    for (int i = 0; i < n; i++)
        printf("%-12s %d\n", arr[i].word, arr[i].count);

    free(arr);
}

/* ---------- 释放整张哈希表 ---------- */
static void free_all(void)
{
    for (int i = 0; i < TABLE_SIZE; i++) {
        Entry *p = table[i];
        while (p != NULL) {
            Entry *next = p->next;
            free(p);
            p = next;
        }
        table[i] = NULL;
    }
}

/* ---------- 演示 ---------- */
int main(void)
{
    const char *text =
        "The quick brown fox jumps over the lazy dog. "
        "The dog barks, and the fox runs away. "
        "It's a quick fox, isn't it? Yes, the fox is quick!";

    printf("原文:\n%s\n\n", text);

    count_words(text);
    print_sorted();
    free_all();

    return 0;
}
