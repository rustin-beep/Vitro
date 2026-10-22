#ifndef POOL_H
#define POOL_H

#define POOL_BLOCK_SIZE 64
#define POOL_BLOCK_COUNT 64

typedef struct {
    char storage[POOL_BLOCK_SIZE * POOL_BLOCK_COUNT];
    unsigned char used[POOL_BLOCK_COUNT];
    int free_stack[POOL_BLOCK_COUNT];
    int free_top;
    int used_count;
    int alloc_total;
    int free_total;
} Pool;

/* prepares the backing store and the free list */
int pool_create(Pool *pool);

/* returns a pointer into the backing store or NULL when the pool is full */
void *pool_alloc(Pool *pool);

/* returns a block to the pool, 0 on success */
int pool_free(Pool *pool, void *pointer);

int pool_used_count(const Pool *pool);
int pool_free_count(const Pool *pool);

/* free blocks that do not belong to the longest contiguous free run */
int pool_fragmentation(const Pool *pool);

/* index of the block behind a pointer or -1 when the pointer is not ours */
int pool_block_index(const Pool *pool, const void *pointer);

int pool_capacity(void);
int pool_block_size(void);

extern int pool_ops;

#endif /* POOL_H */
