/* concurrency.c —— 2PL 与 MVCC 并发控制对比
 *
 * 编译: gcc -Wall -O2 -std=c11 -o concurrency concurrency.c
 * 运行: ./concurrency
 *
 * 两个模块:
 *   1. 严格两阶段锁（Strict 2PL）—— 读写都加锁, 提交时释放
 *      · 阻塞式调度
 *      · 死锁检测（等待图找环）
 *   2. MVCC —— 每个数据项保留多个版本
 *      · 读永不阻塞
 *      · 写创建新版本
 *      · 快照隔离: 每个事务看到一致的快照
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

/* ================================================================
 * 数据模型
 * ================================================================ */
#define N_TXNS    4
#define N_ITEMS   3
#define MAX_STEPS 16

typedef struct {
    int  txn;
    char op;         /* 'R' 读, 'W' 写, 'C' 提交 */
    int  item;
    int  value;      /* 写时的值 */
} Op;

static Op   g_schedule[MAX_STEPS];
static int  g_nsteps = 0;

static void add_op(int txn, char op, int item, int value) {
    g_schedule[g_nsteps++] = (Op){txn, op, item, value};
}

static const char *op_text(Op *o) {
    static char buf[32];
    if (o->op == 'C') snprintf(buf, sizeof(buf), "T%d COMMIT", o->txn);
    else snprintf(buf, sizeof(buf), "T%d %c%d%s", o->txn, o->op, o->item,
                  o->op == 'W' ? "" : "");
    return buf;
}

/* ================================================================
 * ================================================================
 *                    模块一: 严格两阶段锁
 * ================================================================
 * ================================================================ */

typedef enum { LOCK_NONE, LOCK_SHARED, LOCK_EXCLUSIVE } LockMode;

typedef struct {
    LockMode mode;
    int      holder;         /* 持锁事务, -1 = 空闲 */
    int      waiters[8];     /* 等待中的事务 */
    int      n_waiters;
} LockTable;

typedef struct {
    int  id;
    bool active;
    int  blocked_on_item;    /* -1 = 不阻塞 */
    int  blocked_on_txn;     /* -1 = 不阻塞, 否则谁持有 */
} TxnState;

typedef struct {
    LockTable  locks[N_ITEMS];
    TxnState   txns[N_TXNS + 1];
    int        wait_graph[N_TXNS + 1][N_TXNS + 1];
    int        values[N_ITEMS];
    char       trace[64][64];
    int        n_trace;
} TwoPLState;

static void twopl_init(TwoPLState *s) {
    memset(s, 0, sizeof(*s));
    for (int i = 0; i < N_ITEMS; i++) {
        s->locks[i].mode = LOCK_NONE;
        s->locks[i].holder = -1;
        s->locks[i].n_waiters = 0;
    }
    for (int i = 1; i <= N_TXNS; i++) {
        s->txns[i].id = i;
        s->txns[i].active = true;
        s->txns[i].blocked_on_item = -1;
        s->txns[i].blocked_on_txn = -1;
    }
    s->values[0] = 100;
    s->values[1] = 200;
    s->values[2] = 300;
}

static void twopl_log(TwoPLState *s, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(s->trace[s->n_trace], 64, fmt, ap);
    va_end(ap);
    s->n_trace++;
}

#include <stdarg.h>

/* 返回: 0 = 成功, -1 = 阻塞 */
static int twopl_acquire(TwoPLState *s, int txn, int item, LockMode want) {
    LockTable *l = &s->locks[item];

    /* 已经持有锁? 升级模式 */
    if (l->holder == txn) {
        if (want == LOCK_EXCLUSIVE && l->mode == LOCK_SHARED) {
            /* 想升级: 如果还有别的读者, 阻塞 (简化处理: 直接失败) */
            return 0;
        }
        return 0;
    }

    /* 空闲 → 直接拿 */
    if (l->holder == -1 && l->n_waiters == 0) {
        l->holder = txn;
        l->mode   = want;
        return 0;
    }

    /* 共享 + 已共享 → 兼容 */
    if (want == LOCK_SHARED && l->mode == LOCK_SHARED) {
        /* 简化: 允许多读者, 用 holder 记录 "第一个" 读者,
         * 用 n_waiters 记录其他读者 */
        l->n_waiters++;
        return 0;
    }

    /* 冲突: 记录等待 */
    if (l->holder >= 0) {
        s->wait_graph[txn][l->holder] = 1;
        s->txns[txn].blocked_on_item = item;
        s->txns[txn].blocked_on_txn  = l->holder;
    }
    return -1;
}

