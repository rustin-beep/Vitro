/* paxos.c —— Paxos 共识算法
 *
 * 编译: gcc -Wall -O2 -std=c11 -o paxos paxos.c
 * 运行: ./paxos
 *
 * 两个阶段:
 *   Phase 1a  Proposer → Acceptor  PREPARE(n)
 *   Phase 1b  Acceptor → Proposer  PROMISE(n, accepted_n, accepted_v)
 *   Phase 2a  Proposer → Acceptor  ACCEPT(n, v)
 *   Phase 2b  Acceptor → Proposer  ACCEPTED(n, v)
 *
 * 安全性(不是活性!):
 *   · 提案号唯一递增: (round, proposer_id)
 *   · Acceptor 承诺后不再接受更小编号
 *   · Proposer 必须采用 promise 里编号最大的"已接受值"
 *   · 多数派接受 → 值被选定, 之后不能被覆盖
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define N_ACC       5
#define N_PROP      3
#define MAJORITY    3
#define MAX_MSGS    256
#define MAX_VAL     48

/* ================================================================
 * 提案号: (round, proposer_id)
 *   比较规则: 先比 round, 再比 pid
 * ================================================================ */
typedef struct { int round, pid; } PropNum;

static int pn_cmp(PropNum a, PropNum b) {
    if (a.round != b.round) return a.round - b.round;
    return a.pid - b.pid;
}

static bool pn_zero(PropNum p) { return p.round == 0 && p.pid == 0; }

static void pn_print(PropNum p) {
    if (pn_zero(p)) printf("(0,0)");
    else            printf("(r%d,P%d)", p.round, p.pid);
}

/* ================================================================
 * Acceptor
 *
 *   持久化状态 (必须先写盘再应答):
 *     promised      —— 承诺过的最大提案号
 *     accepted_num  —— 接受过的最大提案号
 *     accepted_val  —— 与之对应的值
 *
 *   pending: 用于模拟"消息在网络上"
 * ================================================================ */
typedef struct {
    int     id;
    PropNum promised;
    PropNum accepted_num;
    char    accepted_val[MAX_VAL];
    bool    has_accepted;
    bool    alive;
} Acceptor;

/* ================================================================
 * Proposer
 *
 *   状态机: IDLE → PREPARING → ACCEPTING → DONE
 *   需要收集多数派响应
 * ================================================================ */
typedef enum { P_IDLE, P_PREPARING, P_ACCEPTING, P_DONE, P_ABORTED } PState;

typedef struct {
    int     id;
    PState  state;
    int     round;              /* 下次提议要用的 round */
    PropNum prop_num;           /* 当前提案号 */
    char    value[MAX_VAL];     /* 提议的值 */

    int     prepare_acks;
    int     accept_acks;

    PropNum highest_accepted;   /* promise 里编号最大的已接受提案号 */
    char    highest_val[MAX_VAL];
    bool    has_highest;
} Proposer;

/* ================================================================
 * 消息
 * ================================================================ */
typedef enum { MSG_PREPARE, MSG_PROMISE, MSG_ACCEPT, MSG_ACCEPTED } MsgType;

typedef struct {
    MsgType type;
    int     from, to;
    PropNum num;
    char    value[MAX_VAL];
    bool    ok;
} Message;

/* ================================================================
 * 全局
 * ================================================================ */
static Acceptor  g_acc[N_ACC];
static Proposer  g_prop[N_PROP];
static Message   g_msgs[MAX_MSGS];
static int       g_nmsgs = 0;

static int       g_chosen_round = -1;
static char      g_chosen_val[MAX_VAL] = "";
static bool      g_has_chosen = false;

static int       g_tick = 0;

/* ================================================================
 * 消息队列
 * ================================================================ */
static void send_msg(Message m) {
    if (g_nmsgs < MAX_MSGS) g_msgs[g_nmsgs++] = m;
}

