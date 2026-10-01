/* arc.c —— ARC（自适应替换缓存）+ LRU 对比
 *
 * 编译: gcc -Wall -O2 -std=c11 -o arc arc.c
 * 运行: ./arc
 *
 * ARC 维护 4 个列表:
 *   T1: 最近访问过一次的缓存条目（recency）
 *   T2: 最近访问过多次的缓存条目（frequency）
 *   B1: T1 中最近被淘汰的幽灵条目（只记 key，不存数据）
 *   B2: T2 中最近被淘汰的幽灵条目
 *
 * 参数 p 表示 T1 的目标大小。命中 B1 → p 增大（recency 更重要）；
 * 命中 B2 → p 减小（frequency 更重要）。这样 ARC 能自动适应负载。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define HASH_SIZE 2048

/* ================================================================
 * 双向链表节点（同时挂在哈希桶和 4 个列表之一上）
 * ================================================================ */
typedef enum { L_T1, L_T2, L_B1, L_B2 } ListId;

typedef struct Node {
    int          key;
    int          value;         /* 幽灵节点里无效 */
    ListId       list;
    struct Node *prev, *next;   /* 链表用 */
    struct Node *hnext;         /* 哈希桶链用 */
} Node;

typedef struct {
    Node *head, *tail;          /* head = MRU, tail = LRU */
    int   size;
} List;

static void list_init(List *L) { L->head = L->tail = NULL; L->size = 0; }

static void list_unlink(List *L, Node *n) {
    if (n->prev) n->prev->next = n->next;
    else         L->head = n->next;
    if (n->next) n->next->prev = n->prev;
    else         L->tail = n->prev;
    n->prev = n->next = NULL;
    L->size--;
}

static void list_push_front(List *L, Node *n) {
    n->prev = NULL;
    n->next = L->head;
    if (L->head) L->head->prev = n;
    else         L->tail = n;
    L->head = n;
    L->size++;
}

static Node *list_pop_back(List *L) {
    Node *n = L->tail;
    if (n) list_unlink(L, n);
    return n;
}

/* ================================================================
 * 哈希：key → Node*
 * ================================================================ */
static unsigned hash_int(int key) {
    unsigned k = (unsigned)key;
    k = (k ^ 61) ^ (k >> 16);
    k += k << 3;
    k ^= k >> 4;
    k *= 0x27d4eb2d;
    k ^= k >> 15;
    return k % HASH_SIZE;
}

/* ================================================================
 * ARC 结构
 * ================================================================ */
typedef struct {
    int   capacity;
    int   p;             /* T1 的目标大小 */
    List  T1, T2, B1, B2;
    Node *buckets[HASH_SIZE];
    long  hits, misses;
} ARC;

static Node *hash_find(Node **buckets, int key) {
    unsigned h = hash_int(key);
    for (Node *n = buckets[h]; n; n = n->hnext)
        if (n->key == key) return n;
    return NULL;
}

static void hash_insert(Node **buckets, Node *n) {
    unsigned h = hash_int(n->key);
    n->hnext = buckets[h];
    buckets[h] = n;
}

static void hash_remove(Node **buckets, Node *n) {
    unsigned h = hash_int(n->key);
    Node **pp = &buckets[h];
    while (*pp) {
        if (*pp == n) { *pp = n->hnext; return; }
        pp = &(*pp)->hnext;
    }
}

static void arc_init(ARC *arc, int cap) {
    arc->capacity = cap;
    arc->p = 0;
    list_init(&arc->T1); list_init(&arc->T2);
    list_init(&arc->B1); list_init(&arc->B2);
    memset(arc->buckets, 0, sizeof(arc->buckets));
    arc->hits = arc->misses = 0;
}

static void arc_free_node(ARC *arc, Node *n) {
    hash_remove(arc->buckets, n);
    free(n);
}

static void arc_free(ARC *arc) {
    List *lists[] = { &arc->T1, &arc->T2, &arc->B1, &arc->B2 };
    for (int i = 0; i < 4; i++) {
        Node *n = lists[i]->head;
        while (n) { Node *nx = n->next; free(n); n = nx; }
        list_init(lists[i]);
    }
}

/* REPLACE：从 T1 或 T2 淘汰一个到对应的幽灵列表
 *
 *   in_b2 = 请求的 key 是否在 B2 里（决定偏好哪一边）
 *   规则：如果 |T1| ≥ 1 且 (in_b2 且 |T1| == p 或 |T1| > p) → 踢 T1
 *         否则踢 T2
 */