static void twopl_release_all(TwoPLState *s, int txn) {
    for (int i = 0; i < N_ITEMS; i++) {
        if (s->locks[i].holder == txn) {
            s->locks[i].holder = -1;
            s->locks[i].mode   = LOCK_NONE;
            s->locks[i].n_waiters = 0;
        }
        /* 清理等待图 */
        memset(s->wait_graph[txn], 0, sizeof(s->wait_graph[txn]));
        for (int j = 1; j <= N_TXNS; j++)
            s->wait_graph[j][txn] = 0;
    }
}

/* 等待图找环 */
static bool dfs_cycle(int g[N_TXNS + 1][N_TXNS + 1], int v,
                      int *visiting, int *visited) {
    visiting[v] = 1;
    for (int u = 1; u <= N_TXNS; u++) {
        if (!g[v][u]) continue;
        if (visiting[u]) return true;
        if (!visited[u] && dfs_cycle(g, u, visiting, visited)) return true;
    }
    visiting[v] = 0;
    visited[v] = 1;
    return false;
}

static bool twopl_has_deadlock(TwoPLState *s, int *out_txn) {
    int visiting[N_TXNS + 1] = {0};
    int visited[N_TXNS + 1]  = {0};

    for (int i = 1; i <= N_TXNS; i++) {
        if (visited[i]) continue;
        if (dfs_cycle(s->wait_graph, i, visiting, visited)) {
            *out_txn = i;
            return true;
        }
    }
    return false;
}

