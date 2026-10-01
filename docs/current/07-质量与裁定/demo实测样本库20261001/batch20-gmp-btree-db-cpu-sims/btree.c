/* btree.c —— B 树：插入 / 删除 / 查找 / 遍历
 *
 * 编译: gcc -Wall -O2 -std=c11 -o btree btree.c
 * 运行: ./btree
 *
 * 阶数 ORDER = 5:
 *   每个节点最多 4 个 key, 5 个孩子
 *   每个节点最少 2 个 key (根节点除外)
 *
 * B 树与 AVL 的区别:
 *   AVL  每个节点 1 个 key, 2 个孩子, 高度 O(log n)
 *   B 树 每个节点多个 key, 多个孩子, 高度更低
 *         磁盘每次读一页, 一页装一个节点 —— 减少 I/O 次数
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define ORDER 5                    /* 阶数: 每个节点最多 ORDER 个孩子 */
#define MAX_KEYS (ORDER - 1)       /* 最多 4 个 key */
#define MIN_KEYS ((ORDER + 1) / 2 - 1)  /* 最少 2 个 key */
#define MAX_CHILD ORDER            /* 最多 5 个孩子 */

typedef struct Node {
    int   keys[MAX_KEYS];
    int   nkeys;
    struct Node *child[MAX_CHILD];
    bool  leaf;
} Node;

static Node *g_root = NULL;

/* ================================================================
 * 创建节点
 * ================================================================ */
static Node *node_new(bool leaf) {
    Node *n = (Node *)calloc(1, sizeof(Node));
    n->leaf  = leaf;
    n->nkeys = 0;
    return n;
}

/* ================================================================
 * 查找
 * ================================================================ */
static Node *find_node(Node *n, int key, int *idx) {
    while (n) {
        int i = 0;
        while (i < n->nkeys && key > n->keys[i]) i++;
        if (i < n->nkeys && key == n->keys[i]) {
            if (idx) *idx = i;
            return n;
        }
        if (n->leaf) return NULL;
        n = n->child[i];
    }
    return NULL;
}

static bool btree_search(int key) {
    return find_node(g_root, key, NULL) != NULL;
}

/* ================================================================
 * 分裂: 节点 full 时, 中间 key 上升给 parent
 *
 *   full 节点: [k0 k1 k2 k3]
 *              /  |  |  |  \
 *   分裂后:
 *     中间 k2 上提
 *     左: [k0 k1]     右: [k3]
 * ================================================================ */
static void split_child(Node *parent, int i) {
    Node *full = parent->child[i];
    int   mid  = full->nkeys / 2;
    int   mid_key = full->keys[mid];

    /* 新右节点 */
    Node *right = node_new(full->leaf);
    right->nkeys = full->nkeys - mid - 1;
    for (int j = 0; j < right->nkeys; j++)
        right->keys[j] = full->keys[mid + 1 + j];

    if (!full->leaf) {
        for (int j = 0; j <= right->nkeys; j++)
            right->child[j] = full->child[mid + 1 + j];
    }

    full->nkeys = mid;

    /* parent 腾出位置 */
    for (int j = parent->nkeys; j > i; j--) {
        parent->keys[j]  = parent->keys[j - 1];
        parent->child[j + 1] = parent->child[j];
    }
    parent->keys[i]      = mid_key;
    parent->child[i + 1] = right;
    parent->nkeys++;
}

/* ================================================================
 * 插入
 * ================================================================ */
static void insert_nonfull(Node *n, int key) {
    int i = n->nkeys - 1;

    if (n->leaf) {
        /* 叶子直接插 */
        while (i >= 0 && key < n->keys[i]) {
            n->keys[i + 1] = n->keys[i];
            i--;
        }
        n->keys[i + 1] = key;
        n->nkeys++;
    } else {
        /* 内部节点: 找到该走的子树 */
        while (i >= 0 && key < n->keys[i]) i--;
        i++;

        /* 若子节点已满, 先分裂 */
        if (n->child[i]->nkeys == MAX_KEYS) {
            split_child(n, i);
            if (key > n->keys[i]) i++;
        }
        insert_nonfull(n->child[i], key);
    }
}

