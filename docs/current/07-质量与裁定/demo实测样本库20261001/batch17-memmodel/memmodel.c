/* memmodel.c —— 内存模型与 happens-before 分析
 *
 * 编译: gcc -Wall -O2 -std=c11 -o memmodel memmodel.c
 * 运行: ./memmodel
 *
 * 核心概念:
 *   · happens-before (HB): 若 a → b，则 a 的写对 b 可见
 *   · HB 的 5 条规则: 程序顺序 / spawn / join / 锁 / 传递性
 *   · 数据竞争: 两个线程访问同一变量，至少一个写，且无 HB
 *   · 内存模型: SC / TSO / 宽松，决定允许哪些指令重排
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define MAX_OPS     32
#define MAX_THREADS 4

/* ================================================================
 * 操作与程序
 * ================================================================ */
typedef enum {
    OP_WRITE, OP_READ,
    OP_ACQUIRE, OP_RELEASE,
    OP_SPAWN, OP_JOIN
} OpType;

typedef struct {
    int    id, tid, seq;
    OpType type;
    int    var, val, mutex, target;
    char   text[64];
} Op;

typedef struct {
    Op    ops[MAX_OPS];
    int   n;
    int   next_seq[MAX_THREADS];
    bool  hb[MAX_OPS][MAX_OPS];
} Program;

static int g_var_count = 0;

static int var_id(const char *name) { (void)name; return g_var_count++; }

static void prog_init(Program *p) {
    memset(p, 0, sizeof(*p));
    g_var_count = 0;
}

static int add_op(Program *p, int tid, OpType t, const char *txt) {
    int i = p->n++;
    Op *o = &p->ops[i];
    o->id = i; o->tid = tid; o->seq = p->next_seq[tid]++;
    o->type = t; o->var = -1; o->val = 0; o->mutex = -1; o->target = -1;
    strncpy(o->text, txt, sizeof(o->text) - 1);
    return i;
}

static int op_write(Program *p, int tid, const char *var, int val) {
    char buf[64]; snprintf(buf, sizeof(buf), "%s = %d", var, val);
    int i = add_op(p, tid, OP_WRITE, buf);
    p->ops[i].var = var_id(var); p->ops[i].val = val;
    return i;
}

static int op_read(Program *p, int tid, const char *var) {
    char buf[64]; snprintf(buf, sizeof(buf), "r = %s", var);
    int i = add_op(p, tid, OP_READ, buf);
    p->ops[i].var = var_id(var);
    return i;
}

static int op_lock(Program *p, int tid, int m) {
    char buf[64]; snprintf(buf, sizeof(buf), "lock(m%d)", m);
    int i = add_op(p, tid, OP_ACQUIRE, buf);
    p->ops[i].mutex = m; return i;
}

static int op_unlock(Program *p, int tid, int m) {
    char buf[64]; snprintf(buf, sizeof(buf), "unlock(m%d)", m);
    int i = add_op(p, tid, OP_RELEASE, buf);
    p->ops[i].mutex = m; return i;
}

static int op_spawn(Program *p, int tid, int tgt) {
    char buf[64]; snprintf(buf, sizeof(buf), "spawn(T%d)", tgt);
    int i = add_op(p, tid, OP_SPAWN, buf);
    p->ops[i].target = tgt; return i;
}

static int op_join(Program *p, int tid, int tgt) {
    char buf[64]; snprintf(buf, sizeof(buf), "join(T%d)", tgt);
    int i = add_op(p, tid, OP_JOIN, buf);
    p->ops[i].target = tgt; return i;
}

/* ================================================================
 * HB 计算
 * ================================================================ */
static void build_hb(Program *p) {
    int n = p->n;
    memset(p->hb, 0, sizeof(p->hb));
    for (int i = 0; i < n; i++) p->hb[i][i] = true;

    /* 1. 程序顺序: 同线程 seq 小的在前 */
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++)
            if (p->ops[i].tid == p->ops[j].tid &&
                p->ops[i].seq <  p->ops[j].seq)
                p->hb[i][j] = true;

    /* 2. spawn: spawn(t) → t 的首条指令 */
    for (int i = 0; i < n; i++) {
        if (p->ops[i].type != OP_SPAWN) continue;
        int t = p->ops[i].target;
        for (int j = 0; j < n; j++)
            if (p->ops[j].tid == t && p->ops[j].seq == 0) {
                p->hb[i][j] = true; break;
            }
    }

    /* 3. join: t 的末条指令 → join(t) */
    for (int i = 0; i < n; i++) {
        if (p->ops[i].type != OP_JOIN) continue;
        int t = p->ops[i].target, last = -1;
        for (int j = 0; j < n; j++) if (p->ops[j].tid == t) last = j;
        if (last >= 0) p->hb[last][i] = true;
    }

    /* 4. 锁: unlock(m) → 之后的下一次 lock(m) */
    for (int i = 0; i < n; i++) {
        if (p->ops[i].type != OP_RELEASE) continue;
        int m = p->ops[i].mutex;
        for (int j = i + 1; j < n; j++)
            if (p->ops[j].type == OP_ACQUIRE && p->ops[j].mutex == m) {
                p->hb[i][j] = true; break;
            }
    }

    /* 5. 传递闭包 (Warshall) */
    for (int k = 0; k < n; k++)
        for (int i = 0; i < n; i++)
            if (p->hb[i][k])
                for (int j = 0; j < n; j++)
                    if (p->hb[k][j]) p->hb[i][j] = true;
}

