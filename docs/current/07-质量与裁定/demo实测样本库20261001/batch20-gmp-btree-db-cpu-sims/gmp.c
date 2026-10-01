/* gmp.c —— Go 调度器 GMP 模型模拟
 *
 * 编译: gcc -Wall -O2 -std=c11 -o gmp gmp.c
 * 运行: ./gmp
 *
 * G = goroutine       用户态轻量协程
 * M = machine         操作系统线程
 * P = processor       逻辑处理器, 拥有本地队列
 *
 * 关键机制:
 *   1. M 必须绑定一个 P 才能运行 G
 *   2. 每个 P 有自己的本地运行队列
 *   3. 本地空了: 先取全局队列, 再从其他 P 偷一半
 *   4. G 阻塞时 M 释放 P, 让别的 M 可以接手
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define N_P       3
#define N_M       5
#define MAX_G     40
#define LOCAL_Q   32
#define GLOBAL_Q  64

typedef enum { G_READY, G_RUNNING, G_WAITING, G_DONE } GState;

typedef struct {
    int     id;
    GState  state;
    int     work_left;       /* 还需多少 tick 执行完 */
    int     wake_tick;       /* WAITING 状态的唤醒时刻 */
    int     cpu_burst;       /* 一段连续执行多少 tick 后会阻塞 */
    int     elapsed;         /* 本段已执行 tick */
    char    name[16];
} G;

typedef struct {
    G  *items[LOCAL_Q];
    int head, tail;
    int m_id;                /* 当前绑定哪个 M, -1 = 空闲 */
    int steals;
} P;

typedef struct {
    int  id;
    int  p_id;
    G   *cur_g;
    int  switches;
} M;

static G    g_gs[MAX_G];
static int  g_ngs = 0;
static P    g_ps[N_P];
static M    g_ms[N_M];
static G   *g_global[GLOBAL_Q];
static int  g_gh = 0, g_gt = 0;
static int  g_tick = 0;
static long g_stat_steal = 0;
static long g_stat_global = 0;
static long g_stat_syscall = 0;

/* ================================================================
 * 环形队列
 * ================================================================ */
static int  p_size(P *p) { return (p->tail - p->head + LOCAL_Q) % LOCAL_Q; }

static void p_push(P *p, G *g) {
    p->items[p->tail] = g;
    p->tail = (p->tail + 1) % LOCAL_Q;
}

/* LIFO: 从尾取, 缓存友好 */
static G *p_pop(P *p) {
    if (p->head == p->tail) return NULL;
    p->tail = (p->tail - 1 + LOCAL_Q) % LOCAL_Q;
    return p->items[p->tail];
}

/* FIFO: 从头偷 */
static G *p_steal(P *p) {
    if (p->head == p->tail) return NULL;
    G *g = p->items[p->head];
    p->head = (p->head + 1) % LOCAL_Q;
    return g;
}

static void global_push(G *g) {
    g_global[g_gt] = g;
    g_gt = (g_gt + 1) % GLOBAL_Q;
}

static G *global_pop(void) {
    if (g_gh == g_gt) return NULL;
    G *g = g_global[g_gh];
    g_gh = (g_gh + 1) % GLOBAL_Q;
    return g;
}

/* ================================================================
 * 创建一个 G
 * ================================================================ */
static G *new_g(const char *name, int work, int burst) {
    G *g = &g_gs[g_ngs];
    g->id        = g_ngs++;
    g->state     = G_READY;
    g->work_left = work;
    g->cpu_burst = burst;
    g->elapsed   = 0;
    g->wake_tick = 0;
    snprintf(g->name, sizeof(g->name), "%s", name);
    return g;
}

/* ================================================================
 * 找下一个要跑的 G
 *   优先级: 本地 → 全局 → 从其他 P 偷
 * ================================================================ */
