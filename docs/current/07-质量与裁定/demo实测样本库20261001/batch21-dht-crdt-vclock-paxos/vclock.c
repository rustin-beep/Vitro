/* vclock.c —— 向量时钟与因果序
 *
 * 编译: gcc -Wall -O2 -std=c11 -o vclock vclock.c
 * 运行: ./vclock
 *
 * 核心:
 *   向量时钟 VC[i] = 进程 i 已知的"各进程发生过的事件数"
 *
 *   比较规则 (Lamport 1978, Mattern 1989):
 *     e1 → e2   (e1 因果先于 e2)  当且仅当 VC(e1) < VC(e2)
 *     e1 ∥ e2   (并发)             当且仅当 VC 互不 ≤
 *
 *   性质:
 *     · 事件 -[发送]-> 事件, 消息携带发送者的向量时钟
 *     · 接收者合并: VC[k] = max(VC[k], msg[k]) 再 +1
 *     · 传递性: a→b, b→c 则 a→c (由向量时钟自然保证)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>

#define N_PROC   3
#define MAX_EVENTS 64

/* ================================================================
 * 向量时钟
 * ================================================================ */
typedef struct {
    int v[N_PROC];
} VClock;

static VClock vc_zero(void) {
    VClock c;
    for (int i = 0; i < N_PROC; i++) c.v[i] = 0;
    return c;
}

/* 本地事件: 自己分量 +1 */
static void vc_tick(VClock *c, int pid) {
    c->v[pid]++;
}

/* 接收消息: 逐分量取 max, 再 +1 */
static void vc_merge_then_tick(VClock *c, VClock *other, int pid) {
    for (int i = 0; i < N_PROC; i++)
        if (other->v[i] > c->v[i]) c->v[i] = other->v[i];
    c->v[pid]++;
}

/* 严格小于: a < b 等价 "a → b" (因果先于) */
static bool vc_lt(VClock a, VClock b) {
    bool any_less = false;
    for (int i = 0; i < N_PROC; i++) {
        if (a.v[i] > b.v[i]) return false;
        if (a.v[i] < b.v[i]) any_less = true;
    }
    return any_less;
}

/* 相等 */
static bool vc_eq(VClock a, VClock b) {
    for (int i = 0; i < N_PROC; i++)
        if (a.v[i] != b.v[i]) return false;
    return true;
}

/* 并发: 既不 < 也不 > */
static bool vc_concurrent(VClock a, VClock b) {
    return !vc_lt(a, b) && !vc_lt(b, a) && !vc_eq(a, b);
}

static void vc_print(VClock c) {
    printf("(");
    for (int i = 0; i < N_PROC; i++) {
        if (i) printf(",");
        printf("%d", c.v[i]);
    }
    printf(")");
}

/* ================================================================
 * 事件日志
 * ================================================================ */
typedef enum {
    EV_LOCAL,
    EV_SEND,
    EV_RECV
} EvType;

typedef struct {
    int     id;
    int     pid;
    int     seq;         /* 进程内序号 */
    EvType  type;
    VClock  vc;
    int     peer;        /* 消息对端 */
    int     send_ev_id;  /* 若是 recv, 对应哪个 send 事件 */
    char    label[32];
} Event;

static Event g_events[MAX_EVENTS];
static int   g_nevents = 0;

static int new_event(int pid, EvType type, VClock vc,
                     int peer, int send_id, const char *label) {
    Event *e = &g_events[g_nevents];
    e->id         = g_nevents++;
    e->pid        = pid;
    e->type       = type;
    e->vc         = vc;
    e->peer       = peer;
    e->send_ev_id = send_id;
    snprintf(e->label, sizeof(e->label), "%s", label);

    /* 进程内序号 */
    int seq = 0;
    for (int i = 0; i < g_nevents - 1; i++)
        if (g_events[i].pid == pid) seq++;
    e->seq = seq;

    return e->id;
}

/* ================================================================
 * 模拟进程
 * ================================================================ */
typedef struct {
    int     pid;
    VClock  vc;
    int     last_send[MAX_EVENTS];   /* 每对 (pid) 的最后发送事件 */
} Process;

static Process g_procs[N_PROC];

static void proc_local(int pid, const char *label) {
    vc_tick(&g_procs[pid].vc, pid);
    new_event(pid, EV_LOCAL, g_procs[pid].vc, -1, -1, label);
}

static int proc_send(int pid, int to, const char *label) {
    vc_tick(&g_procs[pid].vc, pid);
    int eid = new_event(pid, EV_SEND, g_procs[pid].vc, to, -1, label);
    g_procs[pid].last_send[to] = eid;
    return eid;
}

