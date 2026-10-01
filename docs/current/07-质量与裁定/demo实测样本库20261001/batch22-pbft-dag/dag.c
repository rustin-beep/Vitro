/* dag.c —— DAG 类共识（Tangle 风格）
 *
 * 编译: gcc -Wall -O2 -std=c11 -o dag dag.c
 * 运行: ./dag
 *
 * 核心思想:
 *   没有区块、没有 leader、没有显式投票。
 *   每个事件引用 1~2 个已有事件作为"父节点", 形成 DAG。
 *   累积权重 = 有多少后代(直接或间接)引用它 —— 这就是隐式投票。
 *   权重超过阈值 → 事件被确认。
 *   拓扑排序给出唯一的全局一致顺序。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define N_NODES      3
#define MAX_EVENTS   60
#define CONFIRM_MIN  3
#define N_ROUNDS     5

/* ================================================================
 * 事件与节点
 * ================================================================ */
typedef struct {
    int  id;
    int  creator;
    int  parent1, parent2;   /* 引用的父事件 id, -1 = 无 */
    int  weight;             /* 累积权重 = 后代数量 */
    bool confirmed;
    int  confirmed_at;       /* 在哪个 tick 被确认 */
} Event;

typedef struct {
    bool seen[MAX_EVENTS];   /* 本地视图: 节点见过哪些事件 */
} Node;

static Event g_events[MAX_EVENTS];
static int   g_nevents = 0;
static Node  g_nodes[N_NODES];
static int   g_tick = 0;

/* ================================================================
 * 创建事件
 *   gossip=true  → 所有节点立刻可见 (创世事件)
 *   gossip=false → 仅创建者可见, 稍后手动 gossip
 * ================================================================ */
static int create_event(int creator, int p1, int p2, bool gossip) {
    int id = g_nevents++;
    Event *e = &g_events[id];
    e->id           = id;
    e->creator      = creator;
    e->parent1      = p1;
    e->parent2      = p2;
    e->weight       = 0;
    e->confirmed    = false;
    e->confirmed_at = -1;

    if (gossip) {
        for (int i = 0; i < N_NODES; i++)
            g_nodes[i].seen[id] = true;
    } else {
        g_nodes[creator].seen[id] = true;
    }
    return id;
}

static void gossip_event(int id) {
    for (int i = 0; i < N_NODES; i++)
        g_nodes[i].seen[id] = true;
}

/* ================================================================
 * 找节点视角下的"tips" —— 所有已知但没有被引用的事件
 * ================================================================ */
static int find_tips(int node_id, int *tips, int max) {
    int count = 0;
    for (int i = 0; i < g_nevents; i++) {
        if (!g_nodes[node_id].seen[i]) continue;

        bool has_child = false;
        for (int j = 0; j < g_nevents; j++) {
            if (!g_nodes[node_id].seen[j]) continue;
            if (g_events[j].parent1 == i || g_events[j].parent2 == i) {
                has_child = true;
                break;
            }
        }
        if (!has_child && count < max)
            tips[count++] = i;
    }
    return count;
}

/* ================================================================
 * 累积权重
 *
 *   对每个事件 X, 沿父边向上标记所有祖先。
 *   每标记一个祖先, 就给那个祖先的权重 +1。
 *   结果: 一个事件的权重 = 直接或间接引用它的后代总数。
 * ================================================================ */
static void compute_weights(void) {
    for (int i = 0; i < g_nevents; i++)
        g_events[i].weight = 0;

    for (int i = 0; i < g_nevents; i++) {
        bool visited[MAX_EVENTS] = {false};
        int  stack[MAX_EVENTS * 2];
        int  top = 0;

        if (g_events[i].parent1 >= 0)
            stack[top++] = g_events[i].parent1;
        if (g_events[i].parent2 >= 0)
            stack[top++] = g_events[i].parent2;

        while (top > 0) {
            int p = stack[--top];
            if (p < 0 || visited[p]) continue;
            visited[p] = true;
            g_events[p].weight++;

            if (g_events[p].parent1 >= 0)
                stack[top++] = g_events[p].parent1;
            if (g_events[p].parent2 >= 0)
                stack[top++] = g_events[p].parent2;
        }
    }
}

/* ================================================================
 * 确认: 权重达到阈值即视为"被认可"
 * ================================================================ */
static void confirm_events(void) {
    for (int i = 0; i < g_nevents; i++) {
        if (g_events[i].confirmed) continue;
        if (g_events[i].weight >= CONFIRM_MIN) {
            g_events[i].confirmed    = true;
            g_events[i].confirmed_at = g_tick;
        }
    }
}