static void btree_insert(int key) {
    if (!g_root) {
        g_root = node_new(true);
        g_root->keys[0] = key;
        g_root->nkeys   = 1;
        return;
    }

    if (g_root->nkeys == MAX_KEYS) {
        /* 根满了: 建一个新根, 把老根分裂下去 */
        Node *new_root = node_new(false);
        new_root->child[0] = g_root;
        split_child(new_root, 0);
        g_root = new_root;
    }
    insert_nonfull(g_root, key);
}

/* ================================================================
 * 删除
 *
 *   三种情况:
 *     1. key 在叶子里 → 直接删
 *     2. key 在内部节点 → 用前驱或后继替换
 *     3. 往子树走之前, 先保证子节点至少有 MIN_KEYS+1 个 key
 *        (否则删完会低于下界, 需要借位或合并)
 * ================================================================ */

/* 从前驱子树取最大 key */
static int get_predecessor(Node *n, int idx) {
    Node *cur = n->child[idx];
    while (!cur->leaf) cur = cur->child[cur->nkeys];
    return cur->keys[cur->nkeys - 1];
}

/* 从后继子树取最小 key */
static int get_successor(Node *n, int idx) {
    Node *cur = n->child[idx + 1];
    while (!cur->leaf) cur = cur->child[0];
    return cur->keys[0];
}

/* 从左兄弟借一个 key */
static void borrow_from_left(Node *parent, int idx) {
    Node *child = parent->child[idx];
    Node *left  = parent->child[idx - 1];

    /* child 整体右移一位 */
    for (int i = child->nkeys - 1; i >= 0; i--)
        child->keys[i + 1] = child->keys[i];
    if (!child->leaf)
        for (int i = child->nkeys; i >= 0; i--)
            child->child[i + 1] = child->child[i];

    child->keys[0] = parent->keys[idx - 1];
    if (!child->leaf)
        child->child[0] = left->child[left->nkeys];

    parent->keys[idx - 1] = left->keys[left->nkeys - 1];
    child->nkeys++;
    left->nkeys--;
}

/* 从右兄弟借一个 key */
static void borrow_from_right(Node *parent, int idx) {
    Node *child = parent->child[idx];
    Node *right = parent->child[idx + 1];

    child->keys[child->nkeys] = parent->keys[idx];
    if (!child->leaf)
        child->child[child->nkeys + 1] = right->child[0];

    parent->keys[idx] = right->keys[0];

    for (int i = 0; i < right->nkeys - 1; i++)
        right->keys[i] = right->keys[i + 1];
    if (!right->leaf)
        for (int i = 0; i < right->nkeys; i++)
            right->child[i] = right->child[i + 1];

    child->nkeys++;
    right->nkeys--;
}

/* 合并 child[idx] 和 child[idx+1], 中间 key 拉下来 */
static void merge_children(Node *parent, int idx) {
    Node *left  = parent->child[idx];
    Node *right = parent->child[idx + 1];

    left->keys[left->nkeys] = parent->keys[idx];
    left->nkeys++;

    for (int i = 0; i < right->nkeys; i++)
        left->keys[left->nkeys + i] = right->keys[i];
    if (!left->leaf)
        for (int i = 0; i <= right->nkeys; i++)
            left->child[left->nkeys + i] = right->child[i];

    left->nkeys += right->nkeys;

    for (int i = idx + 1; i < parent->nkeys; i++) {
        parent->keys[i - 1]  = parent->keys[i];
        parent->child[i]     = parent->child[i + 1];
    }
    parent->nkeys--;

    free(right);
}

/* 确保 child[idx] 至少有 MIN_KEYS+1 个 key */
static void fill_child(Node *parent, int idx) {
    Node *child = parent->child[idx];

    if (idx > 0 && parent->child[idx - 1]->nkeys > MIN_KEYS) {
        borrow_from_left(parent, idx);
    } else if (idx < parent->nkeys &&
               parent->child[idx + 1]->nkeys > MIN_KEYS) {
        borrow_from_right(parent, idx);
    } else {
        if (idx < parent->nkeys) merge_children(parent, idx);
        else                     merge_children(parent, idx - 1);
    }
}

