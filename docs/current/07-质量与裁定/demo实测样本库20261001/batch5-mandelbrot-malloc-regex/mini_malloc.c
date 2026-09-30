/* mini_malloc_nolib.c —— 不依赖 unistd.h 的版本
 *
 * 编译: gcc -Wall -O2 -o mini_malloc_nolib mini_malloc_nolib.c
 * 运行: ./mini_malloc_nolib
 *
 * 改动点：
 *   - 去掉 <unistd.h>
 *   - 不再调用真正的 sbrk，改为操作一块 1MB 静态数组
 *   - 其它分配器逻辑与上一版完全相同
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* ================================================================
 * 模拟的 "内核堆"
 * ================================================================ */
#define POOL_SIZE (1 << 20)                 /* 1MB */

static char  g_heap_pool[POOL_SIZE];
static char *g_brk      = g_heap_pool;      /* 当前堆顶 */
static char *g_pool_end = g_heap_pool + POOL_SIZE;

/* 模拟 sbrk：把 brk 指针推前 incr 字节，返回旧 brk
 * 失败返回 (void *)-1，和真实 sbrk 保持一致 */
static void *my_sbrk(long incr)
{
    if (incr == 0) return g_brk;

    char *neu = g_brk + incr;
    if (neu < g_heap_pool || neu > g_pool_end)
        return (void *)-1;

    char *old = g_brk;
    g_brk = neu;
    return old;
}

/* ================================================================
 * 分配器本体
 * ================================================================ */
typedef uint64_t word_t;

#define WSIZE     8
#define DSIZE     16
#define CHUNKSIZE 4096

static char *heap_start = NULL;
static char *heap_end   = NULL;

static word_t wget(void *p)           { return *(word_t *)p; }
static void   wput(void *p, word_t v) { *(word_t *)p = v; }

static word_t size_of(void *blk) { return wget(blk) & ~(word_t)0x7; }
static int    is_used(void *blk) { return (int)(wget(blk) & 1); }

static void mark(void *blk, size_t size, int used)
{
    word_t v = (word_t)size | (word_t)(used & 1);
    wput(blk, v);
    wput((char *)blk + size - WSIZE, v);
}

static char *next_block(char *blk) { return blk + size_of(blk); }

static char *prev_block(char *blk)
{
    if (blk <= heap_start) return NULL;
    word_t fp = wget(blk - WSIZE);
    return blk - (fp & ~(word_t)0x7);
}

static void coalesce(char *blk)
{
    size_t size = size_of(blk);

    char *next = blk + size;
    if (next < heap_end && !is_used(next))
        size += size_of(next);

    if (blk > heap_start) {
        char *prev = prev_block(blk);
        if (prev && !is_used(prev)) {
            size += size_of(prev);
            blk   = prev;
        }
    }
    mark(blk, size, 0);
}

static void heap_init(void)
{
    /* 关键替换：sbrk → my_sbrk */
    char *p = (char *)my_sbrk(CHUNKSIZE);
    if (p == (char *)-1) {
        heap_start = heap_end = NULL;
        return;
    }
    heap_start = p;
    heap_end   = p + CHUNKSIZE;
    mark(p, CHUNKSIZE, 0);
}

static char *extend_heap(size_t bytes)
{
    bytes = (bytes + DSIZE - 1) & ~(size_t)(DSIZE - 1);
    if (bytes < CHUNKSIZE) bytes = CHUNKSIZE;

    char *last = heap_start;
    while (next_block(last) < heap_end)
        last = next_block(last);

    char *old_end = heap_end;
    char *np = (char *)my_sbrk((long)bytes);   /* 同样改用 my_sbrk */
    if (np == (char *)-1)
        return NULL;
    heap_end = old_end + bytes;

    if (!is_used(last)) {
        size_t newsize = size_of(last) + bytes;
        mark(last, newsize, 0);
        return last;
    }
    mark(old_end, bytes, 0);
    return old_end;
}

static void *allocate(char *blk, size_t need)
{
    size_t oldsize = size_of(blk);
    size_t rem     = oldsize - need;

    if (rem < 32) {
        mark(blk, oldsize, 1);
        return blk + WSIZE;
    }

    mark(blk, need, 1);
    char *rest = blk + need;
    mark(rest, rem, 0);
    coalesce(rest);
    return blk + WSIZE;
}

