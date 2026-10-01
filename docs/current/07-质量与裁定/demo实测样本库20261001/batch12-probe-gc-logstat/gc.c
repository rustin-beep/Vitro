/* gc.c —— 标记-清除垃圾回收器
 *
 * 编译: gcc -Wall -O2 -o gc gc.c
 * 运行: ./gc
 *
 * 核心思路:
 *   1. 所有对象都在一个固定大小的"堆"里
 *   2. 每个对象有 mark 位，默认 0
 *   3. GC 分两阶段:
 *      - mark : 从根集合出发，深度优先，把可达对象全部标记
 *      - sweep: 遍历整个堆，未标记的回收，已标记的清零标记
 *   4. 回收的空位进 free list，下次分配时优先复用
 *
 *   这就是 1960 年 McCarthy 发明 Lisp 时用的那套算法。
 *   Java、C#、Go 的 GC 都是它的后裔。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define HEAP_SIZE   64
#define MAX_REFS    4
#define ROOTS_MAX   16

/* ================================================================
 * 对象
 * ================================================================ */
typedef enum { OBJ_INT, OBJ_PAIR, OBJ_STRING } ObjType;

typedef struct Object Object;
struct Object {
    ObjType type;
    bool    marked;             /* GC 标记位 */
    bool    in_use;             /* 当前是否被占用 */
    int     id;

    union {
        int    ival;
        char   sval[32];
        struct {
            Object *a;
            Object *b;
        } pair;
    } u;

    Object *refs[MAX_REFS];     /* 所有引用 */
    int     nrefs;
};

/* ================================================================
 * 堆 + 空闲链表
 * ================================================================ */
static Object  g_heap[HEAP_SIZE];
static int     g_next_id = 1;
static Object *g_free_list = NULL;   /* 简单用数组下标链表 */
static int     g_free_next[HEAP_SIZE];

/* 根集合：模拟"栈上的变量"和"全局变量" */
static Object *g_roots[ROOTS_MAX];
static int     g_nroots = 0;

/* 统计 */
static long g_alloc_count = 0;
static long g_gc_count    = 0;
static long g_freed_total = 0;

/* ================================================================
 * 初始化
 * ================================================================ */
static void heap_init(void)
{
    memset(g_heap, 0, sizeof(g_heap));

    /* 把所有 slot 串成 free list：0 → 1 → 2 → ... → -1 */
    for (int i = 0; i < HEAP_SIZE; i++) {
        g_free_next[i] = i + 1;
        g_heap[i].in_use = false;
    }
    g_free_next[HEAP_SIZE - 1] = -1;
    g_free_list = &g_heap[0];
}

static int index_of(Object *o)
{
    if (!o) return -1;
    return (int)(o - g_heap);
}

/* 从 free list 弹出一个 slot */
static Object *free_list_pop(void)
{
    if (!g_free_list) return NULL;

    int idx = index_of(g_free_list);
    Object *o = g_free_list;

    int next = g_free_next[idx];
    g_free_list = (next >= 0) ? &g_heap[next] : NULL;

    return o;
}

/* 把 slot 推回 free list */
static void free_list_push(Object *o)
{
    int idx = index_of(o);
    g_free_next[idx] = g_free_list ? index_of(g_free_list) : -1;
    g_free_list = o;
}

/* ================================================================
 * 分配
 * ================================================================ */
static void gc_collect(void);   /* 前置声明 */

static Object *gc_alloc(ObjType type)
{
    Object *o = free_list_pop();

    if (!o) {
        /* 堆满了，触发一次 GC，再试一次 */
        printf("  \033[1;33m[GC]\033[0m 堆满，触发回收...\n");
        gc_collect();

        o = free_list_pop();
        if (!o) {
            fprintf(stderr, "  堆耗尽，无法分配\n");
            return NULL;
        }
    }

    /* 清空并初始化 */
    memset(o, 0, sizeof(*o));
    o->type   = type;
    o->in_use = true;
    o->marked = false;
    o->id     = g_next_id++;
    o->nrefs  = 0;

    g_alloc_count++;
    return o;
}

/* ================================================================
 * 便捷构造函数
 * ================================================================ */
static Object *mk_int(int v)
{
    Object *o = gc_alloc(OBJ_INT);
    if (!o) return NULL;
    o->u.ival = v;
    return o;
}

static Object *mk_str(const char *s)
{
    Object *o = gc_alloc(OBJ_STRING);
    if (!o) return NULL;
    strncpy(o->u.sval, s, sizeof(o->u.sval) - 1);
    o->u.sval[sizeof(o->u.sval) - 1] = '\0';
    return o;
}

