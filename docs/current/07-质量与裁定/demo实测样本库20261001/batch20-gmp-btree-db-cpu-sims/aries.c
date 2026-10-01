/* aries.c —— ARIES 数据库恢复算法
 *
 * 编译: gcc -Wall -O2 -std=c11 -o aries aries.c
 * 运行: ./aries
 *
 * 场景:
 *   T1: 更新 page1 (100→150), 更新 page2 (200→250), commit, 刷盘
 *   T2: 更新 page3 (300→350), 更新 page1 (150→180), 未提交就崩溃
 *   T3: 更新 page2 (250→280), abort（回滚了）
 *
 * 崩溃后内存页部分丢失, 需要用日志恢复:
 *   Analysis: 重建事务表 + 脏页表
 *   Redo:     从最小 recLSN 重做所有更新（幂等）
 *   Undo:     回滚所有未提交事务, 写 CLR
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

/* ================================================================
 * 常量与类型
 * ================================================================ */
#define MAX_LOG    64
#define MAX_TXNS   8
#define MAX_DIRTY  8
#define MAX_PAGES  8

typedef enum {
    LOG_BEGIN,
    LOG_UPDATE,
    LOG_COMMIT,
    LOG_ABORT,
    LOG_CLR,         /* 补偿日志记录 */
    LOG_CKPT
} LogType;

typedef enum {
    TX_ACTIVE,
    TX_COMMITTED,
    TX_ABORTED
} TxnStatus;

typedef struct {
    int     lsn;
    LogType type;
    int     tid;
    int     page_id;
    int     before;
    int     after;
    int     prev_lsn;         /* 该事务上一条日志 */
    int     undo_next_lsn;    /* CLR 用: 下一条要 undo 的记录 */
} LogRecord;

typedef struct {
    int       tid;
    TxnStatus status;
    int       last_lsn;
    int       undo_next_lsn;
} TxnEntry;

typedef struct {
    int page_id;
    int recLSN;               /* 该页首次变脏时的 LSN */
    int pageLSN;              /* 该页最后一次修改的 LSN */
} DirtyPage;

typedef struct {
    int id;
    int value;
    int pageLSN;
} Page;

/* ================================================================
 * 全局状态
 * ================================================================ */
static LogRecord g_log[MAX_LOG];
static int       g_nlog = 0;

static Page      g_disk[MAX_PAGES];      /* 磁盘上的页 */
static Page      g_mem[MAX_PAGES];       /* 内存中的页 */

static TxnEntry  g_txns[MAX_TXNS];
static int       g_ntxns = 0;

static DirtyPage g_dirty[MAX_DIRTY];
static int       g_ndirty = 0;

/* ================================================================
 * 日志写入
 * ================================================================ */
static int log_append(LogType type, int tid, int page_id,
                      int before, int after, int prev_lsn, int undo_next) {
    int lsn = g_nlog + 1;
    LogRecord *r = &g_log[g_nlog++];
    r->lsn = lsn;
    r->type = type;
    r->tid = tid;
    r->page_id = page_id;
    r->before = before;
    r->after = after;
    r->prev_lsn = prev_lsn;
    r->undo_next_lsn = undo_next;
    return lsn;
}

static const char *log_type_name(LogType t) {
    switch (t) {
    case LOG_BEGIN:   return "BEGIN";
    case LOG_UPDATE:  return "UPDATE";
    case LOG_COMMIT:  return "COMMIT";
    case LOG_ABORT:   return "ABORT";
    case LOG_CLR:     return "CLR";
    case LOG_CKPT:    return "CKPT";
    }
    return "?";
}

/* ================================================================
 * 事务表
 * ================================================================ */
static TxnEntry *txn_get(int tid) {
    for (int i = 0; i < g_ntxns; i++)
        if (g_txns[i].tid == tid) return &g_txns[i];
    return NULL;
}

static TxnEntry *txn_add(int tid) {
    TxnEntry *t = &g_txns[g_ntxns++];
    t->tid = tid;
    t->status = TX_ACTIVE;
    t->last_lsn = 0;
    t->undo_next_lsn = 0;
    return t;
}

/* ================================================================
 * 脏页表
 * ================================================================ */
static DirtyPage *dirty_find(int page_id) {
    for (int i = 0; i < g_ndirty; i++)
        if (g_dirty[i].page_id == page_id) return &g_dirty[i];
    return NULL;
}

