#include <stdio.h>
#include <stdlib.h>

struct TreeNode {
    int val;
    struct TreeNode *left;
    struct TreeNode *right;
};

struct TreeNode* mergeTrees(struct TreeNode* root1, struct TreeNode* root2) {
    if (root1 == NULL && root2 == NULL) return NULL;
    struct TreeNode* node = (struct TreeNode*)malloc(sizeof(struct TreeNode));
    int v1 = root1 ? root1->val : 0;
    int v2 = root2 ? root2->val : 0;
    node->val = v1 + v2;
    struct TreeNode* l1 = root1 ? root1->left : (struct TreeNode*)0;
    struct TreeNode* l2 = root2 ? root2->left : (struct TreeNode*)0;
    struct TreeNode* r1 = root1 ? root1->right : (struct TreeNode*)0;
    struct TreeNode* r2 = root2 ? root2->right : (struct TreeNode*)0;
    node->left = mergeTrees(l1, l2);
    node->right = mergeTrees(r1, r2);
    return node;
}

void preorder(struct TreeNode* root, int* out, int* idx) {
    if (root == NULL) return;
    int i = *idx;
    out[i] = root->val;
    *idx = *idx + 1;
    preorder(root->left, out, idx);
    preorder(root->right, out, idx);
}

void freeTree(struct TreeNode* root) {
    if (root == NULL) return;
    freeTree(root->left);
    freeTree(root->right);
    free(root);
}

int main(void) {
    // root1 = [1,3,2,5], root2 = [2,1,3,null,4,null,7]
    struct TreeNode a[4], b[5];
    a[0].val = 1; a[0].left = &a[1]; a[0].right = &a[2];
    a[1].val = 3; a[1].left = &a[3]; a[1].right = NULL;
    a[2].val = 2; a[2].left = NULL; a[2].right = NULL;
    a[3].val = 5; a[3].left = NULL; a[3].right = NULL;

    b[0].val = 2; b[0].left = &b[1]; b[0].right = &b[2];
    b[1].val = 1; b[1].left = NULL; b[1].right = &b[3];
    b[2].val = 3; b[2].left = NULL; b[2].right = &b[4];
    b[3].val = 4; b[3].left = NULL; b[3].right = NULL;
    b[4].val = 7; b[4].left = NULL; b[4].right = NULL;

    struct TreeNode* root = mergeTrees(&a[0], &b[0]);
    int out[20], idx = 0;
    preorder(root, out, &idx);
    for (int i = 0; i < idx; i++) printf("%d ", out[i]);
    printf("\n");
    freeTree(root);
    return 0;
}
