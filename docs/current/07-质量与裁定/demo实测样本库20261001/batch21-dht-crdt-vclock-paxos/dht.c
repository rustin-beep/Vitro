/* dht.c —— Kademlia 分布式哈希表
 *
 * 编译: gcc -Wall -O2 -std=c11 -o dht dht.c
 * 运行: ./dht
 *
 * Kademlia 的核心思想:
 *   1. XOR 距离: d(a,b) = a XOR b, 满足三角不等式, 且单向
 *   2. 路由表: k-bucket, 按"距离分层" —— 远的桶覆盖一半 ID 空间
 *   3. 迭代查找: 每次向"已知最近"的 k 个节点问, 逐步逼近目标
 *   4. 存储: key-value 存在与 key 的 XOR 距离最近的 k 个节点上
 *
 * 关键洞察: XOR 距离下, 每个节点对"自己附近"的 ID 空间了解很细,
 * 对"远方"了解很粗 —— 路由表的 log(N) 复杂度由此而来。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

#define ID_BITS   32
#define K         4           /* 每个 k-bucket 存 K 个节点 */
#define N_NODES   32          /* 网络里的节点总数 */
#define MAX_KEYS  16
#define ALPHA     3           /* 并发查询数, 演示里不用真正并发 */

/* ================================================================
 * 节点 ID
 * ================================================================ */
typedef uint32_t NodeID;

static uint32_t xor_dist(NodeID a, NodeID b) { return a ^ b; }

/* 返回 x 的二进制最高位位置 (1-based), x=0 返回 0 */
static int bit_length(uint32_t x) {
    int n = 0;
    while (x) { n++; x >>= 1; }
    return n;
}

/* ID 的十六进制字符串 */
static void id_str(NodeID id, char *buf, size_t n) {
    snprintf(buf, n, "%08x", id);
}

/* ================================================================
 * k-bucket
 *
 *   每个 bucket 存 K 个节点, 维护一个 last_seen 时间戳。
 *   桶满时: 如果桶里有失效节点就踢掉, 否则踢掉"最久没见"的。
 * ================================================================ */
typedef struct {
    NodeID   id;
    int      last_seen;
    bool     alive;
} Peer;

typedef struct {
    Peer     peers[K];
    int      n;
} KBucket;

/* ================================================================
 * 节点: 路由表 + 本地存储
 * ================================================================ */
typedef struct Node {
    NodeID   id;
    KBucket  buckets[ID_BITS];   /* bucket[i] 存距离在 [2^i, 2^(i+1)) 的节点 */

    /* 存储: 与 key 距离近的节点负责保存 */
    struct {
        NodeID key;
        int    value;
        bool   used;
    } store[MAX_KEYS];

    int      lookups;            /* 统计: 查找次数 */
    int      hops;               /* 统计: 累计 RPC 次数 */
} Node;

static Node     g_nodes[N_NODES];
static int      g_nnodes = 0;
static int      g_clock = 0;

/* 注册一个节点 */
static Node *node_new(void) {
    Node *n = &g_nodes[g_nnodes++];
    memset(n, 0, sizeof(*n));
    /* 用随机 ID, 冲突则重试 */
    do {
        n->id = ((uint32_t)rand() << 16) ^ (uint32_t)rand();
    } while (n->id == 0);
    return n;
}

/* ================================================================
 * bucket 索引: 两个节点之间, 距离的二进制位数决定放在哪个桶
 *
 *   例如 id=0x0, peer=0x5 (0101):
 *     距离 = 0101, 最高位在第 3 位 → bucket[2]
 * ================================================================ */
static int bucket_index(NodeID self, NodeID other) {
    uint32_t d = xor_dist(self, other);
    if (d == 0) return -1;
    return bit_length(d) - 1;
}

/* ================================================================
 * 更新路由表: 把 peer 塞进对应桶
 * ================================================================ */