static void dirty_mark(int page_id, int lsn) {
    DirtyPage *d = dirty_find(page_id);
    if (!d) {
        d = &g_dirty[g_ndirty++];
        d->page_id = page_id;
        d->recLSN  = lsn;
    }
    d->pageLSN = lsn;
}

/* ================================================================
 * 事务操作
 * ================================================================ */
static int g_next_tid = 1;

static int txn_begin(void) {
    int tid = g_next_tid++;
    TxnEntry *t = txn_add(tid);
    int lsn = log_append(LOG_BEGIN, tid, -1, 0, 0, 0, 0);
    t->last_lsn = lsn;
    return tid;
}

static void txn_update(int tid, int page_id, int new_value) {
    Page *p = &g_mem[page_id];
    int before = p->value;
    int after  = new_value;

    TxnEntry *t = txn_get(tid);

    /* WAL 规则: 先写日志 */
    int lsn = log_append(LOG_UPDATE, tid, page_id,
                         before, after, t->last_lsn, 0);

    /* 更新内存页 */
    p->value   = after;
    p->pageLSN = lsn;

    /* 更新事务表、脏页表 */
    t->last_lsn       = lsn;
    t->undo_next_lsn  = lsn;

    dirty_mark(page_id, lsn);
}

static void txn_commit(int tid) {
    TxnEntry *t = txn_get(tid);
    int lsn = log_append(LOG_COMMIT, tid, -1, 0, 0, t->last_lsn, 0);
    t->last_lsn = lsn;
    t->status   = TX_COMMITTED;

    printf("    T%d COMMIT (LSN=%d)\n", tid, lsn);
}

static void txn_abort(int tid) {
    TxnEntry *t = txn_get(tid);
    int lsn = log_append(LOG_ABORT, tid, -1, 0, 0, t->last_lsn, 0);
    t->last_lsn = lsn;
    t->status   = TX_ABORTED;

    printf("    T%d ABORT (LSN=%d)\n", tid, lsn);

    /* 真正的 abort 会立即回滚; 这里简化为在恢复阶段处理 */
}

/* ================================================================
 * 检查点: 打印当前状态并清空脏页表
 * ================================================================ */
static void checkpoint(void) {
    int lsn = log_append(LOG_CKPT, 0, -1, 0, 0, 0, 0);
    printf("  [检查点] LSN=%d, %d 个脏页\n", lsn, g_ndirty);
    g_ndirty = 0;
}

/* ================================================================
 * 模拟刷盘: 把内存页写回磁盘
 * ================================================================ */
static void flush_page(int page_id) {
    g_disk[page_id] = g_mem[page_id];
    printf("  [刷盘] page%d = %d (pageLSN=%d)\n",
           page_id, g_disk[page_id].value, g_disk[page_id].pageLSN);
}

/* ================================================================
 * 打印
 * ================================================================ */
static void dump_log(void) {
    printf("\n  \033[1;36m[日志]\033[0m\n");
    printf("    LSN  Type    TID  Page  Before  After  PrevLSN  UndoNext\n");
    printf("    ───  ──────  ───  ────  ──────  ─────  ───────  ────────\n");
    for (int i = 0; i < g_nlog; i++) {
        LogRecord *r = &g_log[i];
        printf("    %-3d  %-6s  T%-2d  %-4s  ",
               r->lsn, log_type_name(r->type), r->tid,
               r->page_id >= 0 ? "" : "-");
        if (r->page_id >= 0) printf("%-4d  ", r->page_id);
        else                 printf("      ");
        printf("%-6d  %-5d  %-7d  %d\n",
               r->before, r->after, r->prev_lsn, r->undo_next_lsn);
    }
}

static void dump_state(const char *title) {
    printf("\n  \033[1;36m[%s]\033[0m\n", title);
    printf("    磁盘: ");
    for (int i = 0; i < 3; i++)
        printf("page%d=%-4d ", i, g_disk[i].value);
    printf("\n");
    printf("    内存: ");
    for (int i = 0; i < 3; i++)
        printf("page%d=%-4d ", i, g_mem[i].value);
    printf("\n");
    printf("    事务表: ");
    for (int i = 0; i < g_ntxns; i++) {
        const char *s = "?";
        if (g_txns[i].status == TX_ACTIVE)    s = "\033[1;33mACTIVE\033[0m";
        if (g_txns[i].status == TX_COMMITTED) s = "\033[1;32mCOMMIT\033[0m";
        if (g_txns[i].status == TX_ABORTED)   s = "\033[1;31mABORT\033[0m";
        printf("T%d=%s(lastLSN=%d) ",
               g_txns[i].tid, s, g_txns[i].last_lsn);
    }
    printf("\n");
    printf("    脏页表: ");
    if (g_ndirty == 0) printf("(空)");
    for (int i = 0; i < g_ndirty; i++)
        printf("page%d(recLSN=%d,pageLSN=%d) ",
               g_dirty[i].page_id, g_dirty[i].recLSN, g_dirty[i].pageLSN);
    printf("\n");
}

