#include <stdio.h>
#include <stdlib.h>

/* ---------- 树节点 ---------- */
typedef struct Node {
    int          key;
    struct Node *left;
    struct Node *right;
} Node;

/* ---------- 创建节点 ---------- */
static Node *new_node(int key)
{
    Node *n = (Node *)malloc(sizeof(Node));
    if (!n) {
        perror("malloc");
        exit(EXIT_FAILURE);
    }
    n->key   = key;
    n->left  = NULL;
    n->right = NULL;
    return n;
}

/* ---------- 插入（递归） ---------- */
static Node *insert(Node *root, int key)
{
    if (root == NULL)
        return new_node(key);

    if (key < root->key)
        root->left  = insert(root->left,  key);
    else if (key > root->key)
        root->right = insert(root->right, key);
    /* key == root->key 时不做任何事，保持集合唯一 */

    return root;
}

/* ---------- 查找（递归） ---------- */
static Node *search(Node *root, int key)
{
    if (root == NULL || root->key == key)
        return root;
    if (key < root->key)
        return search(root->left,  key);
    return search(root->right, key);
}

/* ---------- 找最小节点（用于删除的后继） ---------- */
static Node *find_min(Node *root)
{
    while (root != NULL && root->left != NULL)
        root = root->left;
    return root;
}

/* ---------- 删除（递归，三种情况） ---------- */
static Node *delete_node(Node *root, int key)
{
    if (root == NULL)
        return NULL;

    if (key < root->key) {
        root->left  = delete_node(root->left,  key);
    } else if (key > root->key) {
        root->right = delete_node(root->right, key);
    } else {
        /* 找到目标节点 */

        /* 情况 1 & 2：至多一个孩子 */
        if (root->left == NULL) {
            Node *tmp = root->right;
            free(root);
            return tmp;
        }
        if (root->right == NULL) {
            Node *tmp = root->left;
            free(root);
            return tmp;
        }

        /* 情况 3：两个孩子 —— 用右子树最小值替换 */
        Node *succ = find_min(root->right);
        root->key   = succ->key;
        root->right = delete_node(root->right, succ->key);
    }
    return root;
}

/* ---------- 中序遍历（升序） ---------- */
static void inorder(const Node *root)
{
    if (root == NULL) return;
    inorder(root->left);
    printf("%d ", root->key);
    inorder(root->right);
}

/* ---------- 后序释放 ---------- */
static void free_tree(Node *root)
{
    if (root == NULL) return;
    free_tree(root->left);
    free_tree(root->right);
    free(root);
}

/* ---------- 树高 ---------- */
static int height(const Node *root)
{
    if (root == NULL) return 0;
    int lh = height(root->left);
    int rh = height(root->right);
    return 1 + (lh > rh ? lh : rh);
}

/* ---------- 树形打印（逆中序 + 缩进） ---------- */
static void print_tree(const Node *root, int depth)
{
    if (root == NULL) return;

    print_tree(root->right, depth + 1);

    for (int i = 0; i < depth; i++)
        printf("    ");
    printf("%d\n", root->key);

    print_tree(root->left, depth + 1);
}

/* ---------- 演示 ---------- */
int main(void)
{
    Node *root = NULL;
    int  keys[] = { 50, 30, 70, 20, 40, 60, 80, 35, 45, 65 };

    for (int i = 0; i < (int)(sizeof(keys)/sizeof(keys[0])); i++)
        root = insert(root, keys[i]);

    printf(">>> 树形结构（逆时针旋转 90° 看）\n");
    print_tree(root, 0);

    printf("\n>>> 中序遍历（应为升序）\n");
    inorder(root);
    printf("\n");

    printf("\n>>> 树高: %d\n", height(root));

    printf("\n>>> 查找 45: ");
    Node *s = search(root, 45);
    printf(s ? "找到\n" : "未找到\n");

    printf(">>> 查找 99: ");
    s = search(root, 99);
    printf(s ? "找到\n" : "未找到\n");

    printf("\n>>> 删除叶子节点 20\n");
    root = delete_node(root, 20);
    print_tree(root, 0);

    printf("\n>>> 删除只有一个孩子的节点 30\n");
    root = delete_node(root, 30);
    print_tree(root, 0);

    printf("\n>>> 删除有两个孩子的节点 50（根）\n");
    root = delete_node(root, 50);
    print_tree(root, 0);

    printf("\n>>> 删除后中序遍历\n");
    inorder(root);
    printf("\n");

    free_tree(root);
    return 0;
}