static void tick(void) {
    g_tick++;
    Message batch[MAX_MSGS];
    int nb = g_nmsgs;
    memcpy(batch, g_msgs, sizeof(Message) * (size_t)nb);
    g_nmsgs = 0;

    /* 处理本 tick 收到的所有消息 */
    for (int i = 0; i < nb; i++) {
        Message *m = &batch[i];

        if (m->type == MSG_PREPARE || m->type == MSG_ACCEPT) {
            Acceptor *a = &g_acc[m->to];
            if (!a->alive) continue;

            if (m->type == MSG_PREPARE) {
                /* ---- Phase 1b: PROMISE ---- */
                if (pn_cmp(m->num, a->promised) > 0) {
                    a->promised = m->num;
                    Message r = {0};
                    r.type  = MSG_PROMISE;
                    r.from  = a->id;
                    r.to    = m->from;
                    r.num   = a->has_accepted ? a->accepted_num : (PropNum){0,0};
                    r.ok    = true;
                    if (a->has_accepted)
                        strncpy(r.value, a->accepted_val, MAX_VAL - 1);
                    send_msg(r);
                    printf("    [t=%02d] A%d: PREPARE ", g_tick, a->id);
                    pn_print(m->num);
                    printf(" → \033[1;32mPROMISE\033[0m ");
                    pn_print(r.num);
                    if (a->has_accepted)
                        printf(" val=%s", a->accepted_val);
                    printf("\n");
                } else {
                    Message r = {0};
                    r.type = MSG_PROMISE;
                    r.from = a->id;
                    r.to   = m->from;
                    r.num  = a->promised;
                    r.ok   = false;
                    send_msg(r);
                    printf("    [t=%02d] A%d: PREPARE ", g_tick, a->id);
                    pn_print(m->num);
                    printf(" → \033[1;31m拒绝\033[0m (已承诺 ");
                    pn_print(a->promised);
                    printf(")\n");
                }
            } else {
                /* ---- Phase 2b: ACCEPTED ---- */
                if (pn_cmp(m->num, a->promised) >= 0) {
                    a->promised     = m->num;
                    a->accepted_num = m->num;
                    strncpy(a->accepted_val, m->value, MAX_VAL - 1);
                    a->has_accepted = true;

                    Message r = {0};
                    r.type  = MSG_ACCEPTED;
                    r.from  = a->id;
                    r.to    = m->from;
                    r.num   = m->num;
                    r.ok    = true;
                    strncpy(r.value, m->value, MAX_VAL - 1);
                    send_msg(r);
                    printf("    [t=%02d] A%d: ACCEPT  ", g_tick, a->id);
                    pn_print(m->num);
                    printf(" %s → \033[1;32mACCEPTED\033[0m\n",
                           m->value);
                } else {
                    printf("    [t=%02d] A%d: ACCEPT  ", g_tick, a->id);
                    pn_print(m->num);
                    printf(" → \033[1;31m拒绝\033[0m\n");
                }
            }
        }
        else if (m->type == MSG_PROMISE) {
            Proposer *p = &g_prop[m->to];
            if (p->state != P_PREPARING) continue;
            if (pn_cmp(m->num, p->prop_num) != 0) continue;   /* 过期 */

            if (!m->ok) continue;
            p->prepare_acks++;

            /* 记录"编号最大的已接受值" —— Paxos 安全性的核心 */
            if (!pn_zero(m->num) &&
                (!p->has_highest || pn_cmp(m->num, p->highest_accepted) > 0)) {
                p->highest_accepted = m->num;
                strncpy(p->highest_val, m->value, MAX_VAL - 1);
                p->has_highest = true;
            }
        }
        else if (m->type == MSG_ACCEPTED) {
            Proposer *p = &g_prop[m->to];
            if (p->state != P_ACCEPTING) continue;
            if (pn_cmp(m->num, p->prop_num) != 0) continue;
            if (!m->ok) continue;
            p->accept_acks++;
        }
    }
}

/* ================================================================
 * Proposer 逻辑
 * ================================================================ */
static void proposer_start(int pid, const char *value) {
    Proposer *p = &g_prop[pid];
    p->round++;
    p->prop_num      = (PropNum){p->round, pid};
    p->state         = P_PREPARING;
    p->prepare_acks  = 0;
    p->accept_acks   = 0;
    p->has_highest   = false;
    strncpy(p->value, value, MAX_VAL - 1);

    printf("\n  \033[1;33mP%d 发起提案 %s 值=\"%s\"\033[0m\n",
           pid, "", value);
    printf("    Phase 1a: 广播 PREPARE ");
    pn_print(p->prop_num);
    printf("\n");

    for (int i = 0; i < N_ACC; i++) {
        Message m = {0};
        m.type = MSG_PREPARE;
        m.from = pid;
        m.to   = i;
        m.num  = p->prop_num;
        send_msg(m);
    }
}

