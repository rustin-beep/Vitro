// @category: llm_multifile
// 工程：MF-CACHE — LRU 缓存：哈希桶 + 双向链表 + MRU/LRU 序
// 来源：LLM 多文件语料（2026-10-21 入库；clang golden 由 clang_direct 工程模式现场生成）
#include "cache.h"
#include <stdio.h>
#include <string.h>

static void cache_copy(char *dst, size_t cap, const char *src)
{
    size_t n;

    if (dst == NULL || src == NULL || cap == 0) {
        return;
    }
    n = strlen(src);
    if (n > cap - 1) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

static unsigned int cache_hash(const char *key)
{
    unsigned int hash = 2166136261u;

    while (*key != '\0') {
        hash ^= (unsigned char)*key;
        hash *= 16777619u;
        key++;
    }
    return hash;
}

void cache_init(Cache *cache, int capacity)
{
    int i;

    memset(cache, 0, sizeof(Cache));
    if (capacity <= 0) {
        capacity = CACHE_DEFAULT_CAPACITY;
    }
    cache->capacity = capacity;
    for (i = 0; i < CACHE_BUCKETS * 2; i++) {
        cache->entries[i].used = 0;
        cache->entries[i].key[0] = '\0';
        cache->entries[i].value = 0;
        cache->entries[i].prev = -1;
        cache->entries[i].next = -1;
        cache->bucket_of[i] = -1;
    }
    cache->head = -1;
    cache->tail = -1;
    cache->count = 0;
    cache->hits = 0;
    cache->misses = 0;
    cache->lookups = 0;
}

static int cache_find(const Cache *cache, const char *key)
{
    unsigned int bucket = cache_hash(key) % CACHE_BUCKETS;
    int i;

    for (i = 0; i < CACHE_BUCKETS * 2; i++) {
        if (cache->entries[i].used && strcmp(cache->entries[i].key, key) == 0) {
            if (cache->bucket_of[i] == (int)bucket) {
                return i;
            }
        }
    }
    return -1;
}

static void cache_unlink(Cache *cache, int index)
{
    int prev = cache->entries[index].prev;
    int next = cache->entries[index].next;

    if (prev >= 0) {
        cache->entries[prev].next = next;
    } else {
        cache->head = next;
    }
    if (next >= 0) {
        cache->entries[next].prev = prev;
    } else {
        cache->tail = prev;
    }
    cache->entries[index].prev = -1;
    cache->entries[index].next = -1;
}

static void cache_push_front(Cache *cache, int index)
{
    cache->entries[index].prev = -1;
    cache->entries[index].next = cache->head;
    if (cache->head >= 0) {
        cache->entries[cache->head].prev = index;
    }
    cache->head = index;
    if (cache->tail < 0) {
        cache->tail = index;
    }
}

static void cache_move_front(Cache *cache, int index)
{
    if (cache->head == index) {
        return;
    }
    cache_unlink(cache, index);
    cache_push_front(cache, index);
}

static int cache_free_slot(Cache *cache)
{
    int i;

    for (i = 0; i < CACHE_BUCKETS * 2; i++) {
        if (!cache->entries[i].used) {
            return i;
        }
    }
    return -1;
}

int cache_get(Cache *cache, const char *key, int *value)
{
    int index;

    if (cache == NULL || key == NULL) {
        return -1;
    }
    cache->lookups++;
    index = cache_find(cache, key);
    if (index < 0) {
        cache->misses++;
        return -2;
    }
    cache->hits++;
    cache_move_front(cache, index);
    if (value != NULL) {
        *value = cache->entries[index].value;
    }
    return 0;
}

int cache_put(Cache *cache, const char *key, int value)
{
    int index;

    if (cache == NULL || key == NULL || key[0] == '\0') {
        return -1;
    }
    index = cache_find(cache, key);
    if (index >= 0) {
        cache->entries[index].value = value;
        cache_move_front(cache, index);
        return 0;
    }
    if (cache->count >= cache->capacity) {
        if (cache->tail < 0) {
            return -2;
        }
        index = cache->tail;
        cache_unlink(cache, index);
        cache->entries[index].used = 0;
        cache->entries[index].key[0] = '\0';
        cache->count--;
    }
    index = cache_free_slot(cache);
    if (index < 0) {
        return -3;
    }
    cache_copy(cache->entries[index].key, CACHE_KEY_LEN, key);
    cache->entries[index].value = value;
    cache->entries[index].used = 1;
    cache->bucket_of[index] = (int)(cache_hash(key) % CACHE_BUCKETS);
    cache_push_front(cache, index);
    cache->count++;
    return 0;
}

int cache_remove(Cache *cache, const char *key)
{
    int index;

    if (cache == NULL || key == NULL) {
        return -1;
    }
    index = cache_find(cache, key);
    if (index < 0) {
        return -2;
    }
    cache_unlink(cache, index);
    cache->entries[index].used = 0;
    cache->entries[index].key[0] = '\0';
    cache->count--;
    return 0;
}

int cache_size(const Cache *cache)
{
    if (cache == NULL) {
        return 0;
    }
    return cache->count;
}

double cache_hit_rate(const Cache *cache)
{
    if (cache == NULL || cache->lookups == 0) {
        return 0.0;
    }
    return (double)cache->hits / (double)cache->lookups;
}

void cache_print(const Cache *cache)
{
    int current;
    int position = 0;

    printf("    mru->lru:");
    current = (cache != NULL) ? cache->head : -1;
    while (current >= 0 && position < 16) {
        printf(" %s=%d", cache->entries[current].key, cache->entries[current].value);
        current = cache->entries[current].next;
        position++;
    }
    printf("\n");
}

int cache_linear_lookup(const Cache *cache, const char *key)
{
    int i;
    int comparisons = 0;

    if (cache == NULL || key == NULL) {
        return -1;
    }
    for (i = 0; i < CACHE_BUCKETS * 2; i++) {
        if (!cache->entries[i].used) {
            continue;
        }
        comparisons++;
        if (strcmp(cache->entries[i].key, key) == 0) {
            return comparisons;
        }
    }
    return -comparisons;
}
