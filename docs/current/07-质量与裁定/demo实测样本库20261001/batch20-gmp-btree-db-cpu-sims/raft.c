/* raft.c —— Raft 共识算法模拟
 *
 * 编译: gcc -Wall -O2 -std=c11 -o raft raft.c
 * 运行: ./raft
 *
 * 5 个节点，内存消息队列，tick 为时间单位。
 *
 * 三个阶段:
 *   1. 选举: 某个 follower 超时 → candidate → 拉票 → leader
 *   2. 复制: 客户端提交命令 → leader 追加 → 广播 → 多数确认 → commit
 *   3. 恢复: leader 挂掉 → 新选举 → 已提交日志不丢
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define N_NODES          5
#define MAJORITY         3
#define MAX_LOG          32
#define MAX_MSGS         256
#define HEARTBEAT        3
#define ELECTION_MIN     10
#define ELECTION_MAX     18

typedef enum { FOLLOWER, CANDIDATE, LEADER } Role;
typedef enum {
    MSG_REQUEST_VOTE, MSG_REQUEST_VOTE_REPLY,
    MSG_APPEND_ENTRIES, MSG_APPEND_ENTRIES_REPLY
} MsgType;

typedef struct {
    int term;
    int cmd;
} LogEntry;

typedef struct {
    MsgType type;
    int     from, to;
    int     term;
    /* RequestVote */
    int     candidate_id;
    int     last_log_index, last_log_term;
    bool    vote_granted;
    /* AppendEntries */
    int     leader_id;
    int     prev_log_index, prev_log_term;
    LogEntry entries[8];
    int     n_entries;
    int     leader_commit;
    /* AppendEntries reply */
    bool    success;
    int     match_index;
} Message;

typedef struct {
    int      id;
    Role     role;
    int      current_term;
    int      voted_for;

    LogEntry log[MAX_LOG + 1];       /* 1-indexed */
    int      log_len;

    int      commit_index;
    int      last_applied;

    int      next_index[N_NODES + 1];
    int      match_index[N_NODES + 1];

    int      votes_received;
    int      election_timeout;
    int      election_elapsed;
    int      heartbeat_elapsed;
    int      leader_id;
} Node;

static Node    g_nodes[N_NODES + 1];
static Message g_msgs[MAX_MSGS];
static int     g_nmsgs = 0;
static int     g_tick  = 0;

/* ================================================================
 * 工具
 * ================================================================ */
static const char *role_name(Role r) {
    switch (r) {
    case FOLLOWER:  return "\033[1;36mF\033[0m";
    case CANDIDATE: return "\033[1;33mC\033[0m";
    case LEADER:    return "\033[1;31mL\033[0m";
    }
    return "?";
}

static void tprintf(void) {
    printf("\033[90m[t=%02d]\033[0m ", g_tick);
}

static void send_msg(Message m) {
    if (g_nmsgs < MAX_MSGS) g_msgs[g_nmsgs++] = m;
}

static int rand_timeout(void) {
    return ELECTION_MIN + rand() % (ELECTION_MAX - ELECTION_MIN + 1);
}

static void reset_election_timer(Node *n) {
    n->election_elapsed = 0;
    n->election_timeout = rand_timeout();
}

static int last_log_term(Node *n) {
    return n->log_len == 0 ? 0 : n->log[n->log_len].term;
}

/* 候选人的日志是否至少和我一样新 */
static bool log_up_to_date(Node *n, int idx, int term) {
    int my_t = last_log_term(n);
    int my_i = n->log_len;
    if (term != my_t) return term > my_t;
    return idx >= my_i;
}

/* ================================================================
 * 状态转换
 * ================================================================ */
static void become_follower(Node *n, int term) {
    if (term > n->current_term) {
        n->current_term = term;
        n->voted_for = -1;
    }
    if (n->role != FOLLOWER) {
        tprintf();
        printf("  T%d %s → \033[1;36mFOLLOWER\033[0m (term %d)\n",
               n->id, role_name(n->role), n->current_term);
    }
    n->role = FOLLOWER;
    reset_election_timer(n);
}

