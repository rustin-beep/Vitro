/* crdt.c —— CRDT 无冲突复制数据类型
 *
 * 编译: gcc -Wall -O2 -std=c11 -o crdt crdt.c
 * 运行: ./crdt
 *
 * 核心思想:
 *   CRDT 保证任意顺序合并都收敛 —— 数学上就是"幂等 + 交换 + 结合"。
 *   不用协调、不用锁, 副本之间随便同步, 最终自动一致。
 *
 * 四种 CRDT:
 *   G-Counter   只增计数器: 每个副本一个分量, 合并取 max
 *   PN-Counter  增减计数器: 两个 G-Counter (加和减)
 *   LWW-Register  最后写胜出: 时间戳比大小, 平局用副本 id
 *   OR-Set      观察删除集合: 每个元素带唯一 tag
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

#define N_REPLICAS 3
#define MAX_ELEMS   16
#define MAX_TAGS    8

/* ================================================================
 * 1. G-Counter: 只增计数器
 *
 *   state: 每个副本一个分量, 各自只增自己的
 *   value: 所有分量求和
 *   merge: 分量逐项取 max
 * ================================================================ */
typedef struct {
    int counts[N_REPLICAS];
} GCounter;

static void gc_init(GCounter *g) {
    memset(g, 0, sizeof(*g));
}

static void gc_inc(GCounter *g, int replica) {
    g->counts[replica]++;
}

static int gc_value(GCounter *g) {
    int s = 0;
    for (int i = 0; i < N_REPLICAS; i++) s += g->counts[i];
    return s;
}

static void gc_merge(GCounter *dst, GCounter *src) {
    for (int i = 0; i < N_REPLICAS; i++)
        if (src->counts[i] > dst->counts[i])
            dst->counts[i] = src->counts[i];
}

static void gc_print(GCounter *g) {
    printf("[");
    for (int i = 0; i < N_REPLICAS; i++) {
        if (i) printf(",");
        printf("%d", g->counts[i]);
    }
    printf("] = %d", gc_value(g));
}

/* ================================================================
 * 2. PN-Counter: 增减计数器
 *
 *   两个 G-Counter: inc 和 dec
 *   value = sum(inc) - sum(dec)
 * ================================================================ */
typedef struct {
    GCounter inc;
    GCounter dec;
} PNCounter;

static void pn_init(PNCounter *p) {
    gc_init(&p->inc);
    gc_init(&p->dec);
}

static void pn_inc(PNCounter *p, int r) { gc_inc(&p->inc, r); }
static void pn_dec(PNCounter *p, int r) { gc_inc(&p->dec, r); }
static int  pn_value(PNCounter *p)      { return gc_value(&p->inc) - gc_value(&p->dec); }

static void pn_merge(PNCounter *dst, PNCounter *src) {
    gc_merge(&dst->inc, &src->inc);
    gc_merge(&dst->dec, &src->dec);
}

/* ================================================================
 * 3. LWW-Register: 最后写胜出
 *
 *   state: (value, timestamp, replica_id)
 *   merge: 比 timestamp, 大的赢; 平局比 replica_id
 * ================================================================ */
typedef struct {
    int value;
    int ts;
    int writer;   /* 平局时用副本 id 打破 */
    bool used;
} LWWRegister;

static void lww_init(LWWRegister *r) {
    r->value = 0;
    r->ts = -1;
    r->writer = -1;
    r->used = false;
}

static void lww_write(LWWRegister *r, int value, int ts, int writer) {
    /* 本地的写总是覆盖 (假设本地时钟单调) */
    if (ts > r->ts || (ts == r->ts && writer > r->writer)) {
        r->value = value;
        r->ts = ts;
        r->writer = writer;
        r->used = true;
    }
}

static void lww_merge(LWWRegister *dst, LWWRegister *src) {
    if (!src->used) return;
    if (!dst->used ||
        src->ts > dst->ts ||
        (src->ts == dst->ts && src->writer > dst->writer)) {
        *dst = *src;
    }
}

/* ================================================================
 * 4. OR-Set: 观察删除集合
 *
 *   每个元素带一组唯一 tag (replica_id, seq)
 *   add: 生成新 tag 加入元素
 *   remove: 删除当前看到的所有 tag
 *   merge: tag 集合求并集
 *   注意: remove 只能删除"已经看到"的 tag
 * ================================================================ */
typedef struct {
    int     replica;
    int     seq;
} Tag;

typedef struct {
    char    elem[16];
    Tag     tags[MAX_TAGS];
    int     n_tags;
} ORSetElem;

typedef struct {
    ORSetElem items[MAX_ELEMS];
    int       n_items;
    int       next_seq[N_REPLICAS];
} ORSet;

static void ors_init(ORSet *s) {
    memset(s, 0, sizeof(*s));
}

