// @category: llm_multifile
// 工程：MF-CACHE — LRU 缓存：哈希桶 + 双向链表 + MRU/LRU 序
// 来源：LLM 多文件语料（2026-10-21 入库；clang golden 由 clang_direct 工程模式现场生成）
#include <stdio.h>
#include <string.h>
#include "cache.h"

static const char *const KEYS[20] = {
    "alpha", "beta", "gamma", "delta", "epsilon",
    "alpha", "zeta", "beta", "eta", "theta",
    "gamma", "iota", "alpha", "kappa", "lambda",
    "beta", "mu", "delta", "nu", "alpha"
};

int main(void)
{
    Cache cache;
    long linear_comparisons = 0;
    int i;
    int value;

    cache_init(&cache, 4);
    printf("=== twenty accesses with a capacity of four ===\n");
    for (i = 0; i < 20; i++) {
        int rc = cache_get(&cache, KEYS[i], &value);
        if (rc == 0) {
            printf("  %2d key=%-8s hit  value=%d\n", i + 1, KEYS[i], value);
        } else {
            printf("  %2d key=%-8s miss\n", i + 1, KEYS[i]);
            cache_put(&cache, KEYS[i], i * 10);
        }
        cache_print(&cache);
    }

    printf("=== statistics ===\n");
    printf("  hits=%ld misses=%ld lookups=%ld hit_rate=%.2f\n",
           cache.hits, cache.misses, cache.lookups, cache_hit_rate(&cache));

    printf("=== remove a key ===\n");
    printf("  remove beta rc=%d size=%d\n", cache_remove(&cache, "beta"), cache_size(&cache));
    cache_print(&cache);
    printf("  get beta rc=%d\n", cache_get(&cache, "beta", &value));

    printf("=== final state ===\n");
    cache_print(&cache);
    {
        int current = cache.head;
        int list_length = 0;
        while (current >= 0) {
            list_length++;
            current = cache.entries[current].next;
        }
        printf("  size=%d list_length=%d consistent=%s\n", cache.count, list_length,
               (cache.count == list_length) ? "yes" : "no");
    }

    printf("=== linear lookup comparison ===\n");
    for (i = 0; i < 20; i++) {
        int comparisons = cache_linear_lookup(&cache, KEYS[i]);
        if (comparisons < 0) {
            linear_comparisons += (long)(-comparisons);
        } else {
            linear_comparisons += (long)comparisons;
        }
    }
    printf("  linear_comparisons=%ld hash_lookups=%ld advantage=%.2f\n",
           linear_comparisons, cache.lookups,
           (cache.lookups > 0) ? (double)linear_comparisons / (double)cache.lookups : 0.0);
    printf("=== done ===\n");
    return 0;
}