static void rt_update(Node *self, NodeID peer_id, bool alive) {
    int idx = bucket_index(self->id, peer_id);
    if (idx < 0) return;

    KBucket *b = &self->buckets[idx];

    /* 已存在: 刷新时间戳 */
    for (int i = 0; i < b->n; i++) {
        if (b->peers[i].id == peer_id) {
            b->peers[i].last_seen = ++g_clock;
            b->peers[i].alive     = alive;
            return;
        }
    }

    /* 桶满: 踢掉一个 */
    if (b->n >= K) {
        int victim = -1;
        /* 优先踢失效节点 */
        for (int i = 0; i < b->n; i++) {
            if (!b->peers[i].alive) { victim = i; break; }
        }
        /* 否则踢最久没见的 */
        if (victim < 0) {
            int oldest = b->peers[0].last_seen;
            victim = 0;
            for (int i = 1; i < b->n; i++) {
                if (b->peers[i].last_seen < oldest) {
                    oldest = b->peers[i].last_seen;
                    victim = i;
                }
            }
        }
        b->peers[victim].id        = peer_id;
        b->peers[victim].last_seen = ++g_clock;
        b->peers[victim].alive     = alive;
        return;
    }

    b->peers[b->n].id        = peer_id;
    b->peers[b->n].last_seen = ++g_clock;
    b->peers[b->n].alive     = alive;
    b->n++;
}

/* ================================================================
 * 从路由表里挑"距离目标最近的 K 个"
 * ================================================================ */
typedef struct {
    NodeID ids[64];
    int    n;
} NodeList;

static void nl_add(NodeList *nl, NodeID id) {
    if (nl->n >= 64) return;
    for (int i = 0; i < nl->n; i++)
        if (nl->ids[i] == id) return;
    nl->ids[nl->n++] = id;
}

static void rt_closest(Node *self, NodeID target, int k, NodeList *out) {
    /* 收集所有已知节点 + 自己 */
    NodeID all[64];
    int n = 0;
    all[n++] = self->id;
    for (int b = 0; b < ID_BITS; b++)
        for (int i = 0; i < self->buckets[b].n; i++) {
            if (!self->buckets[b].peers[i].alive) continue;
            if (n < 64) all[n++] = self->buckets[b].peers[i].id;
        }

    /* 按 XOR 距离排序 (小 → 大) */
    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++)
            if (xor_dist(all[i], target) > xor_dist(all[j], target)) {
                NodeID t = all[i]; all[i] = all[j]; all[j] = t;
            }

    for (int i = 0; i < n && out->n < k; i++)
        nl_add(out, all[i]);
}

/* ================================================================
 * 网络: 按 ID 找节点
 * ================================================================ */
static Node *net_find(NodeID id) {
    for (int i = 0; i < g_nnodes; i++)
        if (g_nodes[i].id == id) return &g_nodes[i];
    return NULL;
}

/* ================================================================
 * RPC: FIND_NODE
 *
 *   请求方: 我知道哪些节点靠近 target
 *   应答方: 从自己路由表里挑 K 个最近的
 * ================================================================ */
static void rpc_find_node(Node *from, Node *to, NodeID target, NodeList *resp) {
    from->hops++;
    rt_update(from, to->id, true);
    rt_update(to, from->id, true);

    NodeList self_closest = {0};
    rt_closest(to, target, K, &self_closest);
    for (int i = 0; i < self_closest.n; i++)
        nl_add(resp, self_closest.ids[i]);
}

/* ================================================================
 * 迭代查找: 逐步逼近目标
 *
 *   1. 从自己最近的 K 个节点开始
 *   2. 对每个"没问过"的候选发起 FIND_NODE
 *   3. 把应答里的新节点合并到候选集
 *   4. 重复, 直到候选集里最近的 K 个都没变化
 * ================================================================ */
static int g_rpc_count = 0;