static void delete_from(Node *n, int key) {
    int idx = 0;
    while (idx < n->nkeys && key > n->keys[idx]) idx++;

    if (idx < n->nkeys && n->keys[idx] == key) {
        /* --- 情况 1: 在叶子里, 直接删 --- */
        if (n->leaf) {
            for (int i = idx + 1; i < n->nkeys; i++)
                n->keys[i - 1] = n->keys[i];
            n->nkeys--;
            return;
        }

        /* --- 情况 2: 在内部节点 --- */
        Node *left  = n->child[idx];
        Node *right = n->child[idx + 1];

        if (left->nkeys > MIN_KEYS) {
            /* 用前驱替换 */
            int pred = get_predecessor(n, idx);
            n->keys[idx] = pred;
            delete_from(left, pred);
        } else if (right->nkeys > MIN_KEYS) {
            /* 用后继替换 */
            int succ = get_successor(n, idx);
            n->keys[idx] = succ;
            delete_from(right, succ);
        } else {
            /* 两边都是最小, 合并后从新节点里删 */
            merge_children(n, idx);
            delete_from(left, key);
        }
    } else {
        /* --- 情况 3: 往子树走 --- */
        if (n->leaf) return;   /* 没找到 */

        bool last_child = (idx == n->nkeys);

        /* 保证子节点不会在删除后低于下界 */
        if (n->child[idx]->nkeys == MIN_KEYS)
            fill_child(n, idx);

        /* fill_child 可能合并过, idx 需要调整 */
        if (last_child && idx > n->nkeys)
            delete_from(n->child[idx - 1], key);
        else
            delete_from(n->child[idx], key);
    }
}

static void btree_delete(int key) {
    if (!g_root) return;
    delete_from(g_root, key);

    /* 根空了: 降级 */
    if (g_root->nkeys == 0) {
        Node *old = g_root;
        if (g_root->leaf) g_root = NULL;
        else              g_root = g_root->child[0];
        free(old);
    }
}

/* ================================================================
 * 遍历
 * ================================================================ */
static void inorder(Node *n) {
    if (!n) return;
    for (int i = 0; i < n->nkeys; i++) {
        if (!n->leaf) inorder(n->child[i]);
        printf("%d ", n->keys[i]);
    }
    if (!n->leaf) inorder(n->child[n->nkeys]);
}

/* ================================================================
 * 树形打印
 * ================================================================ */
static void print_tree_rec(Node *n, int depth, const char *prefix, bool last) {
    if (!n) return;

    for (int i = 0; i < depth - 1; i++) printf("    ");
    if (depth > 0) printf("%s", last ? "└── " : "├── ");

    printf("[");
    for (int i = 0; i < n->nkeys; i++) {
        if (i) printf(" ");
        if (n->nkeys < MIN_KEYS && n != g_root)
            printf("\033[1;31m%d\033[0m", n->keys[i]);
        else
            printf("\033[1;32m%d\033[0m", n->keys[i]);
    }
    printf("]");
    if (n->leaf) printf(" \033[90m←leaf\033[0m");
    printf("\n");

    if (!n->leaf) {
        for (int i = 0; i <= n->nkeys; i++)
            print_tree_rec(n->child[i], depth + 1, prefix,
                           i == n->nkeys);
    }
}

static void print_tree(void) {
    if (!g_root) { printf("    (空)\n"); return; }
    /* 根单独打印 */
    printf("    [");
    for (int i = 0; i < g_root->nkeys; i++) {
        if (i) printf(" ");
        printf("\033[1;33m%d\033[0m", g_root->keys[i]);
    }
    printf("]\n");

    if (!g_root->leaf) {
        for (int i = 0; i <= g_root->nkeys; i++)
            print_tree_rec(g_root->child[i], 1, "", i == g_root->nkeys);
    }
}

static void count_nodes(Node *n, int *nodes, int *keys, int depth,
                        int *max_depth) {
    if (!n) return;
    (*nodes)++;
    (*keys) += n->nkeys;
    if (depth > *max_depth) *max_depth = depth;
    if (!n->leaf)
        for (int i = 0; i <= n->nkeys; i++)
            count_nodes(n->child[i], nodes, keys, depth + 1, max_depth);
}