static void run_2pl(void) {
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   模块一: 严格两阶段锁（Strict 2PL）                 ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    TwoPLState s;
    twopl_init(&s);

    printf("\n  初始: A=%d B=%d C=%d\n",
           s.values[0], s.values[1], s.values[2]);

    printf("\n  调度:\n");
    printf("    T1: R(A) W(B) C\n");
    printf("    T2: R(B) W(A) C\n");
    printf("  这两个事务以不同顺序访问同一对资源 —— 经典死锁模式\n\n");

    int pc[N_TXNS + 1] = {0, 0, 0, 0, 0};

    /* 硬编码的调度: T1 先拿 A, T2 先拿 B, 然后互相等待 */
    printf("\033[1;33m  --- 步骤 1: T1 读 A ---\033[0m\n");
    if (twopl_acquire(&s, 1, 0, LOCK_SHARED) == 0) {
        printf("    T1 获取 A 的共享锁 ✓\n");
        printf("    T1 读到 A=%d\n", s.values[0]);
    }

    printf("\n\033[1;33m  --- 步骤 2: T2 读 B ---\033[0m\n");
    if (twopl_acquire(&s, 2, 1, LOCK_SHARED) == 0) {
        printf("    T2 获取 B 的共享锁 ✓\n");
        printf("    T2 读到 B=%d\n", s.values[1]);
    }

    printf("\n\033[1;33m  --- 步骤 3: T1 写 B ---\033[0m\n");
    if (twopl_acquire(&s, 1, 1, LOCK_EXCLUSIVE) < 0) {
        printf("    T1 请求 B 的排它锁 —— \033[1;31m阻塞\033[0m (T2 持有 B)\n");
        printf("    等待图加边: T1 → T2\n");
    }

    printf("\n\033[1;33m  --- 步骤 4: T2 写 A ---\033[0m\n");
    if (twopl_acquire(&s, 2, 0, LOCK_EXCLUSIVE) < 0) {
        printf("    T2 请求 A 的排它锁 —— \033[1;31m阻塞\033[0m (T1 持有 A)\n");
        printf("    等待图加边: T2 → T1\n");
    }

    /* 检测死锁 */
    printf("\n\033[1;33m  --- 死锁检测 ---\033[0m\n");
    printf("    等待图:\n");
    printf("      T1 ──→ T2\n");
    printf("      T2 ──→ T1\n");

    int victim;
    if (twopl_has_deadlock(&s, &victim)) {
        printf("\n    \033[1;31m✗ 检测到死锁! 环包含 T%d\033[0m\n", victim);
        printf("    \033[1;33m选择牺牲者: T%d (撤销)\033[0m\n", victim);

        twopl_release_all(&s, victim);
        s.txns[victim].active = false;

        printf("    T%d 释放所有锁, 另一个事务解除阻塞\n", victim);

        int other = (victim == 1) ? 2 : 1;
        printf("    T%d 继续执行, 完成:\n", other);

        if (other == 1) {
            printf("      T1 获取 B 的排它锁 ✓\n");
            s.values[1] = 111;
            printf("      T1: B = 111\n");
            printf("      T1 COMMIT\n");
        } else {
            printf("      T2 获取 A 的排它锁 ✓\n");
            s.values[0] = 222;
            printf("      T2: A = 222\n");
            printf("      T2 COMMIT\n");
        }
    } else {
        printf("    未检测到死锁\n");
    }

    printf("\n\033[1;36m  最终状态:\033[0m A=%d B=%d C=%d\n",
           s.values[0], s.values[1], s.values[2]);

    printf("\n  \033[1;36m2PL 的特点:\033[0m\n");
    printf("    · 加锁 → 读写互斥, 串行化保证强\n");
    printf("    · 可能死锁 → 需要检测/预防机制\n");
    printf("    · 读也要加锁 → 读者之间可以并行, 但读写不能\n");
    printf("    · 严格 2PL: 提交时才释放所有锁, 避免级联回滚\n");
}

/* ================================================================
 * ================================================================
 *                        模块二: MVCC
 * ================================================================
 * ================================================================ */

#define MAX_VERSIONS 8

typedef struct {
    int  value;
    int  txn_id;         /* 哪个事务写的 */
    int  begin_ts;       /* 本版本有效起始时刻 */
    int  end_ts;         /* 被覆盖的时刻, 0 = 仍然有效 */
    bool committed;
} Version;

typedef struct {
    Version versions[MAX_VERSIONS];
    int     n;
} ItemHistory;

typedef struct {
    int   id;
    int   start_ts;      /* 事务开始时的快照时刻 */
    bool  active;
    int   writes[N_ITEMS];
    int   write_vals[N_ITEMS];
    bool  write_pending[N_ITEMS];
} MVCCState;

static ItemHistory g_items[N_ITEMS];
static MVCCState   g_mvtxn[N_TXNS + 1];
static int         g_clock = 1;

static void mvcc_init(void) {
    memset(g_items, 0, sizeof(g_items));
    memset(g_mvtxn, 0, sizeof(g_mvtxn));

    int initial[] = {100, 200, 300};
    for (int i = 0; i < N_ITEMS; i++) {
        g_items[i].versions[0].value     = initial[i];
        g_items[i].versions[0].txn_id    = 0;
        g_items[i].versions[0].begin_ts  = 0;
        g_items[i].versions[0].end_ts    = 0;
        g_items[i].versions[0].committed = true;
        g_items[i].n = 1;
    }
    g_clock = 1;
}

static int mvcc_begin(int txn_id) {
    MVCCState *t = &g_mvtxn[txn_id];
    t->id = txn_id;
    t->start_ts = g_clock++;
    t->active = true;
    for (int i = 0; i < N_ITEMS; i++)
        t->write_pending[i] = false;
    return t->start_ts;
}

