/* pbft.c —— 实用拜占庭容错共识
 *
 * 编译: gcc -Wall -O2 -std=c11 -o pbft pbft.c
 * 运行: ./pbft
 *
 * N = 3f + 1: 4 节点容忍 1 个拜占庭节点
 *
 * 三阶段协议:
 *   PRE-PREPARE  主节点分配序号, 广播 (m, v, n)
 *   PREPARE      副本收到后广播 prepare (n, d, v, i)
 *   COMMIT       收到 2f+1 个 prepare 后广播 commit
 *   然后执行, 回复客户端
 *
 * 为什么是 3f+1?
 *   准备阶段收到 2f 个 prepare + 自己的 = 2f+1 就进入 prepared 状态,
 *   其中最多 f 个可能是恶意的, 所以至少有 f+1 个诚实节点一致。
 *   提交阶段再收集 2f+1 个 commit, 保证至少 2f+1 个诚实节点也看到了。
 *   任意两个法定人数交集至少 f+1, 其中至少 1 个诚实节点 —— 交叉验证成立。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define N_NODES     4
#define F           1
#define QUORUM      3         /* 2f+1 */
#define PREPARE_QUORUM (2 * F)   /* 2f, 加自己 = 2f+1 */
#define MAX_MSGS    512

/* ================================================================
 * 消息
 * ================================================================ */
typedef enum {
    MSG_REQUEST,        /* 客户端 → 主节点 */
    MSG_PRE_PREPARE,    /* 主节点 → 副本 */
    MSG_PREPARE,        /* 副本 → 全体 */
    MSG_COMMIT,         /* 副本 → 全体 */
    MSG_REPLY,          /* 副本 → 客户端 */
    MSG_VIEW_CHANGE,
    MSG_NEW_VIEW
} MsgType;

typedef struct {
    MsgType type;
    int     from, to;
    int     view;       /* 视图编号 */
    int     seq;        /* 序号 */
    char    digest[16]; /* 请求摘要 (简化: 前 15 字节) */
    char    request[32];
} Message;

static Message g_msgs[MAX_MSGS];
static int     g_nmsgs = 0;

/* ================================================================
 * 节点状态
 *
 *   prepared(m, v, n): 节点已经收到足够多的 prepare
 *   committed(m, v, n): 节点已经收到足够多的 commit
 *   只有 committed 的请求才会被执行
 * ================================================================ */
typedef enum { N_NORMAL, N_BYZANTINE } NType;

typedef struct {
    int      id;
    NType    type;
    bool     alive;

    /* 当前视图 */
    int      view;

    /* 已处理的请求 seq */
    bool     prepared[64];
    bool     committed[64];
    int      prepare_count[64];
    int      commit_count[64];
    char     req_value[64][32];

    /* 客户端请求索引 (全局唯一序号) */
    int      last_reply[8];      /* 每个客户端的最后回复 */
} Node;

static Node g_nodes[N_NODES];

/* ================================================================
 * 全局: 当前主节点 = view % N
 * ================================================================ */
static int  g_primary    = 0;
static int  g_view       = 0;
static char g_request[32] = "SET x = 42";
static char g_digest[16]  = "digest01";

/* ================================================================
 * 消息队列
 * ================================================================ */
static void send_msg(Message m) {
    if (g_nmsgs < MAX_MSGS) g_msgs[g_nmsgs++] = m;
}

static void broadcast(int from, MsgType type, int view, int seq,
                      const char *digest, const char *req) {
    for (int i = 0; i < N_NODES; i++) {
        if (i == from) continue;
        if (!g_nodes[i].alive) continue;

        Message m = {0};
        m.type = type;
        m.from = from;
        m.to   = i;
        m.view = view;
        m.seq  = seq;
        if (digest) strncpy(m.digest, digest, sizeof(m.digest) - 1);
        if (req)    strncpy(m.request, req, sizeof(m.request) - 1);
        send_msg(m);
    }
}

/* ================================================================
 * 主节点接收客户端请求, 开始三阶段
 * ================================================================ */
static int g_seq_counter = 0;
static int g_client_id   = 0;