/* ================================================================
 * 演示
 * ================================================================ */
static void section(const char *title) {
    printf("\n\033[1;35m━━━ %s ━━━\033[0m\n", title);
}

int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   B 树：插入 / 删除 / 查找 / 遍历                    ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");
    printf("阶数 ORDER = %d\n", ORDER);
    printf("  每节点最多 %d 个 key, %d 个孩子\n", MAX_KEYS, MAX_CHILD);
    printf("  每节点最少 %d 个 key (根节点除外)\n", MIN_KEYS);

    /* ---- 插入 ---- */
    section("插入 1 .. 10");
    printf("  依次插入: ");
    for (int i = 1; i <= 10; i++) {
        printf("%d ", i);
        btree_insert(i);
    }
    printf("\n");

    printf("\n  树形:\n");
    print_tree();

    printf("\n  中序遍历: ");
    inorder(g_root);
    printf("\n");

    /* ---- 中间插入更多 ---- */
    section("再插入 15, 20, 25, 30, 40, 50");
    int more[] = {15, 20, 25, 30, 40, 50};
    for (int i = 0; i < 6; i++) btree_insert(more[i]);
    printf("  树形:\n");
    print_tree();

    printf("\n  中序遍历: ");
    inorder(g_root);
    printf("\n");

    int nodes = 0, keys = 0, max_depth = 0;
    count_nodes(g_root, &nodes, &keys, 1, &max_depth);
    printf("\n  统计: %d 个节点, %d 个 key, 高度 %d\n",
           nodes, keys, max_depth);

    /* ---- 查找 ---- */
    section("查找");
    int probes[] = {7, 20, 42, 1, 100};
    for (int i = 0; i < 5; i++) {
        printf("  查找 %-3d: ", probes[i]);
        Node *n = find_node(g_root, probes[i], NULL);
        if (n) printf("\033[1;32m✓ 找到\033[0m\n");
        else   printf("\033[1;31m✗ 不存在\033[0m\n");
    }

    /* ---- 删除 ---- */
    section("删除 1, 2, 3（叶子节点）");
    btree_delete(1);
    btree_delete(2);
    btree_delete(3);
    print_tree();
    printf("\n  中序: ");
    inorder(g_root);
    printf("\n");

    section("删除 15（内部节点，会用前驱或后继替换）");
    btree_delete(15);
    print_tree();
    printf("\n  中序: ");
    inorder(g_root);
    printf("\n");

    section("删除 20, 25, 30");
    btree_delete(20);
    btree_delete(25);
    btree_delete(30);
    print_tree();
    printf("\n  中序: ");
    inorder(g_root);
    printf("\n");

    section("删除 40, 50");
    btree_delete(40);
    btree_delete(50);
    print_tree();
    printf("\n  中序: ");
    inorder(g_root);
    printf("\n");

    section("继续删到空");
    int rest[] = {4, 5, 6, 7, 8, 9, 10};
    for (int i = 0; i < 7; i++) {
        printf("  删除 %d\n", rest[i]);
        btree_delete(rest[i]);
    }
    print_tree();
    printf("\n  根是否为空: %s\n", g_root ? "否" : "是");

    /* ---- 对比 ---- */
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   和 BST / AVL 的对比                                ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║             每个节点   孩子数   高度(1万key)  磁盘IO ║\n");
    printf("║   ────────  ────────  ──────  ───────────  ────────  ║\n");
    printf("║   BST       1        2       O(n) 最坏     很多      ║\n");
    printf("║   AVL       1        2       ~14           很多      ║\n");
    printf("║   B 树(5)   最多 4   最多 5   ~6           少        ║\n");
    printf("║   B 树(100) 最多 99  最多 100 ~2           极少      ║\n");
    printf("║                                                      ║\n");
    printf("║   B 树的杀手锏: 一个节点就是一个磁盘页。             ║\n");
    printf("║   高度低 → 查一次只需访问极少页 → IO 少 → 快得多。  ║\n");
    printf("║   这就是 MySQL、PostgreSQL、SQLite、文件系统         ║\n");
    printf("║   全都用 B 树/B+ 树做索引的原因。                    ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}