static Object *mk_pair(Object *a, Object *b)
{
    Object *o = gc_alloc(OBJ_PAIR);
    if (!o) return NULL;
    o->u.pair.a = a;
    o->u.pair.b = b;

    /* 自动建立引用关系 */
    if (a && o->nrefs < MAX_REFS) o->refs[o->nrefs++] = a;
    if (b && o->nrefs < MAX_REFS) o->refs[o->nrefs++] = b;
    return o;
}

/* ================================================================
 * 根集合管理
 * ================================================================ */
static void root_add(Object *o)
{
    if (g_nroots < ROOTS_MAX)
        g_roots[g_nroots++] = o;
}

static void root_clear(void)
{
    g_nroots = 0;
}

/* ================================================================
 * Mark 阶段：从根出发 DFS
 *
 *   用显式栈而不是递归，避免深度太大时爆掉 C 栈。
 * ================================================================ */
static void mark_object(Object *o)
{
    if (!o || !o->in_use || o->marked) return;

    /* 显式栈 */
    Object *stack[HEAP_SIZE * MAX_REFS];
    int top = 0;
    stack[top++] = o;

    while (top > 0) {
        Object *cur = stack[--top];
        if (!cur || !cur->in_use || cur->marked) continue;

        cur->marked = true;

        for (int i = 0; i < cur->nrefs; i++) {
            Object *r = cur->refs[i];
            if (r && r->in_use && !r->marked)
                stack[top++] = r;
        }
    }
}

static void mark_phase(void)
{
    for (int i = 0; i < g_nroots; i++)
        mark_object(g_roots[i]);
}

/* ================================================================
 * Sweep 阶段：遍历整个堆，回收未标记
 * ================================================================ */
static int sweep_phase(void)
{
    int freed = 0;

    for (int i = 0; i < HEAP_SIZE; i++) {
        Object *o = &g_heap[i];
        if (!o->in_use) continue;

        if (o->marked) {
            /* 还活着，清标记准备下一轮 */
            o->marked = false;
        } else {
            /* 不可达，回收 */
            o->in_use = false;
            free_list_push(o);
            freed++;
        }
    }
    return freed;
}

/* ================================================================
 * 完整 GC
 * ================================================================ */
static void gc_collect(void)
{
    g_gc_count++;

    /* 统计 GC 前的占用 */
    int live_before = 0;
    for (int i = 0; i < HEAP_SIZE; i++)
        if (g_heap[i].in_use) live_before++;

    printf("  ┌─ GC #%ld ────────────────────────────\n", g_gc_count);
    printf("  │ 回收前: %2d 个对象存活 / %d 个槽位\n",
           live_before, HEAP_SIZE);

    mark_phase();

    int live_after = 0;
    for (int i = 0; i < HEAP_SIZE; i++)
        if (g_heap[i].in_use && g_heap[i].marked) live_after++;

    int freed = sweep_phase();
    g_freed_total += freed;

    printf("  │ 可达对象: %d 个\n", live_after);
    printf("  │ 回收:     %d 个\n", freed);
    printf("  │ 剩余可用: %d 个槽位\n",
           live_before - live_after + freed);
    printf("  └──────────────────────────────────────\n");
}

/* ================================================================
 * 调试：打印堆
 * ================================================================ */
static void print_heap(void)
{
    printf("  堆状态:\n");

    for (int i = 0; i < HEAP_SIZE; i++) {
        Object *o = &g_heap[i];
        if (!o->in_use) continue;

        printf("    [%2d] #%d  ", i, o->id);
        switch (o->type) {
        case OBJ_INT:
            printf("int    %d", o->u.ival);
            break;
        case OBJ_STRING:
            printf("string \"%s\"", o->u.sval);
            break;
        case OBJ_PAIR:
            printf("pair   (→#%d, →#%d)",
                   o->u.pair.a ? o->u.pair.a->id : -1,
                   o->u.pair.b ? o->u.pair.b->id : -1);
            break;
        }

        /* 标一下是不是根 */
        bool is_root = false;
        for (int r = 0; r < g_nroots; r++)
            if (g_roots[r] == o) { is_root = true; break; }
        if (is_root) printf("  \033[1;32m[root]\033[0m");

        putchar('\n');
    }
}

/* ================================================================
 * 演示
 * ================================================================ */
