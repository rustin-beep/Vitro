#ifndef CACHE_H
#define CACHE_H

#include <stddef.h>

#define CACHE_KEY_LEN 24
#define CACHE_BUCKETS 16
#define CACHE_DEFAULT_CAPACITY 4

typedef struct CacheEntry {
    char key[CACHE_KEY_LEN];
    int value;
    int used;
    int prev;
    int next;
} CacheEntry;

typedef struct {
    CacheEntry entries[CACHE_BUCKETS * 2];
    int bucket_of[CACHE_BUCKETS * 2];
    int count;
    int capacity;
    int head;
    int tail;
    long hits;
    long misses;
    long lookups;
} Cache;

void cache_init(Cache *cache, int capacity);
int cache_get(Cache *cache, const char *key, int *value);
int cache_put(Cache *cache, const char *key, int value);
int cache_remove(Cache *cache, const char *key);
int cache_size(const Cache *cache);
double cache_hit_rate(const Cache *cache);
void cache_print(const Cache *cache);
int cache_linear_lookup(const Cache *cache, const char *key);

#endif /* CACHE_H */