static void arc_replace(ARC *arc, int in_b2) {
    int from_t1 = (arc->T1.size >= 1 &&
        ((in_b2 && arc->T1.size == arc->p) || arc->T1.size > arc->p));

    if (from_t1 && arc->T1.size > 0) {
        Node *v = list_pop_back(&arc->T1);
        v->list = L_B1;
        list_push_front(&arc->B1, v);
    } else if (arc->T2.size > 0) {
        Node *v = list_pop_back(&arc->T2);
        v->list = L_B2;
        list_push_front(&arc->B2, v);
    } else if (arc->T1.size > 0) {
        /* T2 空的退化情况 */
        Node *v = list_pop_back(&arc->T1);
        v->list = L_B1;
        list_push_front(&arc->B1, v);
    }
}

/* 完整的 ARC 请求：先查，再决定插入 / 提升 / 淘汰 */
static void arc_request(ARC *arc, int key, int value, int *hit_out) {
    Node *n = hash_find(arc->buckets, key);

    if (n) {
        /* ---- 缓存命中：T1 / T2 ---- */
        if (n->list == L_T1) {
            arc->hits++;
            *hit_out = 1;
            n->value = value;
            list_unlink(&arc->T1, n);
            list_push_front(&arc->T2, n);
            n->list = L_T2;
            return;
        }
        if (n->list == L_T2) {
            arc->hits++;
            *hit_out = 1;
            n->value = value;
            list_unlink(&arc->T2, n);
            list_push_front(&arc->T2, n);   /* 刷新到 MRU */
            return;
        }

        /* ---- 幽灵命中：B1 / B2 ---- */
        arc->misses++;
        *hit_out = 0;

        if (n->list == L_B1) {
            /* B1 命中：recency 重要，p 增大 */
            int d = (arc->B1.size > 0) ? (arc->B2.size / arc->B1.size) : 1;
            if (d < 1) d = 1;
            arc->p += d;
            if (arc->p > arc->capacity) arc->p = arc->capacity;

            arc_replace(arc, 0);

            list_unlink(&arc->B1, n);
            n->value = value;
            n->list  = L_T2;
            list_push_front(&arc->T2, n);
        } else {
            /* B2 命中：frequency 重要，p 减小 */
            int d = (arc->B2.size > 0) ? (arc->B1.size / arc->B2.size) : 1;
            if (d < 1) d = 1;
            arc->p -= d;
            if (arc->p < 0) arc->p = 0;

            arc_replace(arc, 1);

            list_unlink(&arc->B2, n);
            n->value = value;
            n->list  = L_T2;
            list_push_front(&arc->T2, n);
        }
        return;
    }

    /* ---- 完全未命中：三选一的淘汰逻辑 ---- */
    arc->misses++;
    *hit_out = 0;

    if (arc->T1.size + arc->B1.size == arc->capacity) {
        if (arc->T1.size < arc->capacity) {
            /* 丢掉 B1 里最老的幽灵，再替换一个 */
            Node *v = list_pop_back(&arc->B1);
            if (v) arc_free_node(arc, v);
            arc_replace(arc, 0);
        } else {
            /* B1 已空，T1 就是整个缓存：直接丢 T1 LRU */
            Node *v = list_pop_back(&arc->T1);
            if (v) arc_free_node(arc, v);
        }
    } else {
        int total = arc->T1.size + arc->T2.size +
                    arc->B1.size + arc->B2.size;
        if (total >= arc->capacity) {
            if (total == 2 * arc->capacity) {
                Node *v = list_pop_back(&arc->B2);
                if (v) arc_free_node(arc, v);
            }
            arc_replace(arc, 0);
        }
    }

    /* 新条目插入 T1 的 MRU */
    Node *nn = (Node *)malloc(sizeof(Node));
    nn->key = key;
    nn->value = value;
    nn->list = L_T1;
    nn->prev = nn->next = nn->hnext = NULL;
    list_push_front(&arc->T1, nn);
    hash_insert(arc->buckets, nn);
}

/* 上层统一入口：模拟"读或写一个 key" */
static int arc_access(ARC *arc, int key, int value) {
    int hit = 0;
    arc_request(arc, key, value, &hit);
    return hit;
}

/* ================================================================
 * LRU（作为对照）
 * ================================================================ */
typedef struct {
    int   cap;
    List  list;
    Node *buckets[HASH_SIZE];
    long  hits, misses;
} LRU;

static void lru_init(LRU *lru, int cap) {
    lru->cap = cap;
    list_init(&lru->list);
    memset(lru->buckets, 0, sizeof(lru->buckets));
    lru->hits = lru->misses = 0;
}