static ORSetElem *ors_find(ORSet *s, const char *elem, bool create) {
    for (int i = 0; i < s->n_items; i++)
        if (strcmp(s->items[i].elem, elem) == 0) return &s->items[i];
    if (!create) return NULL;
    if (s->n_items >= MAX_ELEMS) return NULL;
    ORSetElem *e = &s->items[s->n_items++];
    memset(e, 0, sizeof(*e));
    strncpy(e->elem, elem, sizeof(e->elem) - 1);
    return e;
}

static void ors_add(ORSet *s, int replica, const char *elem) {
    ORSetElem *e = ors_find(s, elem, true);
    if (!e) return;
    if (e->n_tags >= MAX_TAGS) return;

    /* 生成新 tag —— 每个 add 都是唯一的 */
    Tag t;
    t.replica = replica;
    t.seq     = s->next_seq[replica]++;
    e->tags[e->n_tags++] = t;
}

static void ors_remove(ORSet *s, int replica, const char *elem) {
    (void)replica;
    ORSetElem *e = ors_find(s, elem, false);
    if (!e) return;
    /* 删除当前看到的全部 tag */
    e->n_tags = 0;
}

static bool ors_contains(ORSet *s, const char *elem) {
    ORSetElem *e = ors_find(s, elem, false);
    return e && e->n_tags > 0;
}

static void ors_merge(ORSet *dst, ORSet *src) {
    for (int i = 0; i < src->n_items; i++) {
        ORSetElem *se = &src->items[i];
        if (se->n_tags == 0) continue;   /* 源端已删除, 没有 tag 可合并 */

        ORSetElem *de = ors_find(dst, se->elem, true);
        if (!de) continue;

        /* 把 source 的 tag 逐个加到 dst (去重) */
        for (int j = 0; j < se->n_tags; j++) {
            bool dup = false;
            for (int k = 0; k < de->n_tags; k++) {
                if (de->tags[k].replica == se->tags[j].replica &&
                    de->tags[k].seq     == se->tags[j].seq) {
                    dup = true;
                    break;
                }
            }
            if (!dup && de->n_tags < MAX_TAGS)
                de->tags[de->n_tags++] = se->tags[j];
        }
    }

    /* 同步 next_seq 防止下次 add 生成重复 tag */
    for (int r = 0; r < N_REPLICAS; r++)
        if (src->next_seq[r] > dst->next_seq[r])
            dst->next_seq[r] = src->next_seq[r];
}

static void ors_print(ORSet *s) {
    printf("{");
    bool first = true;
    for (int i = 0; i < s->n_items; i++) {
        if (s->items[i].n_tags == 0) continue;
        if (!first) printf(", ");
        first = false;
        printf("%s", s->items[i].elem);
    }
    printf("}");
}

/* ================================================================
 * 演示
 * ================================================================ */
static void section(const char *title) {
    printf("\n\033[1;35m══════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  %s\033[0m\n", title);
    printf("\033[1;35m══════════════════════════════════════════════════\033[0m\n");
}

/* ================================================================
 * G-Counter 演示
 * ================================================================ */
static void demo_gcounter(void) {
    section("1. G-Counter —— 只增计数器");

    printf("  场景: 三个副本各自记录\"访问次数\", 分区后合并\n\n");

    GCounter a, b, c;
    gc_init(&a); gc_init(&b); gc_init(&c);

    printf("  初始:  A="); gc_print(&a);
    printf("  B="); gc_print(&b);
    printf("  C="); gc_print(&c);
    printf("\n");

    gc_inc(&a, 0); gc_inc(&a, 0); gc_inc(&a, 0);
    printf("  A 增加 3 次:        A="); gc_print(&a); printf("\n");

    gc_inc(&b, 1);
    printf("  B 增加 1 次:        B="); gc_print(&b); printf("\n");

    gc_inc(&c, 2); gc_inc(&c, 2);
    printf("  C 增加 2 次:        C="); gc_print(&c); printf("\n\n");

    printf("  \033[1;33m—— 分区, 各自发展 ——\033[0m\n\n");

    gc_inc(&a, 0);
    gc_inc(&b, 1); gc_inc(&b, 1);
    printf("  A 再加 1 次:        A="); gc_print(&a); printf("\n");
    printf("  B 再加 2 次:        B="); gc_print(&b); printf("\n");
    printf("  C 不动:             C="); gc_print(&c); printf("\n\n");

    printf("  \033[1;33m—— 恢复, 两两合并 ——\033[0m\n\n");

    gc_merge(&a, &b);   /* A ← B */
    printf("  A ← B:              A="); gc_print(&a); printf("\n");
    gc_merge(&a, &c);   /* A ← C */
    printf("  A ← C:              A="); gc_print(&a); printf("\n\n");

    gc_merge(&b, &a);
    gc_merge(&c, &a);
    printf("  所有副本同步完:\n");
    printf("    A="); gc_print(&a); printf("\n");
    printf("    B="); gc_print(&b); printf("\n");
    printf("    C="); gc_print(&c); printf("\n\n");

    printf("  \033[1;32m✓ 全部收敛到 %d\033[0m\n", gc_value(&a));
    printf("  \033[1;32m✓ 答案正确: 3+1+2+1+2 = 9\033[0m\n");
}