static void iterative_find(Node *self, NodeID target, NodeList *result) {
    NodeList shortlist = {0};
    NodeList queried   = {0};

    /* 初始候选: 自己已知最近的 */
    rt_closest(self, target, K, &shortlist);

    int last_best = -1;
    int rounds = 0;

    while (rounds++ < ID_BITS) {
        /* 按距离排序 */
        for (int i = 0; i < shortlist.n; i++)
            for (int j = i + 1; j < shortlist.n; j++)
                if (xor_dist(shortlist.ids[i], target) >
                    xor_dist(shortlist.ids[j], target)) {
                    NodeID t = shortlist.ids[i];
                    shortlist.ids[i] = shortlist.ids[j];
                    shortlist.ids[j] = t;
                }

        /* 选一个没问过的问 */
        NodeID ask = 0;
        bool found = false;
        for (int i = 0; i < shortlist.n; i++) {
            bool done = false;
            for (int j = 0; j < queried.n; j++)
                if (queried.ids[j] == shortlist.ids[i]) { done = true; break; }
            if (!done) { ask = shortlist.ids[i]; found = true; break; }
        }
        if (!found) break;

        nl_add(&queried, ask);
        Node *peer = net_find(ask);
        if (!peer) continue;

        NodeList resp = {0};
        rpc_find_node(self, peer, target, &resp);
        g_rpc_count++;

        for (int i = 0; i < resp.n; i++)
            nl_add(&shortlist, resp.ids[i]);

        /* 检查: 最近的一个有没有变 */
        int best = 0;
        for (int i = 1; i < shortlist.n; i++)
            if (xor_dist(shortlist.ids[i], target) <
                xor_dist(shortlist.ids[best], target))
                best = i;
        int best_dist = (int)xor_dist(shortlist.ids[best], target);

        if (best_dist == last_best) break;
        last_best = best_dist;
    }

    /* 输出最终 K 个最近的 */
    for (int i = 0; i < shortlist.n; i++)
        for (int j = i + 1; j < shortlist.n; j++)
            if (xor_dist(shortlist.ids[i], target) >
                xor_dist(shortlist.ids[j], target)) {
                NodeID t = shortlist.ids[i];
                shortlist.ids[i] = shortlist.ids[j];
                shortlist.ids[j] = t;
            }

    for (int i = 0; i < shortlist.n && i < K; i++)
        nl_add(result, shortlist.ids[i]);
}

/* ================================================================
 * 存储: 把 key-value 放到"距离 key 最近的 K 个节点"
 * ================================================================ */
static void dht_put(Node *self, NodeID key, int value) {
    NodeList closest = {0};
    iterative_find(self, key, &closest);

    printf("    PUT key=%08x value=%d → %d 个节点: ", key, value, closest.n);
    for (int i = 0; i < closest.n; i++) {
        printf("%08x ", closest.ids[i]);
        Node *n = net_find(closest.ids[i]);
        if (n) {
            /* 找一个空槽 */
            for (int j = 0; j < MAX_KEYS; j++) {
                if (!n->store[j].used) {
                    n->store[j].used  = true;
                    n->store[j].key   = key;
                    n->store[j].value = value;
                    break;
                }
            }
        }
    }
    printf("\n");
}

/* 查: 迭代查找, 遇到持有 key 的节点就返回 */
static bool dht_get(Node *self, NodeID key, int *out_value, NodeID *out_holder) {
    NodeList closest = {0};
    iterative_find(self, key, &closest);

    for (int i = 0; i < closest.n; i++) {
        Node *n = net_find(closest.ids[i]);
        if (!n) continue;
        for (int j = 0; j < MAX_KEYS; j++) {
            if (n->store[j].used && n->store[j].key == key) {
                *out_value  = n->store[j].value;
                *out_holder = n->id;
                return true;
            }
        }
    }
    return false;
}

/* ================================================================
 * 加入网络: 新节点通过一个 bootstrap 节点认识大家
 *
 *   1. 把自己的 ID 告诉 bootstrap
 *   2. bootstrap 返回它知道的最近 K 个
 *   3. 新节点再对这些节点做 FIND_NODE(self)
 *   4. 每个应答里都包含更多"离自己近"的节点
 * ================================================================ */