static void become_leader(Node *n) {
    n->role = LEADER;
    for (int i = 1; i <= N_NODES; i++) {
        n->next_index[i]  = n->log_len + 1;
        n->match_index[i] = 0;
    }
    n->match_index[n->id] = n->log_len;
    tprintf();
    printf("  \033[1;31m★ T%d 成为 LEADER (term %d, 日志长度 %d)\033[0m\n",
           n->id, n->current_term, n->log_len);
}

static void start_election(Node *n) {
    n->role = CANDIDATE;
    n->current_term++;
    n->voted_for = n->id;
    n->votes_received = 1;
    reset_election_timer(n);

    tprintf();
    printf("  T%d \033[1;33m发起选举\033[0m (term %d)\n",
           n->id, n->current_term);

    for (int i = 1; i <= N_NODES; i++) {
        if (i == n->id) continue;
        Message m = {0};
        m.type = MSG_REQUEST_VOTE;
        m.from = n->id;
        m.to   = i;
        m.term = n->current_term;
        m.candidate_id   = n->id;
        m.last_log_index = n->log_len;
        m.last_log_term  = last_log_term(n);
        send_msg(m);
    }
}

/* ================================================================
 * 消息处理
 * ================================================================ */
static void handle_request_vote(Node *n, Message *m) {
    Message reply = {0};
    reply.type = MSG_REQUEST_VOTE_REPLY;
    reply.from = n->id;
    reply.to   = m->from;
    reply.term = n->current_term;

    if (m->term < n->current_term) {
        send_msg(reply);
        return;
    }
    if (m->term > n->current_term)
        become_follower(n, m->term);

    bool can_vote = (n->voted_for == -1 || n->voted_for == m->candidate_id);
    bool fresh    = log_up_to_date(n, m->last_log_index, m->last_log_term);

    if (can_vote && fresh) {
        n->voted_for = m->candidate_id;
        reply.vote_granted = true;
        reset_election_timer(n);
        tprintf();
        printf("  T%d 投票给 T%d (term %d)\n",
               n->id, m->candidate_id, n->current_term);
    } else {
        tprintf();
        printf("  T%d 拒绝 T%d (%s)\n", n->id, m->candidate_id,
               !can_vote ? "本任期已投票" : "日志不够新");
    }
    send_msg(reply);
}

static void handle_append_entries(Node *n, Message *m) {
    Message reply = {0};
    reply.type = MSG_APPEND_ENTRIES_REPLY;
    reply.from = n->id;
    reply.to   = m->from;
    reply.term = n->current_term;

    if (m->term < n->current_term) {
        send_msg(reply);
        return;
    }
    if (m->term > n->current_term)
        become_follower(n, m->term);

    n->role      = FOLLOWER;
    n->leader_id = m->leader_id;
    reset_election_timer(n);

    /* prev_log 检查 */
    if (m->prev_log_index > n->log_len) {
        tprintf();
        printf("  T%d 拒绝 AppendEntries: 日志太短 (需 %d, 有 %d)\n",
               n->id, m->prev_log_index, n->log_len);
        send_msg(reply);
        return;
    }
    if (m->prev_log_index > 0 &&
        n->log[m->prev_log_index].term != m->prev_log_term) {
        tprintf();
        printf("  T%d 拒绝 AppendEntries: term 不匹配\n", n->id);
        send_msg(reply);
        return;
    }

    /* 追加/覆盖冲突部分 */
    int appended = 0;
    for (int i = 0; i < m->n_entries; i++) {
        int pos = m->prev_log_index + 1 + i;
        if (pos <= n->log_len) {
            if (n->log[pos].term != m->entries[i].term) {
                n->log_len = pos - 1;
                n->log[pos] = m->entries[i];
                n->log_len = pos;
                appended++;
            }
        } else {
            n->log[pos] = m->entries[i];
            n->log_len = pos;
            appended++;
        }
    }
    if (appended > 0) {
        tprintf();
        printf("  T%d 追加 %d 条日志, 现在长度 %d\n",
               n->id, appended, n->log_len);
    }

    if (m->leader_commit > n->commit_index) {
        int newc = m->leader_commit;
        if (newc > n->log_len) newc = n->log_len;
        if (newc > n->commit_index) {
            n->commit_index = newc;
            tprintf();
            printf("  T%d \033[1;32mcommitIndex → %d\033[0m\n",
                   n->id, n->commit_index);
        }
    }

    reply.success     = true;
    reply.match_index = m->prev_log_index + m->n_entries;
    send_msg(reply);
}