/* ================================================================
 * ★ 恢复阶段一: Analysis
 *
 *   从头扫日志, 重建:
 *     - 事务表: 每个事务的状态、最后 LSN
 *     - 脏页表: 每个页的 recLSN
 *   同时确定 redo 起点 = 脏页表里最小的 recLSN
 * ================================================================ */
static int analysis(void) {
    printf("\n\033[1;35m════════ 阶段 1: Analysis ════════\033[0m\n");

    g_ntxns = 0;
    g_ndirty = 0;

    for (int i = 0; i < g_nlog; i++) {
        LogRecord *r = &g_log[i];

        if (r->type == LOG_BEGIN) {
            TxnEntry *t = txn_add(r->tid);
            t->last_lsn = r->lsn;
            printf("  LSN=%d BEGIN T%d → 加入事务表\n", r->lsn, r->tid);
        }
        else if (r->type == LOG_UPDATE) {
            TxnEntry *t = txn_get(r->tid);
            t->last_lsn      = r->lsn;
            t->undo_next_lsn = r->lsn;

            if (!dirty_find(r->page_id)) {
                dirty_mark(r->page_id, r->lsn);
                printf("  LSN=%d UPDATE T%d page%d → 新脏页, recLSN=%d\n",
                       r->lsn, r->tid, r->page_id, r->lsn);
            }
        }
        else if (r->type == LOG_COMMIT) {
            TxnEntry *t = txn_get(r->tid);
            if (t) {
                t->last_lsn = r->lsn;
                t->status   = TX_COMMITTED;
                printf("  LSN=%d COMMIT T%d → 状态改为已提交\n",
                       r->lsn, r->tid);
            }
        }
        else if (r->type == LOG_ABORT) {
            TxnEntry *t = txn_get(r->tid);
            if (t) {
                t->last_lsn = r->lsn;
                t->status   = TX_ABORTED;
                printf("  LSN=%d ABORT T%d\n", r->lsn, r->tid);
            }
        }
        else if (r->type == LOG_CLR) {
            TxnEntry *t = txn_get(r->tid);
            if (t) {
                t->last_lsn      = r->lsn;
                t->undo_next_lsn = r->undo_next_lsn;
            }
            printf("  LSN=%d CLR T%d (undoNextLSN=%d)\n",
                   r->lsn, r->tid, r->undo_next_lsn);
        }
        else if (r->type == LOG_CKPT) {
            printf("  LSN=%d CKPT\n", r->lsn);
        }
    }

    /* redo 起点 = 所有脏页 recLSN 的最小值 */
    int redo_start = g_nlog + 1;
    for (int i = 0; i < g_ndirty; i++)
        if (g_dirty[i].recLSN < redo_start)
            redo_start = g_dirty[i].recLSN;

    printf("\n  \033[1;33m→ 事务表已重建\033[0m\n");
    printf("  \033[1;33m→ 脏页表已重建\033[0m\n");
    printf("  \033[1;33m→ Redo 起点 = min(recLSN) = %d\033[0m\n",
           redo_start == g_nlog + 1 ? 1 : redo_start);

    return redo_start == g_nlog + 1 ? 1 : redo_start;
}

/* ================================================================
 * ★ 恢复阶段二: Redo
 *
 *   从 redo_start 扫描到日志末尾, 重做所有 UPDATE 和 CLR。
 *   幂等性判断: pageLSN >= LSN 时跳过（已经反映在页面上了）
 * ================================================================ */
