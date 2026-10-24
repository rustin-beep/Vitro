#include <stdio.h>
#include "pool.h"

static void show(const char *label, const Pool *pool)
{
    printf("  %-24s used=%2d free_stack=%2d fragmentation=%2d\n",
           label, pool_used_count(pool), pool_free_count(pool), pool_fragmentation(pool));
}

/* tracks the block behind a pointer, a block that is handed out twice reuses its slot */
static int track_block(void *held[], int freed[], int *count, int max_count, void *block)
{
    int i;

    for (i = 0; i < *count; i++) {
        if (held[i] == block) {
            freed[i] = 0;
            return 0;
        }
    }
    if (*count >= max_count) {
        return -1;
    }
    held[*count] = block;
    freed[*count] = 0;
    (*count)++;
    return 0;
}

static void mark_freed(void *held[], int freed[], int count, void *block)
{
    int i;

    for (i = 0; i < count; i++) {
        if (held[i] == block) {
            freed[i] = 1;
        }
    }
}

int main(void)
{
    Pool pool;
    void *held[POOL_BLOCK_COUNT];
    int freed[POOL_BLOCK_COUNT];
    int held_count;
    int i;
    int failures;
    int rc;

    held_count = 0;
    for (i = 0; i < POOL_BLOCK_COUNT; i++) {
        held[i] = NULL;
        freed[i] = 0;
    }

    printf("=== layout ===\n");
    pool_create(&pool);
    printf("  backing_store_bytes=%d block_size=%d block_count=%d\n",
           (int)sizeof pool.storage, pool_block_size(), pool_capacity());
    show("after create", &pool);

    printf("=== allocate 20 blocks ===\n");
    for (i = 0; i < 20; i++) {
        void *block = pool_alloc(&pool);
        if (block != NULL) {
            char *text = (char *)block;
            text[0] = (char)('A' + (i % 26));
            text[1] = '\0';
            track_block(held, freed, &held_count, POOL_BLOCK_COUNT, block);
        }
        if ((i + 1) % 5 == 0) {
            printf("  after %2d allocations\n", i + 1);
            show("state", &pool);
        }
    }
    printf("  first block text=%s\n", (char *)held[0]);

    printf("=== free 8 blocks interleaved ===\n");
    for (i = 0; i < 8; i++) {
        int index = i * 2 + 1;
        rc = pool_free(&pool, held[index]);
        mark_freed(held, freed, held_count, held[index]);
        printf("  free slot %2d rc=%d\n", index, rc);
        if ((i + 1) % 4 == 0) {
            show("state", &pool);
        }
    }

    printf("=== allocate 10 more blocks ===\n");
    for (i = 0; i < 10; i++) {
        void *block = pool_alloc(&pool);
        if (block == NULL) {
            printf("  allocation %d failed\n", i);
        } else {
            track_block(held, freed, &held_count, POOL_BLOCK_COUNT, block);
        }
    }
    show("state", &pool);

    printf("=== exhaust the pool ===\n");
    failures = 0;
    for (i = 0; i < POOL_BLOCK_COUNT + 4; i++) {
        void *block = pool_alloc(&pool);
        if (block == NULL) {
            failures++;
            printf("  pool_alloc returned NULL at attempt %d (pool is full)\n", i);
            break;
        }
        track_block(held, freed, &held_count, POOL_BLOCK_COUNT, block);
    }
    printf("  allocation_failures=%d tracked=%d\n", failures, held_count);

    printf("=== free everything ===\n");
    for (i = 0; i < held_count; i++) {
        if (held[i] != NULL && freed[i] == 0) {
            pool_free(&pool, held[i]);
            freed[i] = 1;
        }
    }
    show("state", &pool);

    printf("=== verification ===\n");
    {
        int all_free = 1;
        for (i = 0; i < POOL_BLOCK_COUNT; i++) {
            if (pool.used[i] != 0) {
                all_free = 0;
            }
        }
        printf("  free_list_back_to_initial = %s\n",
               (all_free && pool_free_count(&pool) == POOL_BLOCK_COUNT) ? "yes" : "no");
        printf("  used=%d free=%d fragmentation=%d\n",
               pool_used_count(&pool), pool_free_count(&pool), pool_fragmentation(&pool));
    }
    printf("  alloc_total=%d free_total=%d pool_ops=%d\n",
           pool.alloc_total, pool.free_total, pool_ops);
    return 0;
}