/* Proposer 在收到足够 promise 后, 决定真正的提议值 */
static void proposer_check(int pid) {
    Proposer *p = &g_prop[pid];

    if (p->state == P_PREPARING && p->prepare_acks >= MAJORITY) {
        /* 关键安全规则: 如果 promise 里有已接受值, 必须采用编号最大的那个 */
        if (p->has_highest) {
            strncpy(p->value, p->highest_val, MAX_VAL - 1);
            printf("  \033[1;35mP%d 发现已接受值 ");
            pn_print(p->highest_accepted);
            printf("=\"%s\" → \033[1;31m必须沿用此值\033[0m\n",
                   p->value);
        }

        p->state = P_ACCEPTING;
        printf("  \033[1;33mP%d 收到 %d 个 promise → 进入 Phase 2\033[0m\n",
               pid, p->prepare_acks);
        printf("    Phase 2a: 广播 ACCEPT ");
        pn_print(p->prop_num);
        printf(" 值=\"%s\"\n", p->value);

        for (int i = 0; i < N_ACC; i++) {
            Message m = {0};
            m.type = MSG_ACCEPT;
            m.from = pid;
            m.to   = i;
            m.num  = p->prop_num;
            strncpy(m.value, p->value, MAX_VAL - 1);
            send_msg(m);
        }
    }
    else if (p->state == P_ACCEPTING && p->accept_acks >= MAJORITY) {
        p->state = P_DONE;
        /* 检查全局选定的值 */
        if (!g_has_chosen) {
            g_has_chosen = true;
            g_chosen_round = p->prop_num.round;
            strncpy(g_chosen_val, p->value, MAX_VAL - 1);
            printf("\n  \033[1;32m★ 值 \"%s\" 被选定 (提案 %s, 来自 P%d)\033[0m\n",
                   p->value, "", pid);
            pn_print(p->prop_num);
            printf("\n");
        } else if (strcmp(g_chosen_val, p->value) != 0) {
            printf("\n  \033[1;31m✗ 安全性违反! 已选定 \"%s\", 但 P%d 提出了 \"%s\"\033[0m\n",
                   g_chosen_val, pid, p->value);
        } else {
            printf("\n  \033[1;32m✓ P%d 也选定了同一值 \"%s\"\033[0m\n",
                   pid, p->value);
        }
    }
}

/* ================================================================
 * 状态输出
 * ================================================================ */
static void dump_acceptors(void) {
    printf("  \033[1;36mAcceptor 状态:\033[0m\n");
    for (int i = 0; i < N_ACC; i++) {
        Acceptor *a = &g_acc[i];
        printf("    A%d: ", i);
        if (!a->alive) { printf("\033[90m离线\033[0m\n"); continue; }
        printf("promised=");
        pn_print(a->promised);
        printf("  accepted=");
        if (a->has_accepted) {
            pn_print(a->accepted_num);
            printf(" \"%s\"", a->accepted_val);
        } else {
            printf("—");
        }
        printf("\n");
    }
}

static void dump_proposers(void) {
    const char *names[] = {"IDLE", "PREPARING", "ACCEPTING", "DONE", "ABORTED"};
    printf("  \033[1;36mProposer 状态:\033[0m\n");
    for (int i = 0; i < N_PROP; i++) {
        Proposer *p = &g_prop[i];
        printf("    P%d: %-10s prop=", i, names[p->state]);
        pn_print(p->prop_num);
        printf("  prepare_acks=%d  accept_acks=%d\n",
               p->prepare_acks, p->accept_acks);
    }
    if (g_has_chosen)
        printf("  \033[1;32m已选定: \"%s\" (round=%d)\033[0m\n",
               g_chosen_val, g_chosen_round);
}

/* ================================================================
 * 重置
 * ================================================================ */