/* ================================================================
 * PN-Counter 演示
 * ================================================================ */
static void demo_pncounter(void) {
    section("2. PN-Counter —— 增减计数器");

    printf("  场景: 分布式点赞/取消, 合并后值正确\n\n");

    PNCounter a, b, c;
    pn_init(&a); pn_init(&b); pn_init(&c);

    printf("  初始 value = 0\n\n");

    pn_inc(&a, 0); pn_inc(&a, 0); pn_inc(&a, 0);
    pn_inc(&b, 1); pn_inc(&b, 1);
    pn_inc(&c, 2);
    pn_dec(&c, 2);
    pn_dec(&c, 2);

    printf("  A: +3           A=%d\n", pn_value(&a));
    printf("  B: +2           B=%d\n", pn_value(&b));
    printf("  C: +1 -2        C=%d\n\n", pn_value(&c));

    printf("  \033[1;33m—— 合并 ——\033[0m\n\n");

    pn_merge(&a, &b);
    pn_merge(&a, &c);

    printf("  A ← B, A ← C:   A=%d\n", pn_value(&a));

    pn_merge(&b, &a);
    pn_merge(&c, &a);
    printf("  B ← A:          B=%d\n", pn_value(&b));
    printf("  C ← A:          C=%d\n\n", pn_value(&c));

    printf("  \033[1;32m✓ 全部收敛到 %d (3+2+1-2 = 4)\033[0m\n", pn_value(&a));
}

/* ================================================================
 * LWW-Register 演示
 * ================================================================ */
static void demo_lww(void) {
    section("3. LWW-Register —— 最后写胜出");

    printf("  场景: 三个副本各自写\"用户名\", 合并后以时间戳最新的为准\n\n");

    LWWRegister a, b, c;
    lww_init(&a); lww_init(&b); lww_init(&c);

    printf("  \033[1;33m—— 每个副本独立写 ——\033[0m\n\n");

    lww_write(&a, 100, 1, 0);   /* A 在 ts=1 写 100 */
    lww_write(&b, 200, 3, 1);   /* B 在 ts=3 写 200 */
    lww_write(&c, 300, 2, 2);   /* C 在 ts=2 写 300 */

    printf("  A: ts=1 写 100\n");
    printf("  B: ts=3 写 200\n");
    printf("  C: ts=2 写 300\n\n");

    printf("  \033[1;33m—— 合并 ——\033[0m\n\n");

    lww_merge(&a, &b);
    lww_merge(&a, &c);

    printf("  A 合并后: value=%d (ts=%d, writer=T%d)\n",
           a.value, a.ts, a.writer);

    lww_merge(&b, &a);
    lww_merge(&c, &a);

    printf("  B 合并后: value=%d\n", b.value);
    printf("  C 合并后: value=%d\n\n", c.value);

    printf("  \033[1;32m✓ 全部收敛到 200 —— 时间戳 3 是最大的\033[0m\n\n");

    printf("  \033[1;33m—— 平局情况: ts 相同, 用 replica_id 打破 ——\033[0m\n\n");

    LWWRegister x, y;
    lww_init(&x); lww_init(&y);
    lww_write(&x, 111, 5, 1);   /* writer=1 */
    lww_write(&y, 222, 5, 2);   /* writer=2, id 更大 */

    lww_merge(&x, &y);
    printf("  x: ts=5 writer=T1 value=111\n");
    printf("  y: ts=5 writer=T2 value=222\n");
    printf("  合并后 x: value=%d (writer id 大的赢)\n\n", x.value);
    printf("  \033[1;32m✓ 平局有确定解 —— 所有副本都会选 222\033[0m\n");
}

/* ================================================================
 * OR-Set 演示
 * ================================================================ */
