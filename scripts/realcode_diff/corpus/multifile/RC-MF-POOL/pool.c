#include "pool.h"

int pool_ops = 0;
#include <string.h>

int pool_create(Pool *pool)
{
    int i;

    if (pool == NULL) {
        return -1;
    }
    memset(pool->storage, 0, sizeof pool->storage);
    for (i = 0; i < POOL_BLOCK_COUNT; i++) {
        pool->used[i] = 0;
        pool->free_stack[i] = POOL_BLOCK_COUNT - 1 - i;
    }
    pool->free_top = POOL_BLOCK_COUNT;
    pool->used_count = 0;
    pool->alloc_total = 0;
    pool->free_total = 0;
    return 0;
}

void *pool_alloc(Pool *pool)
{
    int index;
    char *block;

    if (pool == NULL) {
        return NULL;
    }
    if (pool->free_top <= 0) {
        return NULL;
    }
    pool->free_top--;
    index = pool->free_stack[pool->free_top];
    if (index < 0 || index >= POOL_BLOCK_COUNT) {
        return NULL;
    }
    pool->used[index] = 1;
    pool->used_count++;
    pool->alloc_total++;
    pool_ops++;
    block = pool->storage + (size_t)index * POOL_BLOCK_SIZE;
    memset(block, 0, POOL_BLOCK_SIZE);
    return block;
}

int pool_free(Pool *pool, void *pointer)
{
    int index;

    if (pool == NULL || pointer == NULL) {
        return -1;
    }
    index = pool_block_index(pool, pointer);
    if (index < 0) {
        return -2;
    }
    if (pool->used[index] == 0) {
        return -3;
    }
    if (pool->free_top >= POOL_BLOCK_COUNT) {
        return -4;
    }
    pool->used[index] = 0;
    pool->free_stack[pool->free_top] = index;
    pool->free_top++;
    pool->used_count--;
    pool->free_total++;
    return 0;
}

int pool_used_count(const Pool *pool)
{
    if (pool == NULL) {
        return 0;
    }
    return pool->used_count;
}

int pool_free_count(const Pool *pool)
{
    if (pool == NULL) {
        return 0;
    }
    return pool->free_top;
}

int pool_fragmentation(const Pool *pool)
{
    int longest = 0;
    int current = 0;
    int scattered = 0;
    int i;

    if (pool == NULL) {
        return 0;
    }
    for (i = 0; i < POOL_BLOCK_COUNT; i++) {
        if (pool->used[i] == 0) {
            current++;
            if (current > longest) {
                longest = current;
            }
        } else {
            current = 0;
        }
    }
    scattered = pool->free_top - longest;
    return (scattered < 0) ? 0 : scattered;
}

int pool_block_index(const Pool *pool, const void *pointer)
{
    const char *base;
    const char *bytes;
    long offset;

    if (pool == NULL || pointer == NULL) {
        return -1;
    }
    base = pool->storage;
    bytes = (const char *)pointer;
    if (bytes < base || bytes >= base + sizeof pool->storage) {
        return -1;
    }
    offset = bytes - base;
    if (offset % POOL_BLOCK_SIZE != 0) {
        return -1;
    }
    return (int)(offset / POOL_BLOCK_SIZE);
}

int pool_capacity(void)
{
    return POOL_BLOCK_COUNT;
}

int pool_block_size(void)
{
    return POOL_BLOCK_SIZE;
}