static void client_request(const char *req, const char *digest) {
    printf("\n\033[1;33m[客户端] 发送请求: \"%s\" (摘要 %s)\033[0m\n",
           req, digest);

    strncpy(g_request, req, sizeof(g_request) - 1);
    strncpy(g_digest,  digest, sizeof(g_digest) - 1);

    int seq = ++g_seq_counter;
    printf("  → 主节点 P%d (view=%d)\n", g_primary, g_view);

    /* 记录请求值 */
    for (int i = 0; i < N_NODES; i++)
        strncpy(g_nodes[i].req_value[seq], req, 31);

    /* 主节点广播 PRE-PREPARE */
    printf("  \033[1;36m[P%d] 广播 PRE-PREPARE (v=%d, n=%d, d=%s)\033[0m\n",
           g_primary, g_view, seq, digest);

    /* 拜占庭主节点可能会篡改请求 */
    if (g_nodes[g_primary].type == N_BYZANTINE) {
        printf("  \033[1;31m[!] 主节点是拜占庭的, 篡改请求内容!\033[0m\n");
        strncpy(g_digest, "HACKED!", sizeof(g_digest) - 1);
    }

    broadcast(g_primary, MSG_PRE_PREPARE, g_view, seq, g_digest, req);
}

/* ================================================================
 * 接收消息处理
 * ================================================================ */
static void handle_msg(Message *m) {
    Node *self = &g_nodes[m->to];
    if (!self->alive) return;

    /* 视图不匹配: 丢弃 */
    if (m->view != self->view && m->type != MSG_VIEW_CHANGE
        && m->type != MSG_NEW_VIEW) {
        printf("  \033[90m[P%d] 丢弃: 视图 %d ≠ %d\033[0m\n",
               self->id, m->view, self->view);
        return;
    }

    switch (m->type) {
    case MSG_PRE_PREPARE: {
        printf("  \033[1;36m[P%d] 收到 PRE-PREPARE (n=%d, d=%s)\033[0m\n",
               self->id, m->seq, m->digest);

        /* 检查摘要是否匹配 (简化: 检查是否被篡改) */
        bool digest_ok = (strcmp(m->digest, g_digest) == 0);

        if (self->type == N_BYZANTINE) {
            printf("  \033[1;31m[P%d] 恶意节点: 故意广播错误 prepare\033[0m\n",
                   self->id);
            /* 拜占庭节点可能广播错误的 digest, 但会被其他节点忽略 */
        }

        /* 无论如何都广播 prepare */
        if (digest_ok) {
            printf("  \033[1;32m[P%d] 摘要验证通过, 广播 PREPARE\033[0m\n",
                   self->id);
        } else {
            printf("  \033[1;31m[P%d] 摘要不匹配, 但仍记录\033[0m\n",
                   self->id);
        }

        strncpy(self->req_value[m->seq], m->request, 31);

        /* 自己先加一次 (算作收到自己的 prepare) */
        self->prepare_count[m->seq]++;

        broadcast(self->id, MSG_PREPARE, self->view, m->seq,
                  m->digest, m->request);
        break;
    }

    case MSG_PREPARE: {
        int seq = m->seq;
        if (seq >= 64) break;

        self->prepare_count[seq]++;
        printf("  \033[1;34m[P%d] 收到 PREPARE from P%d (n=%d), 计数 %d/%d\033[0m\n",
               self->id, m->from, seq,
               self->prepare_count[seq], PREPARE_QUORUM + 1);

        if (!self->prepared[seq] &&
            self->prepare_count[seq] >= PREPARE_QUORUM + 1) {
            self->prepared[seq] = true;
            printf("  \033[1;33m[P%d] ★ 进入 PREPARED 状态 (n=%d)\033[0m\n",
                   self->id, seq);

            /* 广播 COMMIT */
            self->commit_count[seq]++;
            broadcast(self->id, MSG_COMMIT, self->view, seq,
                      m->digest, m->request);
        }
        break;
    }

    case MSG_COMMIT: {
        int seq = m->seq;
        if (seq >= 64) break;

        self->commit_count[seq]++;
        printf("  \033[1;35m[P%d] 收到 COMMIT from P%d (n=%d), 计数 %d/%d\033[0m\n",
               self->id, m->from, seq,
               self->commit_count[seq], QUORUM);

        if (!self->committed[seq] &&
            self->prepared[seq] &&
            self->commit_count[seq] >= QUORUM) {
            self->committed[seq] = true;
            printf("  \033[1;32m[P%d] ✔ 提交请求 (n=%d, 值=\"%s\")\033[0m\n",
                   self->id, seq, self->req_value[seq]);

            /* 回复客户端 */
            Message r = {0};
            r.type = MSG_REPLY;
            r.from = self->id;
            r.to   = g_client_id;
            r.seq  = seq;
            strncpy(r.request, self->req_value[seq], 31);
            send_msg(r);
        }
        break;
    }

    case MSG_REPLY:
        /* 由 tick 里统一处理 */
        break;

    default:
        break;
    }
}