static void handle_vote_reply(Node *n, Message *m) {
    if (m->term > n->current_term) {
        become_follower(n, m->term);
        return;
    }
    if (n->role != CANDIDATE || m->term != n->current_term) return;
    if (!m->vote_granted) return;

    n->votes_received++;
    if (n->votes_received >= MAJORITY) {
        become_leader(n);
    }
}

static void handle_append_reply(Node *n, Message *m) {
    if (m->term > n->current_term) {
        become_follower(n, m->term);
        return;
    }
    if (n->role != LEADER || m->term != n->current_term) return;

    if (m->success) {
        if (m->match_index > n->match_index[m->from])
            n->match_index[m->from] = m->match_index;
        n->next_index[m->from] = n->match_index[m->from] + 1;

        /* 尝试推进 commitIndex：只能 commit 当前任期的日志 */
        for (int N = n->log_len; N > n->commit_index; N--) {
            if (n->log[N].term != n->current_term) break;
            int count = 1;
            for (int j = 1; j <= N_NODES; j++) {
                if (j == n->id) continue;
                if (n->match_index[j] >= N) count++;
            }
            if (count >= MAJORITY) {
                n->commit_index = N;
                tprintf();
                printf("  \033[1;32m★ T%d commitIndex = %d (命令 %d)\033[0m\n",
                       n->id, N, n->log[N].cmd);
                break;
            }
        }
    } else {
        if (n->next_index[m->from] > 1)
            n->next_index[m->from]--;
    }
}

static void deliver(Message *m) {
    Node *n = &g_nodes[m->to];
    switch (m->type) {
    case MSG_REQUEST_VOTE:         handle_request_vote(n, m); break;
    case MSG_REQUEST_VOTE_REPLY:   handle_vote_reply(n, m);   break;
    case MSG_APPEND_ENTRIES:       handle_append_entries(n, m); break;
    case MSG_APPEND_ENTRIES_REPLY: handle_append_reply(n, m); break;
    }
}

/* ================================================================
 * Leader 广播
 * ================================================================ */
static void leader_broadcast(Node *n) {
    for (int i = 1; i <= N_NODES; i++) {
        if (i == n->id) continue;

        int prev_idx  = n->next_index[i] - 1;
        int prev_term = (prev_idx > 0 && prev_idx <= n->log_len)
                        ? n->log[prev_idx].term : 0;

        Message m = {0};
        m.type = MSG_APPEND_ENTRIES;
        m.from = n->id;
        m.to   = i;
        m.term = n->current_term;
        m.leader_id       = n->id;
        m.prev_log_index  = prev_idx;
        m.prev_log_term   = prev_term;
        m.leader_commit   = n->commit_index;

        int k = 0;
        for (int j = n->next_index[i]; j <= n->log_len && k < 8; j++)
            m.entries[k++] = n->log[j];
        m.n_entries = k;

        send_msg(m);
    }
}

/* ================================================================
 * 时间步进
 * ================================================================ */