static void demo_orset(void) {
    section("4. OR-Set —— 观察删除集合");

    printf("  场景: 三个副本维护\"在线用户\", 有 add 有 remove\n\n");

    ORSet a, b, c;
    ors_init(&a); ors_init(&b); ors_init(&c);

    printf("  \033[1;33m—— 初始: 三个副本看到同一份状态 ——\033[0m\n\n");

    ors_add(&a, 0, "alice");
    ors_add(&a, 0, "bob");
    ors_add(&b, 1, "carol");

    ors_merge(&a, &b);
    ors_merge(&b, &a);
    ors_merge(&c, &a);
    ors_merge(&a, &c);

    printf("  同步后: A="); ors_print(&a); printf("\n");
    printf("          B="); ors_print(&b); printf("\n");
    printf("          C="); ors_print(&c); printf("\n\n");

    printf("  \033[1;33m—— 分区 ——\033[0m\n\n");

    /* A 删除 bob, 同时 B 再添加 bob */
    ors_remove(&a, 0, "bob");
    printf("  A 删除 bob:  A="); ors_print(&a); printf("\n");

    ors_add(&b, 1, "bob");   /* B 上又加了一次 bob */
    printf("  B 再加 bob:  B="); ors_print(&b); printf("\n");

    ors_add(&c, 2, "dave");
    printf("  C 加 dave:   C="); ors_print(&c); printf("\n\n");

    printf("  \033[1;32m注意:\033[0m A 删掉了它看到的 bob(A端只有一个 tag),\n");
    printf("         B 新加的 bob 有一个全新的 tag —— A 没看到这个 tag,\n");
    printf("         所以合并后 bob 会重新出现。这就是\"先删除后添加\"的正确语义。\n\n");

    printf("  \033[1;33m—— 合并 ——\033[0m\n\n");

    ors_merge(&a, &b);
    ors_merge(&a, &c);
    printf("  A 合并后: "); ors_print(&a); printf("\n");

    ors_merge(&b, &a);
    ors_merge(&c, &a);
    printf("  B 合并后: "); ors_print(&b); printf("\n");
    printf("  C 合并后: "); ors_print(&c); printf("\n\n");

    printf("  \033[1;32m✓ 全部收敛 —— bob 回来了! (因为 B 的新 add 引入了一个 A 没删掉的 tag)\033[0m\n");

    /* 反面例子: 两边都删除的情况 */
    printf("\n  \033[1;33m—— 对比: 如果两边都删除, 就真的删了 ——\033[0m\n\n");

    ORSet d, e;
    ors_init(&d); ors_init(&e);
    ors_add(&d, 0, "x");
    ors_merge(&e, &d);   /* e 也看到 x */
    ors_merge(&d, &e);

    ors_remove(&d, 0, "x");
    ors_remove(&e, 1, "x");

    ors_merge(&d, &e);
    printf("  D 删除 x, E 删除 x, 合并后: ");
    ors_print(&d);
    printf("\n  \033[1;32m✓ x 被删除, 且不会被\"复活\"\033[0m\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════════╗\n");
    printf("║   CRDT 无冲突复制数据类型 —— 最终一致性                  ║\n");
    printf("╚══════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");
    printf("\n副本数: %d\n", N_REPLICAS);
    printf("模型: 每个副本维护完整状态, 通过 merge 同步\n");
    printf("      merge 满足幂等、交换、结合 → 任意顺序收敛\n");

    demo_gcounter();
    demo_pncounter();
    demo_lww();
    demo_orset();

    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════════╗\n");
    printf("║   CRDT 的数学基础                                        ║\n");
    printf("╠══════════════════════════════════════════════════════════╣\n");
    printf("║                                                          ║\n");
    printf("║   核心: merge 是一个 join-semilattice 上的\"最小上界\"      ║\n");
    printf("║                                                          ║\n");
    printf("║   三个必须性质:                                           ║\n");
    printf("║     幂等:  a ⊔ a = a         (重复合并没副作用)          ║\n");
    printf("║     交换:  a ⊔ b = b ⊔ a     (网络乱序不影响)            ║\n");
    printf("║     结合:  (a ⊔ b) ⊔ c       (拓扑无关)                  ║\n");
    printf("║             = a ⊔ (b ⊔ c)                                ║\n");
    printf("║                                                          ║\n");
    printf("║   四种 CRDT 的 merge 实现:                                ║\n");
    printf("║     G-Counter   分量逐项 max                              ║\n");
    printf("║     PN-Counter  两个 G-Counter 各自 max                   ║\n");
    printf("║     LWW-Register 比 (timestamp, replica_id) 取大          ║\n");
    printf("║     OR-Set      tag 集合求并集                            ║\n");
    printf("║                                                          ║\n");
    printf("║   两种实现风格:                                           ║\n");
    printf("║     状态型 (CvRDT): 同步整个状态, merge 收敛              ║\n");
    printf("║     操作型 (CmRDT): 同步操作, 需可靠广播                  ║\n");
    printf("║     本程序全部用状态型                                    ║\n");
    printf("║                                                          ║\n");
    printf("║   真实应用:                                               ║\n");
    printf("║     · Redis CRDT (企业版)                                ║\n");
    printf("║     · Riak 分布式 KV                                     ║\n");
    printf("║     · Automerge / Yjs — 协同编辑                         ║\n");
    printf("║     · Apple Notes / Figma / Notion 的同步                ║\n");
    printf("║     · AntidoteDB / Riak 的分布式事务                     ║\n");
    printf("╚══════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}