static G *find_work(P *p) {
    /* 1. 本地队列 */
    G *g = p_pop(p);
    if (g) return g;

    /* 2. 全局队列: 一次拿一批, 减少锁竞争 */
    int moved = 0;
    for (int i = 0; i < 4; i++) {
        g = global_pop();
        if (!g) break;
        p_push(p, g);
        moved++;
    }
    if (moved > 0) {
        g_stat_global++;
        g = p_pop(p);
        if (g) return g;
    }

    /* 3. 从其他 P 偷一半 */
    for (int i = 1; i < N_P; i++) {
        int victim = ((int)(p - g_ps) + i) % N_P;
        P *vp = &g_ps[victim];
        int vs = p_size(vp);
        if (vs <= 1) continue;

        int n = vs / 2;
        for (int k = 0; k < n; k++) {
            G *s = p_steal(vp);
            if (!s) break;
            p_push(p, s);
        }
        g_stat_steal++;
        vp->steals++;
        g = p_pop(p);
        if (g) return g;
    }
    return NULL;
}

/* ================================================================
 * 打印辅助
 * ================================================================ */
static const char *state_color(GState s) {
    switch (s) {
    case G_READY:   return "\033[1;33m就绪\033[0m";
    case G_RUNNING: return "\033[1;32m运行\033[0m";
    case G_WAITING: return "\033[1;36m等待\033[0m";
    case G_DONE:    return "\033[1;30m完成\033[0m";
    }
    return "?";
}

static void dump_state(void) {
    printf("\n  \033[1;36m[t=%02d] 系统状态:\033[0m\n", g_tick);

    for (int i = 0; i < N_M; i++) {
        M *m = &g_ms[i];
        printf("    M%d: ", m->id);
        if (m->p_id < 0) {
            printf("\033[90m空闲 (无 P)\033[0m\n");
        } else {
            G *g = m->cur_g;
            printf("绑定 P%d", m->p_id);
            if (g) printf(" → 运行 %s (%s, 剩 %d)",
                          g->name, state_color(g->state), g->work_left);
            printf("\n");
        }
    }

    for (int i = 0; i < N_P; i++) {
        P *p = &g_ps[i];
        printf("    P%d: 队列 %d 项 [", i, p_size(p));
        int n = p_size(p);
        for (int k = 0; k < n && k < 6; k++) {
            if (k) printf(",");
            printf("%s", p->items[(p->head + k) % LOCAL_Q]->name);
        }
        if (n > 6) printf(",...");
        printf("]");
        if (p->m_id >= 0) printf("  ← M%d", p->m_id);
        else              printf("  \033[90m(空闲)\033[0m");
        printf("\n");
    }

    int gq = (g_gt - g_gh + GLOBAL_Q) % GLOBAL_Q;
    printf("    全局队列: %d 项\n", gq);
}

/* ================================================================
 * 主循环
 * ================================================================ */
static void step(void) {
    g_tick++;

    /* ---- 1. WAITING 的 G 唤醒 ---- */
    for (int i = 0; i < g_ngs; i++) {
        G *g = &g_gs[i];
        if (g->state == G_WAITING && g_tick >= g->wake_tick) {
            g->state = G_READY;
            g->elapsed = 0;
            /* 放到全局队列（真实 Go 里从 netpoller 唤醒走全局队列） */
            global_push(g);
        }
    }

    /* ---- 2. 处理每个 M ---- */
    for (int i = 0; i < N_M; i++) {
        M *m = &g_ms[i];

        /* 检查当前 G 是否要释放 P */
        if (m->cur_g) {
            G *g = m->cur_g;

            /* 假随机阻塞: 每跑满 cpu_burst 就进入 WAITING */
            if (g->elapsed >= g->cpu_burst && g->work_left > 0) {
                g->state     = G_WAITING;
                g->wake_tick = g_tick + 2 + rand() % 3;
                g->elapsed   = 0;
                printf("  \033[1;36m[M%d]\033[0m %s 阻塞, 让出 M%d\n",
                       m->id, g->name, m->id);
                m->cur_g = NULL;
                /* 关键: 释放 P, 让别的 M 能接手 */
                P *p = &g_ps[m->p_id];
                p->m_id = -1;
                m->p_id = -1;
                g_stat_syscall++;
                continue;
            }

            /* 执行一个 tick */
            g->work_left--;
            g->elapsed++;

            if (g->work_left == 0) {
                g->state = G_DONE;
                printf("  \033[1;32m[M%d]\033[0m %s 完成\n",
                       m->id, g->name);
                m->cur_g = NULL;
                /* 继续跑下一个 G, 不释放 P */
            } else {
                continue;   /* 保持在 M 上 */
            }
        }

        /* M 没有 P: 尝试获取一个空闲 P */
        if (m->p_id < 0) {
            for (int k = 0; k < N_P; k++) {
                if (g_ps[k].m_id < 0) {
                    g_ps[k].m_id = m->id;
                    m->p_id = k;
                    printf("  \033[90m[M%d]\033[0m 绑定 P%d\n", m->id, k);
                    break;
                }
            }
            if (m->p_id < 0) continue;   /* 没有空闲 P */
        }

        /* M 有 P: 找下一个 G */
        P *p = &g_ps[m->p_id];
        G *g = find_work(p);
        if (!g) continue;

        g->state   = G_RUNNING;
        g->elapsed = 0;
        m->cur_g   = g;
        m->switches++;
    }
}