/* ================================================================
 * 数据竞争检测
 * ================================================================ */
static int check_races(Program *p, bool verbose) {
    int races = 0;
    for (int i = 0; i < p->n; i++)
        for (int j = i + 1; j < p->n; j++) {
            Op *a = &p->ops[i], *b = &p->ops[j];
            if (a->tid == b->tid) continue;
            if (a->type != OP_WRITE && a->type != OP_READ) continue;
            if (b->type != OP_WRITE && b->type != OP_READ) continue;
            if (a->type != OP_WRITE && b->type != OP_WRITE) continue;
            if (a->var < 0 || a->var != b->var) continue;
            if (p->hb[i][j] || p->hb[j][i]) continue;

            races++;
            if (verbose)
                printf("    \033[1;31m✗ 竞争\033[0m  "
                       "T%d.#%d(%s)  ↔  T%d.#%d(%s)\n",
                       a->tid, a->id, a->text,
                       b->tid, b->id, b->text);
        }
    return races;
}

/* ================================================================
 * 打印
 * ================================================================ */
static void print_program(Program *p) {
    printf("  程序:\n");
    for (int i = 0; i < p->n; i++)
        printf("    \033[90m#%-2d\033[0m  T%d.%-2d  %s\n",
               i, p->ops[i].tid, p->ops[i].seq, p->ops[i].text);
}

/* 是否直接边（不存在中间节点） */
static bool is_direct_edge(Program *p, int i, int j) {
    if (!p->hb[i][j] || i == j) return false;
    for (int k = 0; k < p->n; k++) {
        if (k == i || k == j) continue;
        if (p->hb[i][k] && p->hb[k][j]) return false;
    }
    return true;
}

static void print_hb_edges(Program *p) {
    printf("  happens-before 直接边:\n");
    int shown = 0;
    for (int i = 0; i < p->n; i++)
        for (int j = 0; j < p->n; j++) {
            if (p->ops[i].tid == p->ops[j].tid) continue;
            if (!is_direct_edge(p, i, j)) continue;
            printf("    T%d.#%-2d %-18s  →  T%d.#%-2d %s\n",
                   p->ops[i].tid, p->ops[i].id, p->ops[i].text,
                   p->ops[j].tid, p->ops[j].id, p->ops[j].text);
            shown++;
        }
    if (!shown) printf("    \033[90m(无跨线程直接边)\033[0m\n");
}

static void analyze(const char *title, Program *p, const char *comment) {
    printf("\n\033[1;33m═══ %s ═══\033[0m\n", title);

    build_hb(p);
    print_program(p);
    print_hb_edges(p);

    printf("  数据竞争检测:\n");
    int n = check_races(p, true);
    if (n == 0) printf("    \033[1;32m✓ 无数据竞争\033[0m\n");
    else        printf("    \033[1;31m发现 %d 处竞争\033[0m\n", n);

    if (comment) printf("\n  \033[1;36m说明:\033[0m %s\n", comment);
}

/* ================================================================
 * 内存模型演示
 * ================================================================ */
static void memory_models(void) {
    printf("\n\033[1;33m═══ 内存模型对比 ═══\033[0m\n");
    printf("  程序:\n");
    printf("    T0:  x = 1;  r1 = y\n");
    printf("    T1:  y = 1;  r2 = x\n\n");

    printf("  可能的结果 (r1, r2):\n");
    printf("    \033[90m┌─────────┬──────┬──────┬────────┐\033[0m\n");
    printf("    \033[90m│\033[0m r1 r2   \033[90m│\033[0m  SC  \033[90m│\033[0m TSO  "
           "\033[90m│\033[0m 宽松   \033[90m│\033[0m\n");
    printf("    \033[90m├─────────┼──────┼──────┼────────┤\033[0m\n");
    printf("    \033[90m│\033[0m 0  0    \033[90m│\033[0m  ✗   "
           "\033[90m│\033[0m \033[1;32m✓\033[0m    \033[90m│\033[0m \033[1;32m✓\033[0m      "
           "\033[90m│\033[0m\n");
    printf("    \033[90m│\033[0m 0  1    \033[90m│\033[0m \033[1;32m✓\033[0m    "
           "\033[90m│\033[0m \033[1;32m✓\033[0m    \033[90m│\033[0m \033[1;32m✓\033[0m      "
           "\033[90m│\033[0m\n");
    printf("    \033[90m│\033[0m 1  0    \033[90m│\033[0m \033[1;32m✓\033[0m    "
           "\033[90m│\033[0m \033[1;32m✓\033[0m    \033[90m│\033[0m \033[1;32m✓\033[0m      "
           "\033[90m│\033[0m\n");
    printf("    \033[90m│\033[0m 1  1    \033[90m│\033[0m \033[1;32m✓\033[0m    "
           "\033[90m│\033[0m \033[1;32m✓\033[0m    \033[90m│\033[0m \033[1;32m✓\033[0m      "
           "\033[90m│\033[0m\n");
    printf("    \033[90m└─────────┴──────┴──────┴────────┘\033[0m\n\n");

    printf("  \033[1;36mSC (顺序一致性)\033[0m\n");
    printf("    · 所有操作有全局全序，且保持各线程程序顺序\n");
    printf("    · r1=r2=0 不可能: 要么 x=1 先执行，要么 y=1 先执行\n\n");

    printf("  \033[1;36mTSO (x86 模型)\033[0m\n");
    printf("    · 允许 Store-Load 重排（写缓冲效应）\n");
    printf("    · T0 可重排成 \"r1=y; x=1\"，两个读都看到 0\n");
    printf("    · 其他三种重排均被禁止\n\n");

    printf("  \033[1;36m宽松 (ARM/POWER)\033[0m\n");
    printf("    · 任何重排都可能\n");
    printf("    · 需要内存栅栏 / 释放-获取语义才能保证顺序\n");
}