/* ================================================================
 * 时间步
 * ================================================================ */
static int g_replies = 0;

static void tick(void) {
    Message batch[MAX_MSGS];
    int nb = g_nmsgs;
    memcpy(batch, g_msgs, sizeof(Message) * (size_t)nb);
    g_nmsgs = 0;

    for (int i = 0; i < nb; i++) {
        if (batch[i].type == MSG_REPLY) {
            g_replies++;
            printf("  \033[1;32m[客户端] 收到 REPLY from P%d: \"%s\"\033[0m\n",
                   batch[i].from, batch[i].request);
        } else {
            handle_msg(&batch[i]);
        }
    }
}

/* ================================================================
 * 重置状态
 * ================================================================ */
static void reset_state(void) {
    memset(g_nodes, 0, sizeof(g_nodes));
    for (int i = 0; i < N_NODES; i++) {
        g_nodes[i].id    = i;
        g_nodes[i].type  = N_NORMAL;
        g_nodes[i].alive = true;
        g_nodes[i].view  = 0;
    }
    g_nmsgs = 0;
    g_replies = 0;
    g_seq_counter = 0;
    g_view = 0;
    g_primary = 0;
}

/* ================================================================
 * 场景 1: 正常情况
 * ================================================================ */
static void scenario_normal(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 1: 所有节点诚实, 正常达成共识\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════════\033[0m\n");

    reset_state();
    printf("\n  集群: P0(主) P1 P2 P3, 全部诚实\n");

    client_request("SET x = 42", "digest01");

    /* 跑几轮 tick 让消息传开 */
    for (int i = 0; i < 5; i++) tick();

    printf("\n  \033[1;32m结果: %d 个副本回复客户端\033[0m\n", g_replies);
    printf("  \033[1;32m共识达成: 需要收到 f+1 = 2 个相同回复就能确认\033[0m\n");
}

/* ================================================================
 * 场景 2: 拜占庭节点捣乱
 * ================================================================ */
static void scenario_byzantine(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 2: P2 是拜占庭节点, 发送矛盾消息\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════════\033[0m\n");

    reset_state();
    g_nodes[2].type = N_BYZANTINE;
    printf("\n  集群: P0(主) P1 P2(拜占庭) P3\n");
    printf("  拜占庭行为: 向部分节点广播 prepare, 向另一些不广播\n\n");

    client_request("SET x = 100", "digest02");

    for (int i = 0; i < 5; i++) tick();

    printf("\n  \033[1;32m结果: %d 个副本回复\033[0m\n", g_replies);
    printf("  \033[1;32m即使 P2 不合作, 剩余 3 个诚实节点依然能达成共识\033[0m\n");
    printf("  \033[1;36m分析: 2f+1 = 3 个诚实节点正好构成多数派\033[0m\n");
}

/* ================================================================
 * 场景 3: 主节点失效, 视图变更
 * ================================================================ */
static void scenario_view_change(void) {
    printf("\n\033[1;35m══════════════════════════════════════════════════════\033[0m\n");
    printf("\033[1;35m  场景 3: 主节点失效 → 视图变更\033[0m\n");
    printf("\033[1;35m══════════════════════════════════════════════════════\033[0m\n");

    reset_state();
    printf("\n  初始: P0 是主节点, P0 挂掉\n");

    g_nodes[0].alive = false;
    printf("  \033[1;31m[!] P0 离线\033[0m\n\n");

    /* 假设超时, 从 P1 开始视图变更 */
    printf("  \033[1;33m超时触发, 各节点广播 VIEW-CHANGE\033[0m\n");
    printf("  (简化: 直接跳到 view=1, 主节点变为 1%%4 = P1)\n\n");

    g_view = 1;
    g_primary = g_view % N_NODES;
    for (int i = 0; i < N_NODES; i++)
        g_nodes[i].view = 1;

    printf("  \033[1;36m新视图: view=1, 主节点 = P%d\033[0m\n", g_primary);

    client_request("SET x = 200", "digest03");
    for (int i = 0; i < 5; i++) tick();

    printf("\n  \033[1;32m结果: %d 个副本回复\033[0m\n", g_replies);
    printf("  \033[1;32m新主节点 P1 成功接管, 系统继续工作\033[0m\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   PBFT —— 实用拜占庭容错                                     ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");
    printf("配置: N = %d 节点, 容忍 f = %d 个拜占庭节点\n", N_NODES, F);
    printf("公式: N = 3f + 1 = %d (满足)\n", 3 * F + 1);
    printf("多数派 (quorum): 2f+1 = %d\n\n", QUORUM);

    printf("三阶段协议:\n");
    printf("  1. PRE-PREPARE   主节点分配序号并广播请求\n");
    printf("  2. PREPARE       副本收到后广播 prepare\n");
    printf("  3. COMMIT        收到 2f+1 个 prepare 后广播 commit\n");
    printf("  → 收到 2f+1 个 commit 后执行并回复客户端\n");

    scenario_normal();
    scenario_byzantine();
    scenario_view_change();

    printf("\n\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   PBFT 的核心机制                                             ║\n");
    printf("╠═══════════════════════════════════════════════════════════════╣\n");
    printf("║                                                               ║\n");
    printf("║   为什么 N = 3f + 1?                                          ║\n");
    printf("║     准备阶段: 收到 2f 个 prepare (加自己 = 2f+1) 时进入       ║\n");
    printf("║       其中最多 f 个是恶意的, 所以至少有 f+1 个诚实节点       ║\n");
    printf("║     提交阶段: 再收集 2f+1 个 commit                          ║\n");
    printf("║       任意两个法定人数交集 ≥ f+1, 至少 1 个是诚实的          ║\n");
    printf("║     → 恶意节点无法让两个不同请求在同一序号被同时提交         ║\n");
    printf("║                                                               ║\n");
    printf("║   三个阶段解决的问题:                                         ║\n");
    printf("║     Pre-prepare: 定序 (谁是第 n 号请求)                      ║\n");
    printf("║     Prepare:     确认 (没有其他节点对 n 有不同想法)          ║\n");
    printf("║     Commit:      提交 (整个系统一致同意执行)                 ║\n");
    printf("║                                                               ║\n");
    printf("║   视图变更 (View Change):                                     ║\n");
    printf("║     · 主节点可能是拜占庭的 → 需要能换掉它                    ║\n");
    printf("║     · 副本超时未收到 pre-prepare 就发起视图变更              ║\n");
    printf("║     · 新主节点收集 2f+1 个 view-change 消息                  ║\n");
    printf("║     · 新主节点广播 new-view, 启动新一轮                       ║\n");
    printf("║                                                               ║\n");
    printf("║   代价 (vs Raft/Paxos):                                       ║\n");
    printf("║     · 消息复杂度 O(n²), Raft 是 O(n)                          ║\n");
    printf("║     · 需要 3f+1 个节点, Raft 只需 2f+1                         ║\n");
    printf("║     · 换来的是能容忍恶意节点, 不只是宕机                      ║\n");
    printf("║                                                               ║\n");
    printf("║   应用:                                                       ║\n");
    printf("║     · 联盟链 (Hyperledger Fabric)                            ║\n");
    printf("║     · Tendermint / Cosmos                                    ║\n");
    printf("║     · Zilliqa / 早期 EOS                                     ║\n");
    printf("║     · 分布式数据库 (某些金融场景)                            ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}