static void node_join(Node *self, Node *bootstrap) {
    printf("    %08x 加入网络 (bootstrap=%08x)\n", self->id, bootstrap->id);

    /* 直接拿 bootstrap 的整个路由表填自己 (简化) */
    rt_update(self, bootstrap->id, true);
    for (int b = 0; b < ID_BITS; b++)
        for (int i = 0; i < bootstrap->buckets[b].n; i++)
            rt_update(self, bootstrap->buckets[b].peers[i].id, true);

    /* 再对每个已知节点发一次 FIND_NODE(self) */
    NodeList candidates = {0};
    rt_closest(self, self->id, 8, &candidates);

    for (int i = 0; i < candidates.n; i++) {
        Node *peer = net_find(candidates.ids[i]);
        if (!peer) continue;
        NodeList resp = {0};
        rpc_find_node(self, peer, self->id, &resp);
        for (int j = 0; j < resp.n; j++)
            rt_update(self, resp.ids[j], true);
    }

    /* 让其他节点也知道新来者 */
    for (int i = 0; i < candidates.n; i++) {
        Node *peer = net_find(candidates.ids[i]);
        if (peer) rt_update(peer, self->id, true);
    }
}

/* ================================================================
 * 打印
 * ================================================================ */
static void print_routing_table(Node *n) {
    printf("    节点 %08x 的路由表:\n", n->id);
    int total = 0;
    for (int b = ID_BITS - 1; b >= 0; b--) {
        if (n->buckets[b].n == 0) continue;
        printf("      bucket[%2d] (距离 [2^%d, 2^%d)): ",
               b, b, b + 1);
        for (int i = 0; i < n->buckets[b].n; i++) {
            printf("%08x ", n->buckets[b].peers[i].id);
        }
        printf("\n");
        total += n->buckets[b].n;
    }
    printf("      (共 %d 个已知节点)\n", total);
}