/* 读: 找"开始时刻之前已提交, 且尚未被覆盖"的版本 */
static int mvcc_read(int txn_id, int item, int *out_version_idx) {
    MVCCState *t = &g_mvtxn[txn_id];
    ItemHistory *h = &g_items[item];

    /* 先看自己有没有未提交的写 */
    if (t->write_pending[item]) {
        if (out_version_idx) *out_version_idx = -1;
        return t->write_vals[item];
    }

    int best = -1;
    for (int i = 0; i < h->n; i++) {
        Version *v = &h->versions[i];

        /* 未提交的版本跳过（除了自己的, 前面已处理） */
        if (!v->committed) continue;

        /* 起始时间要早于事务开始的快照 */
        if (v->begin_ts >= t->start_ts) continue;

        /* 版本还未被"某个已提交事务"覆盖, 或者覆盖它的版本
         * 是在本事务开始之后才提交的 */
        if (best < 0 || v->begin_ts > h->versions[best].begin_ts)
            best = i;
    }

    if (out_version_idx) *out_version_idx = best;
    return best >= 0 ? h->versions[best].value : -1;
}

static void mvcc_write(int txn_id, int item, int value) {
    MVCCState *t = &g_mvtxn[txn_id];
    t->write_pending[item] = true;
    t->write_vals[item]    = value;
}

static void mvcc_commit(int txn_id) {
    MVCCState *t = &g_mvtxn[txn_id];
    int commit_ts = g_clock++;

    for (int i = 0; i < N_ITEMS; i++) {
        if (!t->write_pending[i]) continue;

        ItemHistory *h = &g_items[i];

        /* 把旧版本"关闭" */
        if (h->n > 0) {
            Version *last = &h->versions[h->n - 1];
            if (last->end_ts == 0)
                last->end_ts = commit_ts;
        }

        /* 追加新版本 */
        Version *v = &h->versions[h->n++];
        v->value     = t->write_vals[i];
        v->txn_id    = txn_id;
        v->begin_ts  = commit_ts;
        v->end_ts    = 0;
        v->committed = true;
    }
    t->active = false;
}