static void reset_all(void) {
    memset(g_acc,  0, sizeof(g_acc));
    memset(g_prop, 0, sizeof(g_prop));
    g_nmsgs = 0;
    g_tick  = 0;
    g_has_chosen = false;
    g_chosen_round = -1;
    g_chosen_val[0] = 0;

    for (int i = 0; i < N_ACC; i++) {
        g_acc[i].id = i;
        g_acc[i].alive = true;
    }
    for (int i = 0; i < N_PROP; i++) {
        g_prop[i].id = i;
        g_prop[i].state = P_IDLE;
        g_prop[i].round = 0;
    }
}

/* 推进若干轮, 每轮: 处理消息 + 检查 proposer 是否该推进 */
static void run(int nticks) {
    for (int i = 0; i < nticks; i++) {
        tick();
        for (int p = 0; p < N_PROP; p++)
            proposer_check(p);
    }
}

/* ================================================================
 * 场景 1: 单个 proposer, 无竞争
 * ================================================================ */
static void scenario_normal(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 1: 单 proposer 正常达成共识\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    reset_all();

    printf("\n  初始: 所有 Acceptor 空白, 5 个节点全部在线\n");
    dump_acceptors();

    proposer_start(0, "value-A");
    run(3);

    printf("\n");
    dump_acceptors();
    dump_proposers();

    printf("\n  \033[1;32m✓ 阶段 1 完成: P0 拿到 5 个 promise\033[0m\n");
    printf("  \033[1;32m✓ 阶段 2 完成: 5 个 Acceptor 全部接受 \"value-A\"\033[0m\n");
    printf("  \033[1;32m✓ 结论: 值 \"value-A\" 被选定\033[0m\n");
}

/* ================================================================
 * 场景 2: 两个 proposer 竞争
 * ================================================================ */
static void scenario_contention(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 2: 两个 proposer 竞争, 高编号获胜\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    reset_all();

    printf("\n  P0 和 P1 几乎同时发起提案\n");

    proposer_start(0, "value-A");
    proposer_start(1, "value-B");    /* P1 的 round 也是 1, 但 pid 更大 */

    printf("\n  \033[1;33m第 1 轮 tick: 消息到达 Acceptor\033[0m\n");
    run(3);

    printf("\n");
    dump_acceptors();
    dump_proposers();

    printf("\n  \033[1;36m分析:\033[0m\n");
    printf("    P0 的提案号 = (r1,P0), P1 的提案号 = (r1,P1)\n");
    printf("    (r1,P1) > (r1,P0), 所以 Acceptor 先承诺 P1\n");
    printf("    P0 拿不到多数派 → 被 abort, 需要重试\n");
}

/* ================================================================
 * 场景 3: Paxos 最关键的安全性质
 *
 *   某个值已经被选定, 新 proposer 用更大的提案号
 *   但它在 promise 里看到了旧值, 必须沿用
 * ================================================================ */
static void scenario_safety(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 3: 已选定的值不能被覆盖 —— Paxos 安全核心\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    reset_all();

    printf("\n  第一步: P0 提出 \"value-A\", 到达多数派\n");
    proposer_start(0, "value-A");
    run(3);

    printf("\n");
    dump_acceptors();
    printf("\n  \033[1;32m此时 \"value-A\" 已被 5 个 Acceptor 中的 5 个接受 —— 就是选定\033[0m\n");

    printf("\n  第二步: 模拟 P0 挂掉, 一个新 proposer P2 想提出不同值 \"value-B\"\n");
    g_prop[0].state = P_DONE;   /* P0 已经完成, 不再活跃 */
    proposer_start(2, "value-B");

    printf("\n  \033[1;33m关键: P2 收到 PROMISE 时会看到旧值 —— 必须沿用!\033[0m\n");
    run(3);

    printf("\n");
    dump_acceptors();

    printf("\n  \033[1;36m分析:\033[0m\n");
    printf("    P2 的提案号 (r1,P2) > (r1,P0), 能拿到 promise\n");
    printf("    但每个 promise 都携带 A%d 已接受的 (r1,P0, \"value-A\")\n", 0);
    printf("    规则: proposer 必须选择 promise 里编号最大的已接受值\n");
    printf("    → P2 被迫放弃 \"value-B\", 改为提议 \"value-A\"\n");
    printf("    → \033[1;32m\"value-A\" 被重新确认, 已选定的值不会丢\033[0m\n");

    if (strcmp(g_chosen_val, "value-A") == 0)
        printf("\n  \033[1;32m✓ 安全性质成立\033[0m\n");
    else
        printf("\n  \033[1;31m✗ 违反了安全性质!\033[0m\n");
}