/* ================================================================
 * 场景演示
 * ================================================================ */
static void scenario_locked(void) {
    Program p; prog_init(&p);
    op_lock(&p, 0, 0);
    op_write(&p, 0, "x", 1);
    op_write(&p, 0, "flag", 1);
    op_unlock(&p, 0, 0);
    op_lock(&p, 1, 0);
    op_read(&p, 1, "flag");
    op_read(&p, 1, "x");
    op_unlock(&p, 1, 0);

    analyze("场景 1：锁保护的消息传递",
        &p,
        "unlock(m0) → lock(m0) 建立同步边；\n"
        "        x=1 和 flag=1 通过 HB 传递到 T1 的读，无竞争。");
}

static void scenario_unlocked(void) {
    Program p; prog_init(&p);
    op_write(&p, 0, "x", 1);
    op_write(&p, 0, "flag", 1);
    op_read(&p, 1, "flag");
    op_read(&p, 1, "x");

    analyze("场景 2：无同步的消息传递（错误）",
        &p,
        "没有任何同步操作 → 跨线程无 HB 边；\n"
        "        flag 和 x 的读写都构成数据竞争，T1 可能读到旧值。");
}

static void scenario_spawn(void) {
    Program p; prog_init(&p);
    op_write(&p, 0, "x", 42);
    op_spawn(&p, 0, 1);
    op_write(&p, 1, "y", 100);
    op_join(&p, 0, 1);
    op_read(&p, 0, "y");

    analyze("场景 3：spawn / join 建立的 HB",
        &p,
        "spawn 边: T0 spawn → T1 首条；\n"
        "        join 边: T1 末条 → T0 join；\n"
        "        两者共同构成同步链，无竞争。");
}

static void scenario_store_buffer(void) {
    Program p; prog_init(&p);
    op_write(&p, 0, "x", 1);
    op_read(&p, 0, "y");
    op_write(&p, 1, "y", 1);
    op_read(&p, 1, "x");

    analyze("场景 4：经典 Store-Buffer 测试",
        &p,
        "无同步，两次读都与对方的写构成竞争；\n"
        "        TSO 下两个读可能都返回 0（Store-Load 重排）。");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║     内存模型 与 happens-before 分析              ║\n");
    printf("╚══════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    printf("\n\033[1;36mHB 的 5 条规则:\033[0m\n");
    printf("  ① 程序顺序: 同线程内 a 在 b 之前 → a → b\n");
    printf("  ② spawn:    spawn(t) → t 的第一条指令\n");
    printf("  ③ join:     t 的最后一条指令 → join(t)\n");
    printf("  ④ 锁:       unlock(m) → 之后的下一次 lock(m)\n");
    printf("  ⑤ 传递性:   a → b 且 b → c → a → c\n");

    scenario_locked();
    scenario_unlocked();
    scenario_spawn();
    scenario_store_buffer();
    memory_models();

    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║   核心结论                                       ║\n");
    printf("╠══════════════════════════════════════════════════╣\n");
    printf("║ · HB 是"可见性"的数学描述：a→b 则 a 的写对 b 可见 ║\n");
    printf("║ · 数据竞争 = 两个冲突访问 + 无 HB 关系          ║\n");
    printf("║ · 正确同步 = 消除所有跨线程冲突的数据竞争        ║\n");
    printf("║ · 弱内存模型允许重排，但同步操作建立 HB          ║\n");
    printf("║ · C11 的 memory_order / Java 的 volatile 都是   ║\n");
    printf("║   在语言层面表达"我要哪条 HB 规则"               ║\n");
    printf("╚══════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}
