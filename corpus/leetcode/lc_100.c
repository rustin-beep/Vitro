#include <stdio.h>
#include <stdlib.h>

struct TreeNode {
    int val;
    struct TreeNode* left;
    struct TreeNode* right;
};

int isSameTree(struct TreeNode* p, struct TreeNode* q) {
    if (p == NULL && q == NULL) return 1;
    if (p == NULL || q == NULL) return 0;
    if (p->val != q->val) return 0;
    return isSameTree(p->left, q->left) && isSameTree(p->right, q->right);
}

struct TreeNode* newNode(int val) {
    struct TreeNode* n = (struct TreeNode*)malloc(sizeof(struct TreeNode));
    n->val = val;
    n->left = NULL;
    n->right = NULL;
    return n;
}

void freeTree(struct TreeNode* root) {
    if (root == NULL) return;
    freeTree(root->left);
    freeTree(root->right);
    free(root);
}

int main() {
    struct TreeNode* p = newNode(1);
    p->left = newNode(2);
    p->right = newNode(3);
    struct TreeNode* q = newNode(1);
    q->left = newNode(2);
    q->right = newNode(3);
    printf("%d\n", isSameTree(p, q));
    freeTree(p); freeTree(q);

    p = newNode(1);
    p->left = newNode(2);
    q = newNode(1);
    q->right = newNode(2);
    printf("%d\n", isSameTree(p, q));
    freeTree(p); freeTree(q);

    p = newNode(1);
    p->left = newNode(2);
    p->right = newNode(1);
    q = newNode(1);
    q->left = newNode(1);
    q->right = newNode(2);
    printf("%d\n", isSameTree(p, q));
    freeTree(p); freeTree(q);

    return 0;
}
