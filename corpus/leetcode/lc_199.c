#include <stdio.h>
#include <stdlib.h>

struct TreeNode {
    int val;
    struct TreeNode *left;
    struct TreeNode *right;
};

struct TreeNode* build(int* arr, int n, int idx) {
    if (idx >= n || arr[idx] == -1) return NULL;
    struct TreeNode* node = (struct TreeNode*)malloc(sizeof(struct TreeNode));
    node->val = arr[idx];
    node->left = build(arr, n, idx * 2 + 1);
    node->right = build(arr, n, idx * 2 + 2);
    return node;
}

void freeTree(struct TreeNode* root) {
    if (root == NULL) return;
    freeTree(root->left);
    freeTree(root->right);
    free(root);
}

int* rightSideView(struct TreeNode* root, int* returnSize) {
    int* res = (int*)malloc(100 * sizeof(int));
    *returnSize = 0;
    if (root == NULL) return res;
    struct TreeNode* q[100];
    int head = 0, tail = 0;
    q[tail++] = root;
    while (head < tail) {
        int level_size = tail - head;
        struct TreeNode* last = NULL;
        for (int i = 0; i < level_size; i++) {
            struct TreeNode* node = q[head++];
            last = node;
            if (node->left) q[tail++] = node->left;
            if (node->right) q[tail++] = node->right;
        }
        int idx = *returnSize;
        res[idx] = last->val;
        *returnSize = *returnSize + 1;
    }
    return res;
}

int main(void) {
    int a1[] = {1,2,3,-1,5,-1,4};
    int s1 = 0;
    struct TreeNode* r1 = build(a1, 7, 0);
    int* v1 = rightSideView(r1, &s1);
    for (int i = 0; i < s1; i++) printf("%d ", v1[i]);
    printf("\n");
    free(v1);
    freeTree(r1);

    int a2[] = {1,-1,3};
    int s2 = 0;
    struct TreeNode* r2 = build(a2, 3, 0);
    int* v2 = rightSideView(r2, &s2);
    for (int i = 0; i < s2; i++) printf("%d ", v2[i]);
    printf("\n");
    free(v2);
    freeTree(r2);
    return 0;
}