static void proc_recv(int pid, int from, int send_ev_id, const char *label) {
    VClock msg = g_events[send_ev_id].vc;
    vc_merge_then_tick(&g_procs[pid].vc, &msg, pid);
    new_event(pid, EV_RECV, g_procs[pid].vc, from, send_ev_id, label);
}

/* ================================================================
 * 打印
 * ================================================================ */
static const char *ev_type_str(EvType t) {
    switch (t) {
    case EV_LOCAL: return "L";
    case EV_SEND:  return "S";
    case EV_RECV:  return "R";
    }
    return "?";
}

static const char *ev_type_color(EvType t) {
    switch (t) {
    case EV_LOCAL: return "\033[1;37m";
    case EV_SEND:  return "\033[1;33m";
    case EV_RECV:  return "\033[1;32m";
    }
    return "";
}

static void print_event_list(void) {
    printf("\n  \033[1;36m[事件表]\033[0m\n");
    printf("    ID  P  类型  向量时钟        标签            对端\n");
    printf("    ──  ─  ────  ─────────────  ──────────────  ────\n");
    for (int i = 0; i < g_nevents; i++) {
        Event *e = &g_events[i];
        printf("    %-2d  P%d %s%-4s\033[0m  ",
               e->id, e->pid, ev_type_color(e->type), ev_type_str(e->type));
        vc_print(e->vc);
        printf("%-4s", "");
        printf("  %-14s", e->label);

        if (e->type == EV_SEND) printf("→ P%d", e->peer);
        else if (e->type == EV_RECV) printf("← P%d (send=%d)", e->peer, e->send_ev_id);
        else printf("");
        printf("\n");
    }
}

/* ================================================================
 * 时间线绘制
 * ================================================================ */
static void draw_timeline(void) {
    printf("\n  \033[1;36m[时间线]\033[0m  (\033[1;33mS\033[0m=send  "
           "\033[1;32mR\033[0m=recv  \033[1;37mL\033[0m=local  "
           "\033[90m---\033[0m=消息)\n\n");

    /* 每个进程一列, 高度 = 最大事件数 */
    int max_seq = 0;
    for (int i = 0; i < g_nevents; i++)
        if (g_events[i].seq > max_seq) max_seq = g_events[i].seq;

    /* 收集每行 (seq) 每个进程的事件 id */
    for (int s = 0; s <= max_seq; s++) {
        printf("    ");
        for (int p = 0; p < N_PROC; p++) {
            int eid = -1;
            for (int i = 0; i < g_nevents; i++) {
                if (g_events[i].pid == p && g_events[i].seq == s) {
                    eid = i;
                    break;
                }
            }
            if (eid >= 0) {
                Event *e = &g_events[eid];
                char sym = 'L';
                if (e->type == EV_SEND) sym = 'S';
                if (e->type == EV_RECV) sym = 'R';

                printf("%s%c\033[0m",
                       ev_type_color(e->type), sym);

                /* 显示向量时钟的缩写 */
                printf("\033[90m");
                for (int k = 0; k < N_PROC; k++) {
                    if (k > 0) printf("");
                    printf("%d", e->vc.v[k]);
                }
                printf("\033[0m");
            } else {
                printf("·");
            }
            printf("      ");
        }
        printf("\n");
    }

    /* 消息箭头 */
    printf("\n    \033[1;33m消息传递:\033[0m\n");
    for (int i = 0; i < g_nevents; i++) {
        Event *e = &g_events[i];
        if (e->type != EV_SEND) continue;
        /* 找对应的 recv */
        int recv_id = -1;
        for (int j = 0; j < g_nevents; j++) {
            if (g_events[j].type == EV_RECV && g_events[j].send_ev_id == e->id) {
                recv_id = j;
                break;
            }
        }
        if (recv_id < 0) {
            printf("      #%d P%d → P%d (未送达)\n", e->id, e->pid, e->peer);
        } else {
            Event *r = &g_events[recv_id];
            printf("      P%d.#%d → P%d.#%d  (send ID=%d, recv ID=%d)\n",
                   e->pid, e->seq, r->pid, r->seq, e->id, recv_id);
        }
    }
}

/* ================================================================
 * 因果序分析
 * ================================================================ */
static const char *rel_str(int a, int b) {
    VClock va = g_events[a].vc;
    VClock vb = g_events[b].vc;
    if (vc_lt(va, vb))       return "→";      /* a 因果先于 b */
    if (vc_lt(vb, va))       return "←";      /* b 因果先于 a */
    if (vc_concurrent(va, vb)) return "∥";    /* 并发 */
    return "=";
}