static int count_done(void) {
    int n = 0;
    for (int i = 0; i < g_ngs; i++)
        if (g_gs[i].state == G_DONE) n++;
    return n;
}

/* ================================================================
 * 演示
 * ================================================================ */
int main(void) {
    srand(7);

    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   Go 调度器 GMP 模型模拟                             ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");

    printf("配置: %d 个 M (OS 线程), %d 个 P (逻辑处理器)\n", N_M, N_P);
    printf("      每个 P 有独立本地队列, 装满后再进全局队列\n\n");

    /* 初始化 */
    memset(g_ps, 0, sizeof(g_ps));
    memset(g_ms, 0, sizeof(g_ms));
    for (int i = 0; i < N_P; i++) g_ps[i].m_id = -1;
    for (int i = 0; i < N_M; i++) {
        g_ms[i].id   = i;
        g_ms[i].p_id = -1;
    }

    /* 创建一批 G */
    printf("\033[1;33m━━━ 创建 12 个 G ━━━\033[0m\n");
    for (int i = 0; i < 12; i++) {
        char name[16];
        snprintf(name, sizeof(name), "G%d", i);
        /* work 5~12 tick, 每跑 3~5 tick 会阻塞一次 */
        G *g = new_g(name, 5 + rand() % 8, 3 + rand() % 3);

        /* 轮流放进 P 的本地队列, 模拟 Go 的 runqput */
        P *p = &g_ps[i % N_P];
        if (p_size(p) < LOCAL_Q)
            p_push(p, g);
        else
            global_push(g);
    }

    printf("\n  初始分配:\n");
    for (int i = 0; i < N_P; i++) {
        printf("    P%d: ", i);
        int n = p_size(&g_ps[i]);
        for (int k = 0; k < n; k++) {
            if (k) printf(", ");
            printf("%s(%d tick)",
                   g_ps[i].items[(g_ps[i].head + k) % LOCAL_Q]->name,
                   g_ps[i].items[(g_ps[i].head + k) % LOCAL_Q]->work_left);
        }
        printf("\n");
    }

    dump_state();

    printf("\n\033[1;33m━━━ 开始调度 ━━━\033[0m\n\n");

    /* 主循环 */
    int last_done = -1;
    while (g_tick < 200) {
        step();

        int done = count_done();
        if (done != last_done) {
            last_done = done;
            if (done == g_ngs) {
                printf("\n  \033[1;32m全部 %d 个 G 执行完毕\033[0m\n", g_ngs);
                break;
            }
        }
    }

    printf("\n");
    dump_state();

    /* 统计 */
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   统计                                               ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║   总 tick 数:      %3d                              ║\n", g_tick);
    printf("║   完成的 G:        %3d / %d                         ║\n",
           count_done(), g_ngs);
    printf("║   工作窃取次数:    %3ld                              ║\n", g_stat_steal);
    printf("║   全局队列取次数:  %3ld                              ║\n", g_stat_global);
    printf("║   G 阻塞次数:      %3ld                              ║\n", g_stat_syscall);
    printf("║                                                      ║\n");
    printf("║   每个 M 的上下文切换:\n");
    for (int i = 0; i < N_M; i++)
        printf("║     M%d: %3d 次                                      ║\n",
               i, g_ms[i].switches);
    printf("║                                                      ║\n");
    printf("║   每个 P 被偷次数:\n");
    for (int i = 0; i < N_P; i++)
        printf("║     P%d: %3d 次                                      ║\n",
               i, g_ps[i].steals);
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}