static void tick(void) {
    g_tick++;

    /* 1. 定时器检查 */
    for (int i = 1; i <= N_NODES; i++) {
        Node *n = &g_nodes[i];
        if (n->role == LEADER) {
            n->heartbeat_elapsed++;
            if (n->heartbeat_elapsed >= HEARTBEAT) {
                n->heartbeat_elapsed = 0;
                leader_broadcast(n);
            }
        } else {
            n->election_elapsed++;
            if (n->election_elapsed >= n->election_timeout) {
                start_election(n);
            }
        }
    }

    /* 2. 投递当前所有消息（新发的消息下一轮处理，模拟网络延迟） */
    Message batch[MAX_MSGS];
    int nb = g_nmsgs;
    memcpy(batch, g_msgs, sizeof(Message) * (size_t)nb);
    g_nmsgs = 0;
    for (int i = 0; i < nb; i++)
        deliver(&batch[i]);
}

/* ================================================================
 * 客户端提交命令
 * ================================================================ */
static void client_append(int leader_id, int cmd) {
    Node *n = &g_nodes[leader_id];
    if (n->role != LEADER) {
        printf("  客户端: T%d 不是 leader, 拒绝\n", leader_id);
        return;
    }
    n->log_len++;
    n->log[n->log_len].term = n->current_term;
    n->log[n->log_len].cmd  = cmd;
    n->match_index[n->id]   = n->log_len;

    printf("\n");
    tprintf();
    printf("  \033[1;35m客户端 → T%d: 追加命令 %d (位置 %d)\033[0m\n",
           leader_id, cmd, n->log_len);
    leader_broadcast(n);
}

/* ================================================================
 * 状态快照
 * ================================================================ */
static int find_leader(void) {
    for (int i = 1; i <= N_NODES; i++)
        if (g_nodes[i].role == LEADER) return i;
    return -1;
}

static void dump_cluster(const char *title) {
    printf("\n  \033[1;36m[%s]\033[0m\n", title);
    for (int i = 1; i <= N_NODES; i++) {
        Node *n = &g_nodes[i];
        printf("    T%d %s term=%-2d log=[",
               n->id, role_name(n->role), n->current_term);
        for (int j = 1; j <= n->log_len; j++) {
            if (j > 1) printf(",");
            if (j <= n->commit_index) printf("\033[1;32m%d\033[0m", n->log[j].cmd);
            else                       printf("\033[33m%d\033[0m", n->log[j].cmd);
        }
        printf("] commit=%d\n", n->commit_index);
    }
    printf("    \033[90m(绿色=已提交, 黄色=已复制但未提交)\033[0m\n");
}

/* ================================================================
 * 主流程
 * ================================================================ */
static void run_ticks(int n) {
    for (int i = 0; i < n; i++) tick();
}