static void print_causal_matrix(void) {
    printf("\n  \033[1;36m[因果序矩阵]\033[0m\n");
    printf("    行=事件a, 列=事件b\n");
    printf("    →  : a 因果先于 b\n");
    printf("    ←  : b 因果先于 a\n");
    printf("    ∥  : 并发 (无法比较)\n");
    printf("    =  : 同一事件\n\n    ");

    for (int j = 0; j < g_nevents; j++)
        printf("%2d", j);
    printf("\n");

    for (int i = 0; i < g_nevents; i++) {
        printf("    %2d ", i);
        for (int j = 0; j < g_nevents; j++) {
            const char *r = rel_str(i, j);
            if (i == j)               printf(" \033[90m%s\033[0m", r);
            else if (!strcmp(r, "→")) printf(" \033[1;32m%s\033[0m", r);
            else if (!strcmp(r, "←")) printf(" \033[1;36m%s\033[0m", r);
            else                      printf(" \033[1;33m%s\033[0m", r);
        }
        printf("\n");
    }
}

/* ================================================================
 * 找出所有并发对
 * ================================================================ */
static void print_concurrent_pairs(void) {
    printf("\n  \033[1;36m[并发事件对]\033[0m  (无因果关系)\n");

    int count = 0;
    for (int i = 0; i < g_nevents; i++)
        for (int j = i + 1; j < g_nevents; j++) {
            if (vc_concurrent(g_events[i].vc, g_events[j].vc)) {
                printf("    #%-2d P%d.%-2d %-12s  ∥  #%-2d P%d.%-2d %s\n",
                       i, g_events[i].pid, g_events[i].seq, g_events[i].label,
                       j, g_events[j].pid, g_events[j].seq, g_events[j].label);
                count++;
            }
        }
    printf("    共 %d 对并发事件\n", count);
}

/* ================================================================
 * 场景
 * ================================================================ */
static void reset_all(void) {
    memset(g_events, 0, sizeof(g_events));
    memset(g_procs, 0, sizeof(g_procs));
    for (int i = 0; i < N_PROC; i++) {
        g_procs[i].pid = i;
        g_procs[i].vc  = vc_zero();
        for (int j = 0; j < MAX_EVENTS; j++)
            g_procs[i].last_send[j] = -1;
    }
    g_nevents = 0;
}