static void redo(int redo_start) {
    printf("\n\033[1;35m════════ 阶段 2: Redo (起点 LSN=%d) ════════\033[0m\n",
           redo_start);

    for (int i = redo_start - 1; i < g_nlog; i++) {
        LogRecord *r = &g_log[i];

        if (r->type != LOG_UPDATE && r->type != LOG_CLR) continue;

        int page_id = r->page_id;
        Page *p = &g_mem[page_id];

        if (p->pageLSN >= r->lsn) {
            printf("  LSN=%d %s page%d 已反映在页上 (pageLSN=%d ≥ %d), 跳过\n",
                   r->lsn, log_type_name(r->type), page_id,
                   p->pageLSN, r->lsn);
            continue;
        }

        if (r->type == LOG_UPDATE) {
            printf("  LSN=%d UPDATE page%d: %d → %d \033[1;32m[重做]\033[0m\n",
                   r->lsn, page_id, p->value, r->after);
            p->value   = r->after;
            p->pageLSN = r->lsn;
        } else {
            /* CLR 的 after 就是撤销后的值 */
            printf("  LSN=%d CLR    page%d: %d → %d \033[1;32m[重做]\033[0m\n",
                   r->lsn, page_id, p->value, r->after);
            p->value   = r->after;
            p->pageLSN = r->lsn;
        }
    }

    printf("\n  \033[1;33m→ 所有更新已重新应用\033[0m\n");
}

/* ================================================================
 * ★ 恢复阶段三: Undo
 *
 *   对所有 ACTIVE 事务（未提交也没 abort 的）, 从
 *   各自的 lastLSN 出发, 沿 prevLSN 链回滚。
 *   每一步写一条 CLR, 保证"撤销本身也是可恢复的"。
 * ================================================================ */
static void undo(void) {
    printf("\n\033[1;35m════════ 阶段 3: Undo ════════\033[0m\n");

    /* 收集所有活动事务 */
    int active[MAX_TXNS], n_active = 0;
    for (int i = 0; i < g_ntxns; i++)
        if (g_txns[i].status == TX_ACTIVE) {
            active[n_active++] = g_txns[i].tid;
            printf("  发现活动事务 T%d, lastLSN=%d\n",
                   g_txns[i].tid, g_txns[i].last_lsn);
        }

    /* 反复扫描, 每次挑一个要撤销最多的 */
    while (1) {
        int pick = -1, max_lsn = 0;
        for (int i = 0; i < n_active; i++) {
            TxnEntry *t = txn_get(active[i]);
            if (t->undo_next_lsn > max_lsn) {
                max_lsn = t->undo_next_lsn;
                pick = i;
            }
        }
        if (pick < 0) break;

        int tid = active[pick];
        TxnEntry *t = txn_get(tid);

        LogRecord *r = &g_log[t->undo_next_lsn - 1];

        if (r->type == LOG_BEGIN) {
            printf("  T%d 回滚到 BEGIN, 完成\n", tid);
            t->undo_next_lsn = 0;
            continue;
        }

        if (r->type == LOG_UPDATE) {
            int page_id = r->page_id;
            Page *p = &g_mem[page_id];
            int current = p->value;
            int restore = r->before;

            printf("  撤销 LSN=%d: T%d page%d %d → %d\n",
                   r->lsn, tid, page_id, current, restore);

            /* 写 CLR */
            int clr_lsn = log_append(LOG_CLR, tid, page_id,
                                     current, restore,
                                     t->last_lsn, r->prev_lsn);

            p->value   = restore;
            p->pageLSN = clr_lsn;

            t->last_lsn      = clr_lsn;
            t->undo_next_lsn = r->prev_lsn;

            printf("        写入 CLR (LSN=%d, undoNextLSN=%d)\n",
                   clr_lsn, r->prev_lsn);
        }
        else {
            /* CLR: 直接跳到它的 undo_next_lsn */
            t->undo_next_lsn = r->undo_next_lsn;
        }
    }

    printf("\n  \033[1;33m→ 所有活动事务已回滚\033[0m\n");
}

/* ================================================================
 * 初始化
 * ================================================================ */