static void print_store(Node *n) {
    printf("    节点 %08x 的存储: ", n->id);
    int cnt = 0;
    for (int i = 0; i < MAX_KEYS; i++) {
        if (n->store[i].used) {
            printf("{%08x→%d} ", n->store[i].key, n->store[i].value);
            cnt++;
        }
    }
    if (cnt == 0) printf("(空)");
    printf("\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    srand(42);

    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════════╗\n");
    printf("║   Kademlia 分布式哈希表 (DHT)                            ║\n");
    printf("╚══════════════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");

    printf("配置:\n");
    printf("  ID 位数:    %d\n", ID_BITS);
    printf("  k-bucket:   K = %d\n", K);
    printf("  节点总数:   %d\n\n", N_NODES);

    /* ============================================================
     * 1. XOR 距离的性质
     * ============================================================ */
    printf("\033[1;35m━━━ 1. XOR 距离的性质 ━━━\033[0m\n\n");

    NodeID a = 0x00000000, b = 0x0000000f, c = 0x000000ff;
    printf("  a=%08x  b=%08x  c=%08x\n", a, b, c);
    printf("  d(a,b) = %08x  (%d)\n", xor_dist(a, b), xor_dist(a, b));
    printf("  d(a,c) = %08x  (%d)\n", xor_dist(a, c), xor_dist(a, c));
    printf("  d(b,c) = %08x  (%d)\n\n", xor_dist(b, c), xor_dist(b, c));

    printf("  \033[1;33m性质:\033[0m\n");
    printf("    · d(x,x) = 0\n");
    printf("    · d(x,y) > 0 (x≠y)\n");
    printf("    · d(x,y) = d(y,x)  (对称)\n");
    printf("    · d(x,y) + d(y,z) ≥ d(x,z)  (三角不等式)\n");
    printf("    · \033[1;32m单向性\033[0m: 给定 x 和距离 d, 有唯一的 y 使 d(x,y)=d\n");

    /* ============================================================
     * 2. k-bucket 结构
     * ============================================================ */
    printf("\n\033[1;35m━━━ 2. k-bucket: 按距离分层 ━━━\033[0m\n\n");

    NodeID self_id = 0x00000000;
    printf("  以 id=%08x 为参考点, 看 ID 空间怎么划分:\n\n", self_id);
    printf("    bucket[0]: 距离 1          → 只看最低 1 位\n");
    printf("    bucket[1]: 距离 2-3        → 只看最低 2 位\n");
    printf("    bucket[2]: 距离 4-7        → 只看最低 3 位\n");
    printf("    bucket[3]: 距离 8-15\n");
    printf("    ...\n");
    printf("    bucket[31]: 距离 2^31 到 2^32-1  → 完全相反的另一半空间\n\n");

    printf("  \033[1;33m关键性质:\033[0m\n");
    printf("    · 每个 bucket 覆盖的 ID 空间 = 所有更近 bucket 之和\n");
    printf("    · 最近一半节点在 bucket[31] (远), 最近的 1 个在 bucket[0]\n");
    printf("    · 结果: 路由表只用 O(log N) 条记录, 就能定位全网任何节点\n");

    /* ============================================================
     * 3. 建网络
     * ============================================================ */
    printf("\n\033[1;35m━━━ 3. 构建网络 ━━━\033[0m\n\n");

    /* 先建几个初始节点 */
    Node *first = node_new();
    printf("  第 1 个节点: %08x\n", first->id);

    for (int i = 1; i < 5; i++) {
        Node *n = node_new();
        node_join(n, first);
        /* 让 first 也认识它 */
        rt_update(first, n->id, true);
        for (int k = 0; k < g_nnodes - 1; k++)
            if (&g_nodes[k] != n)
                rt_update(n, g_nodes[k].id, true);
    }

    printf("\n  再让 %d 个节点陆续加入:\n", N_NODES - 5);
    for (int i = 5; i < N_NODES; i++) {
        Node *n = node_new();
        Node *boot = &g_nodes[rand() % i];
        node_join(n, boot);
        if (i % 5 == 0) printf("    ... 已加入 %d 个节点\n", i + 1);
    }
    printf("    完成: 共 %d 个节点\n", g_nnodes);

    /* 让所有节点的路由表都更新一遍 (模拟长期的持续通信) */
    for (int round = 0; round < 3; round++) {
        for (int i = 0; i < g_nnodes; i++) {
            for (int j = 0; j < g_nnodes; j++) {
                if (i == j) continue;
                rt_update(&g_nodes[i], g_nodes[j].id, true);
            }
        }
    }

    printf("\n  看一个节点的路由表结构:\n\n");
    print_routing_table(first);

    /* ============================================================
     * 4. 迭代查找
     * ============================================================ */
    printf("\n\033[1;35m━━━ 4. 迭代查找 ━━━\033[0m\n\n");

    NodeID target = 0xdeadbeef;
    printf("  从节点 %08x 找 target=%08x:\n\n", first->id, target);

    NodeList result = {0};
    g_rpc_count = 0;
    iterative_find(first, target, &result);

    printf("  找到 %d 个最接近的节点:\n", result.n);
    for (int i = 0; i < result.n; i++) {
        printf("    %08x  距离 = %08x\n",
               result.ids[i], xor_dist(result.ids[i], target));
    }
    printf("  RPC 次数: %d (节点数 %d, log2(%d)≈%.1f)\n",
           g_rpc_count, g_nnodes, g_nnodes,
           bit_length((uint32_t)g_nnodes - 1) * 1.0);

    /* ============================================================
     * 5. 存储与检索
     * ============================================================ */
    printf("\n\033[1;35m━━━ 5. PUT / GET ━━━\033[0m\n\n");

    NodeID keys[] = { 0x11111111, 0x22222222, 0xdeadbeef };
    int    values[] = { 42, 100, 7 };

    printf("  PUT 三个 key-value:\n");
    for (int i = 0; i < 3; i++)
        dht_put(first, keys[i], values[i]);

    printf("\n  各节点的存储:\n");
    for (int i = 0; i < 4; i++)
        print_store(&g_nodes[i]);

    printf("\n  GET 三个 key:\n");
    for (int i = 0; i < 3; i++) {
        int v;
        NodeID holder;
        if (dht_get(first, keys[i], &v, &holder)) {
            printf("    GET key=%08x → value=%d  (由 %08x 提供)\n",
                   keys[i], v, holder);
        } else {
            printf("    GET key=%08x → \033[1;31mNOT FOUND\033[0m\n", keys[i]);
        }
    }

    /* ============================================================
     * 6. 节点离开
     * ============================================================ */
    printf("\n\033[1;35m━━━ 6. 节点离开 ━━━\033[0m\n\n");

    NodeID dying = g_nodes[3].id;
    printf("  模拟 %08x 离开网络\n", dying);
    for (int i = 0; i < g_nnodes; i++) {
        if (g_nodes[i].id == dying) continue;
        /* 把它在路由表里标记为失效 */
        for (int b = 0; b < ID_BITS; b++) {
            for (int j = 0; j < g_nodes[i].buckets[b].n; j++) {
                if (g_nodes[i].buckets[b].peers[j].id == dying)
                    g_nodes[i].buckets[b].peers[j].alive = false;
            }
        }
    }

    /* 再查 key: 应该由其他副本提供 */
    printf("\n  重新 GET 三个 key (副本容错):\n");
    for (int i = 0; i < 3; i++) {
        int v;
        NodeID holder;
        if (dht_get(first, keys[i], &v, &holder)) {
            printf("    GET key=%08x → value=%d  (由 %08x 提供)\n",
                   keys[i], v, holder);
        } else {
            printf("    GET key=%08x → \033[1;31mNOT FOUND\033[0m\n", keys[i]);
        }
    }

    /* ============================================================
     * 总结
     * ============================================================ */
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════════╗\n");
    printf("║   Kademlia 的三个核心设计                                 ║\n");
    printf("╠══════════════════════════════════════════════════════════╣\n");
    printf("║                                                          ║\n");
    printf("║   1. XOR 距离                                             ║\n");
    printf("║      对称、满足三角不等式, 而且对每个点有唯一的\"对侧点\"  ║\n");
    printf("║      —— 这让路由表可以按二进制前缀分层                    ║\n");
    printf("║                                                          ║\n");
    printf("║   2. k-bucket 路由表                                       ║\n");
    printf("║      每个 bucket 覆盖距离 [2^i, 2^(i+1)) 的节点            ║\n");
    printf("║      —— 远的桶覆盖半个空间, 近的桶覆盖一小块              ║\n");
    printf("║      路由表大小 O(log N), 一次查找 O(log N) 跳            ║\n");
    printf("║                                                          ║\n");
    printf("║   3. 迭代查找 + 并行 α 查询                                ║\n");
    printf("║      每一步都朝目标靠近一点, 且每步能排除一半空间         ║\n");
    printf("║      —— 32 位 ID, 最多 32 跳就找到                        ║\n");
    printf("║                                                          ║\n");
    printf("║   真实的 Kademlia 用 160 位 ID (SHA-1):                   ║\n");
    printf("║     网络规模 2^160, 路由表 ~160 项, 查找 ~log2(N) 跳     ║\n");
    printf("║                                                          ║\n");
    printf("║   应用:                                                   ║\n");
    printf("║     · BitTorrent DHT — 无 tracker 的 peer 发现            ║\n");
    printf("║     · IPFS — 内容寻址 + DHT 路由                          ║\n");
    printf("║     · Ethereum — 节点发现协议 (discv4/discv5)             ║\n");
    printf("║     · Kad 网络 — 电驴的文件索引                           ║\n");
    printf("╚══════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}