static void scenario_1(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 1: 单消息 + 因果链\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════\033[0m\n");
    printf("\n  剧本:\n");
    printf("    P0: a1, send(m) → P1\n");
    printf("    P1: b1, recv(m), b2\n");
    printf("    P2: c1\n\n");

    reset_all();

    proc_local(0, "a1");
    int s = proc_send(0, 1, "m");

    proc_local(1, "b1");
    proc_recv(1, 0, s, "recv_m");
    proc_local(1, "b2");

    proc_local(2, "c1");

    print_event_list();
    draw_timeline();
    print_causal_matrix();
    print_concurrent_pairs();

    printf("\n  \033[1;33m分析:\033[0m\n");
    printf("    a1 → recv_m  (通过 a1 → send → recv 传递)\n");
    printf("    b1 → recv_m  (b1 在 recv 之前, 同进程顺序)\n");
    printf("    c1 ∥ a1      (P2 完全独立于 P0)\n");
    printf("    c1 ∥ b2      (P2 也独立于 P1)\n");
}

static void scenario_2(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 2: 双向通信 —— 真正的因果关系\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════\033[0m\n");
    printf("\n  剧本:\n");
    printf("    P0: send(m1) → P1\n");
    printf("    P1: recv(m1), send(m2) → P0\n");
    printf("    P0: recv(m2)\n");
    printf("    同时 P2 独立工作\n\n");

    reset_all();

    int m1 = proc_send(0, 1, "m1");
    proc_recv(1, 0, m1, "recv_m1");

    proc_local(2, "c1");
    proc_local(2, "c2");

    int m2 = proc_send(1, 0, "m2");
    proc_recv(0, 1, m2, "recv_m2");

    print_event_list();
    draw_timeline();
    print_causal_matrix();
    print_concurrent_pairs();

    printf("\n  \033[1;33m分析:\033[0m\n");
    printf("    m1 → recv_m1 → m2 → recv_m2  (一条完整的因果链)\n");
    printf("    c1, c2 与这条链上所有事件都并发\n");
    printf("    \033[1;32m关键: 向量时钟自动捕获了整个传递链\033[0m\n");
}

static void scenario_3(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 3: 并发写 —— 为什么需要向量时钟\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════\033[0m\n");
    printf("\n  剧本:\n");
    printf("    P0: 更新用户资料 (name=Alice)\n");
    printf("    P1: 更新用户资料 (name=Bob)    —— 同时发生\n");
    printf("    P0: send(sync) → P1\n");
    printf("    P1: recv(sync)\n");
    printf("    此时 P1 应该怎么办?\n\n");

    reset_all();

    proc_local(0, "wr:Alice");       /* P0 本地写 */
    proc_local(1, "wr:Bob");         /* P1 本地写, 与上面并发 */

    int s = proc_send(0, 1, "sync");
    proc_recv(1, 0, s, "recv_sync");

    print_event_list();
    draw_timeline();

    /* 判断: wr:Alice 和 wr:Bob 的关系 */
    int wa = 0, wb = 1;
    printf("\n  \033[1;36m[冲突检测]\033[0m\n");
    printf("    P0 的 'wr:Alice' VC = ");
    vc_print(g_events[wa].vc);
    printf("\n    P1 的 'wr:Bob'   VC = ");
    vc_print(g_events[wb].vc);
    printf("\n");

    if (vc_concurrent(g_events[wa].vc, g_events[wb].vc)) {
        printf("\n    \033[1;31m✗ 检测到冲突: 两个写是并发的\033[0m\n");
        printf("    \033[1;33m→ 需要应用层解决:\033[0m\n");
        printf("        · LWW: 谁的时间戳大选谁\n");
        printf("        · MV: 保留两个版本, 让用户选\n");
        printf("        · CRDT: 自动合并 (比如取并集)\n");
    }

    /* 同步之后, P1 看到的因果 */
    printf("\n  \033[1;36m[同步后 P1 的视角]\033[0m\n");
    printf("    P1 知道 P0 的 wr:Alice 已经发生 (VC 合并了)\n");
    printf("    但 P1 自己的 wr:Bob 与 wr:Alice 是\033[1;33m并发\033[0m的 —— \n");
    printf("    即使 P1 收到了 sync 消息, 也无法从向量时钟判断\n");
    printf("    '谁先发生' —— 因为两者根本没有因果关系。\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════════╗\n");
    printf("║   向量时钟 与 因果序                                     ║\n");
    printf("╚══════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");
    printf("\n进程数: %d\n", N_PROC);

    scenario_1();
    scenario_2();
    scenario_3();

    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════════╗\n");
    printf("║   向量时钟的三条规则                                     ║\n");
    printf("╠══════════════════════════════════════════════════════════╣\n");
    printf("║                                                          ║\n");
    printf("║   1. 本地事件 e 发生在进程 i:                            ║\n");
    printf("║        VC_i[i]++                                         ║\n");
    printf("║                                                          ║\n");
    printf("║   2. 发送消息:                                            ║\n");
    printf("║        先把消息发送事件本身视为一个本地事件              ║\n");
    printf("║        VC_i[i]++, 然后把整个 VC_i 附在消息上             ║\n");
    printf("║                                                          ║\n");
    printf("║   3. 接收消息 (携带 VC_msg):                              ║\n");
    printf("║        for k: VC_i[k] = max(VC_i[k], VC_msg[k])          ║\n");
    printf("║        VC_i[i]++                                         ║\n");
    printf("║                                                          ║\n");
    printf("║   比较规则 (定义 happens-before):                         ║\n");
    printf("║     a → b  ⇔  ∀k VC_a[k] ≤ VC_b[k] 且至少一个严格小于   ║\n");
    printf("║     a ∥ b  ⇔  以上不成立, 且反向也不成立                 ║\n");
    printf("║                                                          ║\n");
    printf("║   性质:                                                   ║\n");
    printf("║     · 传递性: a→b, b→c ⟹ a→c                            ║\n");
    printf("║     · 反自反: ¬(a→a)                                     ║\n");
    printf("║     · 一个进程的事件序列完全有序 (VC 严格递增)           ║\n");
    printf("║     · 不同进程的事件可能并发 (VC 不可比)                 ║\n");
    printf("║                                                          ║\n");
    printf("║   和 Lamport 时钟的区别:                                 ║\n");
    printf("║     Lamport 时钟: 单整数, a→b ⟹ L(a)<L(b), 反之不成立 ║\n");
    printf("║     向量时钟:     N 维, a→b ⟺ VC(a)<VC(b), 充要条件    ║\n");
    printf("║     → 向量时钟能精确判断并发, Lamport 时钟不能          ║\n");
    printf("║                                                          ║\n");
    printf("║   应用:                                                   ║\n");
    printf("║     · Amazon Dynamo —— 冲突检测与版本合并                ║\n");
    printf("║     · Git —— 分支合并的祖先判断 (DAG)                   ║\n");
    printf("║     · CRDT / Riak / Cassandra —— 并发更新检测           ║\n");
    printf("║     · 分布式调试 —— 重建因果图                           ║\n");
    printf("║     · 区块链 —— DAG 类共识 (IOTA / Hedera)              ║\n");
    printf("║                                                          ║\n");
    printf("║   优化: 向量时钟太大怎么办?                              ║\n");
    printf("║     · 稀疏向量 —— 只存已知的活跃进程                     ║\n");
    printf("║     · 区间向量 —— 压缩连续的计数器                       ║\n");
    printf("║     · 哈希摘要 —— Dotted Version Vectors                ║\n");
    printf("╚══════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}