static void init_db(void) {
    memset(g_log, 0, sizeof(g_log));
    memset(g_mem, 0, sizeof(g_mem));
    memset(g_txns, 0, sizeof(g_txns));
    memset(g_dirty, 0, sizeof(g_dirty));

    for (int i = 0; i < MAX_PAGES; i++) {
        g_disk[i].id = i;
        g_disk[i].value = (i + 1) * 100;
        g_disk[i].pageLSN = 0;
        g_mem[i] = g_disk[i];
    }

    g_nlog = 0;
    g_ntxns = 0;
    g_ndirty = 0;
    g_next_tid = 1;
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   ARIES 数据库恢复算法                               ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    init_db();

    printf("\n初始状态: page0=100  page1=200  page2=300\n");

    /* ============================================================
     * 正常运行阶段
     * ============================================================ */
    printf("\n\033[1;35m════════ 正常运行 ════════\033[0m\n");

    int t1 = txn_begin();
    printf("  T%d BEGIN\n", t1);
    txn_update(t1, 0, 150);       /* page0: 100 → 150 */
    printf("  T%d: page0 = 150\n", t1);
    txn_update(t1, 1, 250);       /* page1: 200 → 250 */
    printf("  T%d: page1 = 250\n", t1);
    txn_commit(t1);

    /* T1 提交后, 假设 page0, page1 都刷盘了 */
    flush_page(0);
    flush_page(1);

    checkpoint();
    dump_state("检查点后");

    /* ---- T2 开始, 但没提交 ---- */
    int t2 = txn_begin();
    printf("  T%d BEGIN\n", t2);
    txn_update(t2, 2, 350);       /* page2: 300 → 350 */
    printf("  T%d: page2 = 350\n", t2);
    txn_update(t2, 0, 180);       /* page0: 150 → 180 */
    printf("  T%d: page0 = 180\n", t2);
    /* 没提交 */

    /* ---- T3 开始并 abort ---- */
    int t3 = txn_begin();
    printf("  T%d BEGIN\n", t3);
    txn_update(t3, 1, 280);       /* page1: 250 → 280 */
    printf("  T%d: page1 = 280\n", t3);
    txn_abort(t3);
    /* abort 时实际应该立即回滚, 这里简化: 交给恢复阶段一起做 */

    dump_state("崩溃前内存");
    printf("\n    磁盘上的 page2 还是 300 (没刷过盘)\n");

    /* ============================================================
     * 崩溃：内存全丢，只保留磁盘和日志
     * ============================================================ */
    printf("\n\033[1;31m════════ ★ ★ ★ 崩溃 ★ ★ ★ ════════\033[0m\n");
    printf("  内存全丢失, 磁盘保持: page0=%d page1=%d page2=%d\n",
           g_disk[0].value, g_disk[1].value, g_disk[2].value);

    /* 内存重置为磁盘内容 */
    for (int i = 0; i < MAX_PAGES; i++) {
        g_mem[i] = g_disk[i];
    }

    dump_log();

    /* ============================================================
     * 恢复
     * ============================================================ */
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   开始恢复                                           ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    int redo_start = analysis();
    redo(redo_start);
    undo();

    /* ============================================================
     * 最终状态
     * ============================================================ */
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   恢复完成后的状态                                   ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║   内存: page0=%d  page1=%d  page2=%d                ║\n",
           g_mem[0].value, g_mem[1].value, g_mem[2].value);
    printf("║                                                      ║\n");
    printf("║   期望:                                              ║\n");
    printf("║     T1 提交 → page0=150, page1=250 保留              ║\n");
    printf("║     T2 未提交 → page2=300（撤销）, page0=150（撤销）  ║\n");
    printf("║     T3 已 abort → page1=250（撤销）                  ║\n");
    printf("║                                                      ║\n");
    printf("║   验证:                                              ║\n");
    printf("║     page0=150 %s                                     ║\n",
           g_mem[0].value == 150 ? "\033[1;32m✓\033[0m" : "\033[1;31m✗\033[0m");
    printf("║     page1=250 %s                                     ║\n",
           g_mem[1].value == 250 ? "\033[1;32m✓\033[0m" : "\033[1;31m✗\033[0m");
    printf("║     page2=300 %s                                     ║\n",
           g_mem[2].value == 300 ? "\033[1;32m✓\033[0m" : "\033[1;31m✗\033[0m");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    printf("\n\033[1;36mARIES 的三条黄金规则:\033[0m\n");
    printf("  1. WAL: 日志先写, 数据后写\n");
    printf("     没写完日志就刷数据, 崩溃后无法撤销\n\n");
    printf("  2. Redo 必须幂等\n");
    printf("     用 pageLSN 对比, 已经反映在页上的更新直接跳过\n");
    printf("     崩溃恢复本身也可能再崩, 重放不会出错\n\n");
    printf("  3. Undo 也写日志 (CLR)\n");
    printf("     撤销过程本身也是可恢复的; CLR 记录 undoNextLSN,\n");
    printf("     指向下一条要撤销的记录, 保证回滚可以继续\n");

    return 0;
}