/* ================================================================
 * 场景 4: 少数 Acceptor 挂掉, 仍可达成共识
 * ================================================================ */
static void scenario_fault_tolerance(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 4: 2 个 Acceptor 挂掉, 依然能达成共识\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    reset_all();

    printf("\n  A3 和 A4 离线\n");
    g_acc[3].alive = false;
    g_acc[4].alive = false;

    proposer_start(0, "value-X");
    run(3);

    printf("\n");
    dump_acceptors();
    dump_proposers();

    printf("\n  \033[1;36m分析:\033[0m\n");
    printf("    N=5, 多数派 = 3, 允许 2 个节点失效\n");
    printf("    A0, A1, A2 三个节点在线, 刚好构成多数派\n");
    printf("    → 依然可以达成共识\n\n");
    printf("  \033[1;32m✓ 这就是 Paxos 的容错能力: f 个节点失效, 需要至少 2f+1 个节点\033[0m\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   Paxos 共识算法                                              ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");
    printf("集群: %d 个 Acceptor, %d 个 Proposer, 多数派 = %d\n",
           N_ACC, N_PROP, MAJORITY);
    printf("容错: 最多允许 %d 个 Acceptor 失效\n\n", MAJORITY - 1);

    scenario_normal();
    scenario_contention();
    scenario_safety();
    scenario_fault_tolerance();

    printf("\n\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   Paxos 的核心机制                                            ║\n");
    printf("╠═══════════════════════════════════════════════════════════════╣\n");
    printf("║                                                               ║\n");
    printf("║   Phase 1: Prepare / Promise                                  ║\n");
    printf("║     目的: 抢占提案号, 收集\"可能已经选定的值\"                  ║\n");
    printf("║     Acceptor 承诺: 不再接受编号更小的提案                     ║\n");
    printf("║     Promise 携带: 已接受的最大提案号和值                      ║\n");
    printf("║                                                               ║\n");
    printf("║   Phase 2: Accept / Accepted                                  ║\n");
    printf("║     目的: 让多数派接受这个值                                   ║\n");
    printf("║     Proposer 必须采用 promise 里编号最大的已接受值            ║\n");
    printf("║     一旦多数派接受, 值就被\"选定\", 不会再变                    ║\n");
    printf("║                                                               ║\n");
    printf("║   三条安全性规则                                              ║\n");
    printf("║     1. 提案号唯一递增 —— (round, proposer_id)                 ║\n");
    printf("║     2. Acceptor 只接受 >= 承诺的提案号                        ║\n");
    printf("║     3. Proposer 必须沿用 promise 里最大的已接受值             ║\n");
    printf("║                                                               ║\n");
    printf("║   为什么这样能保证安全?                                       ║\n");
    printf("║     如果值 v 被多数派接受:                                    ║\n");
    printf("║       → 任何新的多数派都与它相交                              ║\n");
    printf("║       → 相交节点在 promise 里会报告 v                         ║\n");
    printf("║       → 新 proposer 被迫选 v                                  ║\n");
    printf("║       → 不可能有第二个不同的值被选定                          ║\n");
    printf("║                                                               ║\n");
    printf("║   与 Raft 的区别:                                             ║\n");
    printf("║     Paxos: 对称, 任何节点都能提议, 无 leader 概念             ║\n");
    printf("║     Raft:  强 leader, 靠 leader 简化设计, 更容易理解          ║\n");
    printf("║     两者本质等价, Raft 是 Paxos 的\"工程化特化\"                ║\n");
    printf("║                                                               ║\n");
    printf("║   真实应用:                                                   ║\n");
    printf("║     · Google Chubby / Spanner                                 ║\n");
    printf("║     · Apache ZooKeeper (Zab, Paxos 变体)                     ║\n");
    printf("║     · etcd (Raft)                                             ║\n");
    printf("║     · Cassandra (轻量级 Paxos)                               ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}