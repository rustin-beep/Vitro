#include <stdio.h>
#include <string.h>

struct TreeNode {
    int val;
    struct TreeNode *left;
    struct TreeNode *right;
};

char g_result[100][128];
int g_count;

void build_paths(struct TreeNode* root, char* path) {
    if (root == NULL) return;
    char cur[128];
    int v = root->val;
    if (strlen(path) == 0) {
        sprintf(cur, "%d", v);
    } else {
        sprintf(cur, "%s->%d", path, v);
    }
    if (root->left == NULL && root->right == NULL) {
        strcpy(g_result[g_count], cur);
        g_count++;
        return;
    }
    build_paths(root->left, cur);
    build_paths(root->right, cur);
}

int main(void) {
    // [3,9,20,null,null,15,7]
    struct TreeNode n1[5];
    n1[0].val = 3; n1[0].left = &n1[1]; n1[0].right = &n1[2];
    n1[1].val = 9; n1[1].left = NULL; n1[1].right = NULL;
    n1[2].val = 20; n1[2].left = &n1[3]; n1[2].right = &n1[4];
    n1[3].val = 15; n1[3].left = NULL; n1[3].right = NULL;
    n1[4].val = 7; n1[4].left = NULL; n1[4].right = NULL;
    g_count = 0;
    build_paths(&n1[0], "");
    for (int i = 0; i < g_count; i++) printf("%s\n", g_result[i]);

    // [1]
    struct TreeNode n2;
    n2.val = 1; n2.left = NULL; n2.right = NULL;
    g_count = 0;
    build_paths(&n2, "");
    for (int i = 0; i < g_count; i++) printf("%s\n", g_result[i]);
    return 0;
}