void *my_malloc(size_t size)
{
    if (size == 0) return NULL;

    if (!heap_start) {
        heap_init();
        if (!heap_start) return NULL;
    }

    size_t need = (size + 2 * WSIZE + DSIZE - 1) & ~(size_t)(DSIZE - 1);
    if (need < 32) need = 32;

    for (char *p = heap_start; p < heap_end; p = next_block(p)) {
        if (!is_used(p) && size_of(p) >= need)
            return allocate(p, need);
    }

    char *blk = extend_heap(need);
    if (!blk) return NULL;
    return allocate(blk, need);
}

void my_free(void *ptr)
{
    if (!ptr) return;
    char *blk = (char *)ptr - WSIZE;
    mark(blk, size_of(blk), 0);
    coalesce(blk);
}

void *my_realloc(void *ptr, size_t size)
{
    if (!ptr) return my_malloc(size);
    if (size == 0) { my_free(ptr); return NULL; }

    char  *blk = (char *)ptr - WSIZE;
    size_t old_payload = size_of(blk) - 2 * WSIZE;

    if (size <= old_payload) return ptr;

    void *np = my_malloc(size);
    if (!np) return NULL;
    memcpy(np, ptr, old_payload);
    my_free(ptr);
    return np;
}

/* ================================================================
 * 调试
 * ================================================================ */
static void dump_heap(void)
{
    if (!heap_start) { printf("  (堆未初始化)\n"); return; }

    printf("  堆范围: [%p, %p)  共 %ld 字节\n",
           (void *)heap_start, (void *)heap_end,
           (long)(heap_end - heap_start));

    int idx = 0, free_n = 0, used_n = 0;
    size_t free_bytes = 0, used_bytes = 0;

    for (char *p = heap_start; p < heap_end; p = next_block(p)) {
        size_t sz   = size_of(p);
        int    used = is_used(p);

        printf("    块%2d @ %p  size=%4zu  %s  载荷=%zu\n",
               idx++, (void *)p, sz,
               used ? "已分配" : "空闲  ", sz - 2 * WSIZE);

        if (used) { used_n++; used_bytes += sz; }
        else      { free_n++; free_bytes += sz; }
    }
    printf("  >>> 已分配 %d 块 (%zu 字节), 空闲 %d 块 (%zu 字节)\n",
           used_n, used_bytes, free_n, free_bytes);
}

/* ================================================================
 * 演示
 * ================================================================ */
int main(void)
{
    printf("=== 迷你 malloc（无 unistd.h 版） ===\n");
    printf("静态池大小: %d 字节\n\n", POOL_SIZE);

    int *a = (int *)my_malloc(sizeof(int) * 4);
    int *b = (int *)my_malloc(sizeof(int) * 4);
    int *c = (int *)my_malloc(sizeof(int) * 4);

    for (int i = 0; i < 4; i++) {
        a[i] = i * 10;
        b[i] = i * 100;
        c[i] = i * 1000;
    }

    printf("[1] 分配 a、b、c 各 16 字节\n");
    printf("    a=%p  b=%p  c=%p\n", (void *)a, (void *)b, (void *)c);
    dump_heap();

    printf("\n[2] 释放 b\n");
    my_free(b);
    dump_heap();

    printf("\n[3] 再分配 16 字节给 d，应复用 b 的空间\n");
    int *d = (int *)my_malloc(sizeof(int) * 4);
    printf("    d=%p  (d == b ? %s)\n", (void *)d, d == b ? "是" : "否");
    dump_heap();

    printf("\n[4] 验证 a、c 数据没被破坏\n");
    printf("    a =");
    for (int i = 0; i < 4; i++) printf(" %d", a[i]);
    printf("\n    c =");
    for (int i = 0; i < 4; i++) printf(" %d", c[i]);
    printf("\n");

    printf("\n[5] 释放 a 和 d，看空闲块自动合并\n");
    my_free(a);
    my_free(d);
    dump_heap();

    printf("\n[6] 压力测试：分配 20 个小块，隔一个释放一个\n");
    void *ptrs[20];
    for (int i = 0; i < 20; i++)
        ptrs[i] = my_malloc(8 + i);

    for (int i = 0; i < 20; i += 2)
        my_free(ptrs[i]);

    printf("    分配了 20 个，释放了 10 个\n");
    dump_heap();

    printf("\n[7] realloc 测试\n");
    char *s = (char *)my_malloc(8);
    strcpy(s, "hello");
    printf("    原字符串: \"%s\"\n", s);

    s = (char *)my_realloc(s, 64);
    strcat(s, ", world!");
    printf("    扩容后:   \"%s\"\n", s);
    my_free(s);

    for (int i = 1; i < 20; i += 2)
        my_free(ptrs[i]);

    printf("\n[8] 全部释放后\n");
    dump_heap();

    return 0;
}