int main(void)
{
    printf("\033[1;36m");
    printf("╔═══════════════════════════════════════╗\n");
    printf("║   标记-清除 垃圾回收器 演示           ║\n");
    printf("╚═══════════════════════════════════════╝\n");
    printf("\033[0m\n");

    heap_init();

    /* ----------------------------------------------------------
     * 场景 1：基本可达性
     * ---------------------------------------------------------- */
    printf("=== 场景 1：根集合 + 可达对象 ===\n\n");

    Object *a = mk_int(42);
    Object *b = mk_int(99);
    Object *c = mk_str("hello");
    Object *d = mk_str("garbage");   /* 故意不被引用 */

    root_add(a);
    root_add(b);
    root_add(c);
    /* d 不是根，也没有被引用 → 会被回收 */

    print_heap();

    printf("\n执行 GC：\n");
    gc_collect();

    printf("\n回收后：\n");
    print_heap();

    /* ----------------------------------------------------------
     * 场景 2：循环引用 —— 引用计数器的死穴
     * ---------------------------------------------------------- */
    printf("\n=== 场景 2：循环引用 ===\n\n");
    printf("创建两个互相引用的对象，都不加入根集合。\n");
    printf("引用计数法会泄漏它们，但标记-清除能回收。\n\n");

    Object *x = mk_pair(NULL, NULL);
    Object *y = mk_pair(NULL, NULL);

    /* 手动建立循环引用 */
    x->refs[x->nrefs++] = y;
    y->refs[y->nrefs++] = x;
    x->u.pair.a = y;
    y->u.pair.a = x;

    printf("创建循环：x → y → x\n");
    printf("x = #%d, y = #%d\n", x->id, y->id);
    printf("两者都不是根，也都没被根引用。\n\n");

    print_heap();

    printf("\n执行 GC：\n");
    gc_collect();

    printf("\n回收后：\n");
    print_heap();

    /* ----------------------------------------------------------
     * 场景 3：对象图遍历
     * ---------------------------------------------------------- */
    printf("\n=== 场景 3：复杂对象图 ===\n\n");

    root_clear();
    heap_init();   /* 清空重置，方便看 */

    /* 构建一棵树：
     *         root
     *        /    \
     *      left   right
     *      /  \
     *   l1    l2
     */
    Object *l1   = mk_int(1);
    Object *l2   = mk_int(2);
    Object *left = mk_pair(l1, l2);
    Object *right= mk_int(3);
    Object *root = mk_pair(left, right);

    root_add(root);

    /* 加两个孤儿对象 */
    Object *orphan1 = mk_str("lost");
    Object *orphan2 = mk_str("forgotten");
    (void)orphan1; (void)orphan2;

    print_heap();

    printf("\n从 root 出发，可达的对象有：");
    printf("#%d, #%d, #%d, #%d, #%d\n",
           root->id, left->id, l1->id, l2->id, right->id);
    printf("孤儿对象 #%d 和 #%d 不可达。\n\n",
           orphan1->id, orphan2->id);

    printf("执行 GC：\n");
    gc_collect();

    printf("\n回收后：\n");
    print_heap();

    /* ----------------------------------------------------------
     * 场景 4：堆压力测试
     * ---------------------------------------------------------- */
    printf("\n=== 场景 4：反复分配 / 回收 ===\n\n");

    root_clear();
    heap_init();

    for (int round = 0; round < 5; round++) {
        printf("\n--- 第 %d 轮 ---\n", round + 1);

        /* 每轮分配 8 个对象，只有一个进根 */
        Object *keeper = mk_str("keeper");
        root_clear();
        root_add(keeper);

        for (int i = 0; i < 7; i++) {
            Object *tmp = mk_int(i);
            (void)tmp;   /* 用完就不管了 */
        }
        printf("  分配 8 个对象，1 个保留在根\n");

        gc_collect();
    }

    /* ----------------------------------------------------------
     * 统计
     * ---------------------------------------------------------- */
    printf("\n=== 统计 ===\n");
    printf("  总分配:   %ld 次\n", g_alloc_count);
    printf("  GC 次数:  %ld 次\n", g_gc_count);
    printf("  总回收:   %ld 个对象\n", g_freed_total);

    printf("\n标记-清除的关键特性：\n");
    printf("  ✓ 能回收循环引用（引用计数做不到）\n");
    printf("  ✗ GC 时会暂停整个程序（stop-the-world）\n");
    printf("  ✗ 会产生内存碎片（回收后不整理）\n");
    printf("  ✗ 遍历整个堆，代价与堆大小成正比\n");

    return 0;
}