/* ================================================================
 * 拓扑排序: DAG 的因果序 —— 就是最终共识顺序
 * ================================================================ */
static void topo_sort(int *order, int *n) {
    int in_deg[MAX_EVENTS] = {0};

    /* 入度 = 引用的父节点数 */
    for (int i = 0; i < g_nevents; i++) {
        if (g_events[i].parent1 >= 0) in_deg[i]++;
        if (g_events[i].parent2 >= 0) in_deg[i]++;
    }

    int queue[MAX_EVENTS], qh = 0, qt = 0;
    for (int i = 0; i < g_nevents; i++)
        if (in_deg[i] == 0) queue[qt++] = i;

    *n = 0;
    while (qh < qt) {
        int cur = queue[qh++];
        order[(*n)++] = cur;

        for (int j = 0; j < g_nevents; j++) {
            if (g_events[j].parent1 == cur || g_events[j].parent2 == cur) {
                if (--in_deg[j] == 0)
                    queue[qt++] = j;
            }
        }
    }
}

/* ================================================================
 * 打印
 * ================================================================ */
static void print_events(void) {
    printf("    ID   创建  引用               权重  状态\n");
    printf("    ──   ────  ─────────────────  ────  ──────────────────\n");
    for (int i = 0; i < g_nevents; i++) {
        Event *e = &g_events[i];
        printf("    E%-2d  N%d    ", e->id, e->creator);

        char refs[28] = "(创世)";
        if (e->parent1 >= 0 && e->parent2 >= 0)
            snprintf(refs, sizeof(refs), "E%d, E%d", e->parent1, e->parent2);
        else if (e->parent1 >= 0)
            snprintf(refs, sizeof(refs), "E%d", e->parent1);
        printf("%-17s  %-4d ", refs, e->weight);

        if (e->confirmed)
            printf("\033[1;32m✓ 已确认 (t=%d)\033[0m", e->confirmed_at);
        else
            printf("\033[90m待确认\033[0m");
        printf("\n");
    }
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    srand(42);

    printf("\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   DAG 类共识 —— Tangle 风格                                   ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");

    printf("模型:\n");
    printf("  %d 个节点, 每轮各创建一个事件\n", N_NODES);
    printf("  事件引用 1~2 个已有事件作为父节点 (DAG 的边)\n");
    printf("  权重 = 直接或间接引用该事件的后代总数\n");
    printf("  权重 ≥ %d → 事件被确认\n\n", CONFIRM_MIN);

    /* ------------------------------------------------------------
     * 1. 创世事件
     * ------------------------------------------------------------ */
    printf("\033[1;35m━━━ 1. 创世事件 ━━━\033[0m\n\n");
    for (int i = 0; i < N_NODES; i++) {
        int eid = create_event(i, -1, -1, true);
        printf("  E%d 由 N%d 创建 (创世)\n", eid, i);
    }
    g_tick = 1;

    /* ------------------------------------------------------------
     * 2. 逐轮创建
     * ------------------------------------------------------------ */
    printf("\n\033[1;35m━━━ 2. 逐轮创建事件 ━━━\033[0m\n");

    for (int round = 0; round < N_ROUNDS; round++) {
        printf("\n  \033[1;33m--- 第 %d 轮 (t=%d) ---\033[0m\n",
               round + 1, g_tick);

        /* 阶段 A: 每个节点基于当前本地视图创建事件, 暂不 gossip */
        int new_events[N_NODES];
        for (int node = 0; node < N_NODES; node++) {
            int tips[16];
            int n_tips = find_tips(node, tips, 16);

            int p1 = -1, p2 = -1;
            if (n_tips >= 1) p1 = tips[rand() % n_tips];
            if (n_tips >= 2) {
                int tries = 0;
                do {
                    p2 = tips[rand() % n_tips];
                    tries++;
                } while (p2 == p1 && tries < 20);
                if (p2 == p1) p2 = -1;
            }

            new_events[node] = create_event(node, p1, p2, false);
        }

        /* 阶段 B: gossip 所有本轮新事件 */
        for (int node = 0; node < N_NODES; node++)
            gossip_event(new_events[node]);

        /* 打印本轮创建的事件 */
        for (int node = 0; node < N_NODES; node++) {
            Event *e = &g_events[new_events[node]];
            printf("  N%d 创建 E%-2d  ← ", node, e->id);
            if (e->parent1 >= 0) printf("E%d", e->parent1);
            else                 printf("—");
            if (e->parent2 >= 0) printf(", E%d", e->parent2);
            printf("\n");
        }

        g_tick++;
        compute_weights();
        confirm_events();
    }

    /* ------------------------------------------------------------
     * 3. 最终 DAG
     * ------------------------------------------------------------ */
    printf("\n\033[1;35m━━━ 3. 最终 DAG ━━━\033[0m\n\n");
    print_events();

    /* ------------------------------------------------------------
     * 4. 拓扑序 = 共识顺序
     * ------------------------------------------------------------ */
    printf("\n\033[1;35m━━━ 4. 拓扑排序 (因果序 = 最终共识顺序) ━━━\033[0m\n\n");

    int order[MAX_EVENTS], n_order;
    topo_sort(order, &n_order);

    printf("    ");
    for (int i = 0; i < n_order; i++) {
        Event *e = &g_events[order[i]];
        if (e->confirmed)
            printf("\033[1;32mE%d\033[0m ", e->id);
        else
            printf("\033[90mE%d\033[0m ", e->id);
    }
    printf("\n\n    \033[90m绿色 = 已确认, 灰色 = 待确认\033[0m\n");

    /* ------------------------------------------------------------
     * 5. 统计
     * ------------------------------------------------------------ */
    int confirmed = 0;
    for (int i = 0; i < g_nevents; i++)
        if (g_events[i].confirmed) confirmed++;

    printf("\n\033[1;35m━━━ 5. 统计 ━━━\033[0m\n\n");
    printf("    总事件数:  %d\n", g_nevents);
    printf("    已确认:    %d / %d\n", confirmed, g_nevents);
    printf("    待确认:    %d\n", g_nevents - confirmed);

    /* ------------------------------------------------------------
     * 6. 总结
     * ------------------------------------------------------------ */
    printf("\n\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   DAG 共识的核心机制                                          ║\n");
    printf("╠═══════════════════════════════════════════════════════════════╣\n");
    printf("║                                                               ║\n");
    printf("║   和传统共识的根本区别:                                       ║\n");
    printf("║     · 没有\"区块\" —— 每个事件独立存在, 无需打包               ║\n");
    printf("║     · 没有 leader —— 任何节点平等, 谁都能创建事件            ║\n");
    printf("║     · 没有显式投票 —— \"引用\"本身就是投票                    ║\n");
    printf("║     · 图的结构即算法 —— 无需额外协调                          ║\n");
    printf("║                                                               ║\n");
    printf("║   权重 = 隐式投票:                                            ║\n");
    printf("║     事件 X 引用 Y 作为父节点 → X 批准了 Y                    ║\n");
    printf("║     X 又被 Z 引用 → Z 间接批准了 Y                           ║\n");
    printf("║     累积权重 = 所有直接和间接批准者数量                       ║\n");
    printf("║     → 权重越大, 越不可能被推翻                               ║\n");
    printf("║                                                               ║\n");
    printf("║   拓扑序 = 因果序 = 最终顺序:                                 ║\n");
    printf("║     如果 A 引用 B, 则 B 必在 A 之前                          ║\n");
    printf("║     拓扑排序给出唯一合法的全局顺序                            ║\n");
    printf("║     这就是交易\"最终性\"的数学定义                            ║\n");
    printf("║                                                               ║\n");
    printf("║   四种共识对比:                                               ║\n");
    printf("║                  Raft   PBFT   DAG    区块链                 ║\n");
    printf("║     拓扑          链     全连   任意      链                 ║\n");
    printf("║     Leader        有     有     无        矿工              ║\n");
    printf("║     共识轮数      多     3      无        概率               ║\n");
    printf("║     消息复杂度    O(n)   O(n²)  图结构    O(n)               ║\n");
    printf("║     吞吐          中     低     高        低                 ║\n");
    printf("║     最终性        立即   立即   延迟      概率               ║\n");
    printf("║     拜占庭        不支持 支持   支持      支持               ║\n");
    printf("║                                                               ║\n");
    printf("║   真实项目:                                                   ║\n");
    printf("║     · IOTA Tangle —— 每笔交易引用 2 笔之前的交易             ║\n");
    printf("║     · Hedera Hashgraph —— gossip + 虚拟投票                  ║\n");
    printf("║     · Nano —— 每账户一条链, 代表投票                         ║\n");
    printf("║     · Avalanche —— 反复采样邻居投票                          ║\n");
    printf("║     · Sui / Aptos —— 现代 DAG-BFT                            ║\n");
    printf("║                                                               ║\n");
    printf("║   DAG 共识的权衡:                                             ║\n");
    printf("║     + 高吞吐 (事件并行), 无需 leader, 天然抗审查             ║\n");
    printf("║     - 最终性非即时, 实现复杂                                 ║\n");
    printf("║     - 核心难点: 在没有全局时钟时, 让所有节点对                ║\n");
    printf("║                  \"确认状态\"最终达成一致                      ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}