static void run_mvcc(void) {
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   模块二: MVCC（多版本并发控制）                     ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    mvcc_init();

    printf("\n  初始: A=%d B=%d C=%d\n",
           g_items[0].versions[0].value,
           g_items[1].versions[0].value,
           g_items[2].versions[0].value);

    printf("\n  调度:\n");
    printf("    T1 开始 (快照 S1)\n");
    printf("    T2 开始 (快照 S2)\n");
    printf("    T1: R(A) W(A, 150) 提交\n");
    printf("    T2: R(A) —— 读到 T1 修改前的旧值!（快照隔离）\n");
    printf("    T2: W(B, 250) 提交\n\n");

    /* T1 和 T2 几乎同时开始 */
    int ts1 = mvcc_begin(1);
    printf("\033[1;33m  --- T1 BEGIN, start_ts=%d ---\033[0m\n", ts1);

    int ts2 = mvcc_begin(2);
    printf("\033[1;33m  --- T2 BEGIN, start_ts=%d ---\033[0m\n", ts2);

    /* T1 读 A */
    printf("\n\033[1;33m  --- T1: R(A) ---\033[0m\n");
    int v = mvcc_read(1, 0, NULL);
    printf("    T1 读到 A=%d (版本 begin_ts=0)\n", v);

    /* T1 写 A */
    printf("\n\033[1;33m  --- T1: W(A, 150) ---\033[0m\n");
    mvcc_write(1, 0, 150);
    printf("    T1 写入 A=150 (暂存在事务私有空间, 未落盘)\n");

    /* T2 读 A —— 应该看到旧值 100 */
    printf("\n\033[1;33m  --- T2: R(A) ---\033[0m\n");
    int v2 = mvcc_read(2, 0, NULL);
    printf("    T2 读到 A=%d  ", v2);
    if (v2 == 100)
        printf("\033[1;32m← 旧版本! 未被 T1 的写阻塞\033[0m\n");
    else
        printf("(不对, 应该读到 100)\n");

    /* T1 提交 */
    printf("\n\033[1;33m  --- T1 COMMIT ---\033[0m\n");
    mvcc_commit(1);
    printf("    T1 提交, 写入时钟 %d\n", g_clock - 1);

    /* T2 再读 A —— 快照在 T1 提交之前, 仍应看到旧值 */
    printf("\n\033[1;33m  --- T2: 再读 R(A) ---\033[0m\n");
    v2 = mvcc_read(2, 0, NULL);
    printf("    T2 读到 A=%d  ", v2);
    if (v2 == 100)
        printf("\033[1;32m← 快照隔离: 仍看到自己快照下的值\033[0m\n");

    /* T2 写 B */
    printf("\n\033[1;33m  --- T2: W(B, 250) ---\033[0m\n");
    mvcc_write(2, 1, 250);
    printf("    T2 写入 B=250\n");

    /* T2 提交 */
    printf("\n\033[1;33m  --- T2 COMMIT ---\033[0m\n");
    mvcc_commit(2);
    printf("    T2 提交, 写入时钟 %d\n", g_clock - 1);

    /* 新事务 T3 开始, 应该看到所有已提交的最新值 */
    printf("\n\033[1;33m  --- T3 BEGIN (在 T1, T2 之后) ---\033[0m\n");
    mvcc_begin(3);
    int vA = mvcc_read(3, 0, NULL);
    int vB = mvcc_read(3, 1, NULL);
    int vC = mvcc_read(3, 2, NULL);
    printf("    T3 读到 A=%d B=%d C=%d\n", vA, vB, vC);
    printf("    \033[1;32m← 看到所有已提交的最新值\033[0m\n");

    /* 版本历史 */
    printf("\n\033[1;36m  [版本链]\033[0m\n");
    for (int i = 0; i < N_ITEMS; i++) {
        printf("    项 %c: ", 'A' + i);
        for (int j = 0; j < g_items[i].n; j++) {
            Version *v = &g_items[i].versions[j];
            printf("[v=%d ts=%d", v->value, v->begin_ts);
            if (v->end_ts) printf(",被覆盖@%d", v->end_ts);
            printf("] ");
        }
        printf("\n");
    }

    printf("\n  \033[1;36mMVCC 的特点:\033[0m\n");
    printf("    · 读不阻塞, 写不阻塞读 —— 各看各的版本\n");
    printf("    · 写不冲突, 但语义冲突（写偏斜）需要额外检测\n");
    printf("    · 快照隔离: 事务看到开始时刻的稳定视图\n");
    printf("    · 需要垃圾回收: 老版本何时能删\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   并发控制: 两阶段锁（2PL） vs 多版本（MVCC）                ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    run_2pl();
    run_mvcc();

    printf("\n\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   两种策略对比                                                ║\n");
    printf("╠═══════════════════════════════════════════════════════════════╣\n");
    printf("║                      2PL               MVCC                   ║\n");
    printf("║   ────────────────  ────────────────  ─────────────────────  ║\n");
    printf("║   读操作            加共享锁, 可能等   永远不阻塞              ║\n");
    printf("║   写操作            加排它锁, 可能等   写新版本                ║\n");
    printf("║   读-写冲突         阻塞              各看各的版本            ║\n");
    printf("║   写-写冲突         阻塞              仅串行提交时检测        ║\n");
    printf("║   死锁              可能, 需检测       不会（不阻塞）          ║\n");
    printf("║   隔离级别          可串行化           快照隔离（默认）        ║\n");
    printf("║   空间开销          低（一把锁）       高（多版本）            ║\n");
    printf("║   典型系统          MySQL 早期 / DB2   PostgreSQL / Oracle    ║\n");
    printf("║                                                               ║\n");
    printf("║   实际生产里两者常混合使用:                                   ║\n");
    printf("║     · MVCC 处理读, 底层用 2PL 保证写-写串行                   ║\n");
    printf("║     · PostgreSQL 叫 MVCC + SSI（可串行化快照隔离）            ║\n");
    printf("║     · MySQL InnoDB 叫 MVCC + 间隙锁                           ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}