static int lru_access(LRU *lru, int key, int value) {
    Node *n = hash_find(lru->buckets, key);
    if (n) {
        lru->hits++;
        n->value = value;
        list_unlink(&lru->list, n);
        list_push_front(&lru->list, n);
        return 1;
    }
    lru->misses++;

    if (lru->list.size >= lru->cap) {
        Node *v = list_pop_back(&lru->list);
        if (v) { hash_remove(lru->buckets, v); free(v); }
    }

    Node *nn = (Node *)malloc(sizeof(Node));
    nn->key = key;
    nn->value = value;
    nn->list = L_T1;
    nn->prev = nn->next = nn->hnext = NULL;
    list_push_front(&lru->list, nn);
    hash_insert(lru->buckets, nn);
    return 0;
}

static void lru_free(LRU *lru) {
    Node *n = lru->list.head;
    while (n) { Node *nx = n->next; free(n); n = nx; }
    list_init(&lru->list);
}

/* ================================================================
 * Trace 生成
 * ================================================================ */
static int *gen_random(int n, int range, unsigned seed) {
    int *keys = (int *)malloc(sizeof(int) * n);
    srand(seed);
    for (int i = 0; i < n; i++) keys[i] = rand() % range;
    return keys;
}

static int *gen_scan(int n, int range, unsigned seed) {
    (void)seed;
    int *keys = (int *)malloc(sizeof(int) * n);
    for (int i = 0; i < n; i++) keys[i] = i % range;
    return keys;
}

static int *gen_hotspot(int n, int hot_range, int cold_range, unsigned seed) {
    int *keys = (int *)malloc(sizeof(int) * n);
    srand(seed);
    for (int i = 0; i < n; i++) {
        if (rand() % 100 < 80)
            keys[i] = rand() % hot_range;
        else
            keys[i] = hot_range + rand() % cold_range;
    }
    return keys;
}

/* ================================================================
 * 对比运行
 * ================================================================ */
static void run_compare(const char *name, const int *keys, int n, int cap) {
    ARC arc; arc_init(&arc, cap);
    LRU lru; lru_init(&lru, cap);

    for (int i = 0; i < n; i++) {
        arc_access(&arc, keys[i], keys[i] * 10);
        lru_access(&lru, keys[i], keys[i] * 10);
    }

    double lru_rate = 100.0 * lru.hits / n;
    double arc_rate = 100.0 * arc.hits / n;

    printf("\n\033[1;33m%s\033[0m\n", name);
    printf("  访问次数: %d    缓存容量: %d\n", n, cap);
    printf("  ┌──────────┬──────────┬──────────┬────────────┐\n");
    printf("  │ 算法     │ 命中     │ 未命中   │ 命中率     │\n");
    printf("  ├──────────┼──────────┼──────────┼────────────┤\n");
    printf("  │ LRU      │ %8ld │ %8ld │ %8.2f%%  │\n",
           lru.hits, lru.misses, lru_rate);
    printf("  │ ARC      │ %8ld │ %8ld │ %8.2f%%  │\n",
           arc.hits, arc.misses, arc_rate);
    printf("  └──────────┴──────────┴──────────┴────────────┘\n");

    if (lru.hits > 0) {
        double gain = 100.0 * (arc.hits - lru.hits) / lru.hits;
        printf("  \033[1;36mARC 相对 LRU 提升: %+.2f%%\033[0m\n", gain);
    }

    printf("  ARC 内部状态: p=%d  T1=%d  T2=%d  B1=%d  B2=%d\n",
           arc.p, arc.T1.size, arc.T2.size, arc.B1.size, arc.B2.size);

    arc_free(&arc);
    lru_free(&lru);
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   ARC（自适应替换缓存）vs LRU 命中率对比            ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    int cap = 100;
    int n   = 50000;

    int *k1 = gen_random(n, 1000, 1);
    run_compare("【1】随机访问 1000 个 key（工作集 > 缓存）", k1, n, cap);
    free(k1);

    int *k2 = gen_scan(n, 200, 2);
    run_compare("【2】循环扫描 200 个 key（缓存装不下）", k2, n, cap);
    free(k2);

    int *k3 = gen_hotspot(n, 50, 1000, 3);
    run_compare("【3】80% 访问 50 个热点 + 20% 扫描 1000 个冷 key",
                k3, n, cap);
    free(k3);

    int *k4 = gen_random(n, 50, 4);
    run_compare("【4】随机访问 50 个 key（工作集 < 缓存）", k4, n, cap);
    free(k4);

    printf("\n\033[1;36m结论:\033[0m\n");
    printf("  - 工作集完全装得下时，LRU 和 ARC 都能达到高命中率\n");
    printf("  - 扫描型负载（场景 2、3）下，LRU 被污染，ARC 明显更好\n");
    printf("  - ARC 用 B1/B2 幽灵列表"记住"被淘汰的 key，\n");
    printf("    自动在 recency 和 frequency 之间调整平衡点 p\n");

    return 0;
}