int main(void) {
    srand(42);

    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   Raft 共识算法：选举 / 复制 / 提交 / 恢复           ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");
    printf("集群: 5 节点, 多数派 = 3\n");
    printf("角色: \033[1;36mF\033[0m=Follower  "
           "\033[1;33mC\033[0m=Candidate  \033[1;31mL\033[0m=Leader\n\n");

    /* ---- 初始化 ---- */
    for (int i = 1; i <= N_NODES; i++) {
        Node *n = &g_nodes[i];
        memset(n, 0, sizeof(*n));
        n->id = i;
        n->role = FOLLOWER;
        n->voted_for = -1;
        n->leader_id = -1;
        reset_election_timer(n);
    }

    /* ============================================================
     * 阶段 1: 选举
     * ============================================================ */
    printf("\033[1;35m════════ 阶段 1: 领导者选举 ════════\033[0m\n\n");

    int leader_id = -1;
    for (int i = 0; i < 40; i++) {
        tick();
        leader_id = find_leader();
        if (leader_id >= 0) break;
    }

    if (leader_id < 0) {
        printf("选举失败\n");
        return 1;
    }

    dump_cluster("选举后的集群状态");

    /* ============================================================
     * 阶段 2: 日志复制
     * ============================================================ */
    printf("\n\033[1;35m════════ 阶段 2: 日志复制 ════════\033[0m\n");

    client_append(leader_id, 100);
    run_ticks(4);

    client_append(leader_id, 200);
    run_ticks(4);

    client_append(leader_id, 300);
    run_ticks(6);

    dump_cluster("三条命令提交后");

    /* ============================================================
     * 阶段 3: 一个 follower 落后，然后追赶
     * ============================================================ */
    printf("\n\033[1;35m════════ 阶段 3: follower 落后再追赶 ════════\033[0m\n");

    /* 找一个非 leader 的 follower 让它"挂"一会 */
    int lagging = -1;
    for (int i = 1; i <= N_NODES; i++)
        if (i != leader_id && g_nodes[i].role == FOLLOWER) {
            lagging = i;
            break;
        }

    printf("  模拟: T%d 暂时断网\n", lagging);
    /* 让它投票给一个"高 term"来模拟它不响应——直接给它一个大 timeout */
    g_nodes[lagging].election_timeout = 10000;

    client_append(leader_id, 400);
    run_ticks(4);
    client_append(leader_id, 500);
    run_ticks(4);

    dump_cluster("T 断网期间, 其他 4 台继续提交");

    printf("\n  模拟: T%d 恢复\n", lagging);
    g_nodes[lagging].election_timeout = 1;   /* 立刻检查 */
    g_nodes[lagging].election_elapsed = 1;

    /* Leader 下次心跳会带上缺失的日志 */
    run_ticks(8);

    dump_cluster("T 追上后");

    /* ============================================================
     * 阶段 4: Leader 挂掉 → 重新选举
     * ============================================================ */
    printf("\n\033[1;35m════════ 阶段 4: Leader 挂掉再选举 ════════\033[0m\n");

    printf("\n  模拟: T%d (当前 leader) 崩溃\n", leader_id);

    /* 让 leader 停止响应: 把它变成特殊的"死"状态 */
    g_nodes[leader_id].election_timeout = 100000;
    g_nodes[leader_id].role = FOLLOWER;
    /* 同时让它不再回应任何消息：通过把它的 current_term 设为极大，
     * 让它拒绝所有入站请求，也不会成为 leader */
    g_nodes[leader_id].current_term = 9999;

    /* 其他节点重新选举 */
    int old_leader = leader_id;
    int new_leader = -1;

    for (int i = 0; i < 60; i++) {
        tick();
        new_leader = find_leader();
        if (new_leader >= 0 && new_leader != old_leader) break;
    }

    if (new_leader >= 0 && new_leader != old_leader) {
        printf("\n  新 leader: T%d\n", new_leader);
    }

    /* 从"死亡"状态恢复旧 leader，让它跟随新 leader */
    g_nodes[old_leader].current_term = 0;
    g_nodes[old_leader].role = FOLLOWER;
    g_nodes[old_leader].election_timeout = rand_timeout();
    g_nodes[old_leader].election_elapsed = 0;
    run_ticks(8);

    dump_cluster("选举恢复后");

    /* ============================================================
     * 总结
     * ============================================================ */
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   Raft 的三条核心安全性                              ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║   1. 选举安全                                         ║\n");
    printf("║      每个任期最多一个 leader —— 靠『每任只投一票』    ║\n");
    printf("║                                                      ║\n");
    printf("║   2. 日志匹配                                         ║\n");
    printf("║      如果两条日志的 index+term 相同, 则它们之前       ║\n");
    printf("║      的所有日志都相同                                 ║\n");
    printf("║                                                      ║\n");
    printf("║   3. Leader 完全性                                    ║\n");
    printf("║      只有包含所有已提交日志的节点才能当选             ║\n");
    printf("║      —— 靠『日志新旧比较』过滤                       ║\n");
    printf("║                                                      ║\n");
    printf("║   关键机制:                                           ║\n");
    printf("║     · 随机选举超时 → 避免选票分裂                     ║\n");
    printf("║     · nextIndex / matchIndex → 增量同步              ║\n");
    printf("║     · 只 commit 当前任期的日志 → 防止幽灵提交        ║\n");
    printf("║     · 多数派写 → 已提交的日志不会丢失                ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}